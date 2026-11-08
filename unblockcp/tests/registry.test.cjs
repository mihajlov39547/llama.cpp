const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const window = new EventTarget();
const document = new EventTarget();
const originalPreventDefault = Event.prototype.preventDefault;
vm.runInNewContext(fs.readFileSync(path.join(__dirname, '../listener-registry.js'), 'utf8'), {
  window, document, EventTarget, Event, WeakRef, console
});
const api = window.__unblockcpInspector;
function event(type, fields = {}) {
  const value = new Event(type, { cancelable: true });
  for (const [key, item] of Object.entries(fields)) Object.defineProperty(value, key, { value: item });
  return value;
}
function mode(value) { window.dispatchEvent(event('unblockcp:mode', { detail: value })); }
function record(name) { return api.report().listeners.find(item => item.name === name); }

test('detached global add/remove aliases use window for watched and unwatched events', () => {
  const add = window.addEventListener;
  const remove = window.removeEventListener;
  for (const type of ['keydown', 'visibilitychange']) {
    let calls = 0;
    function callback() { assert.equal(this, window); calls++; }
    add(type, callback);
    window.dispatchEvent(event(type));
    assert.equal(calls, 1);
    remove(type, callback);
    window.dispatchEvent(event(type));
    assert.equal(calls, 1);
  }
});

test('null/undefined receivers share window registration identity and capture handling', () => {
  const add = window.addEventListener;
  const remove = window.removeEventListener;
  for (const receiver of [null, undefined]) {
    let calls = 0;
    function callback() { calls++; }
    add.call(receiver, 'copy', callback, true);
    window.addEventListener('copy', callback, { capture: true });
    window.dispatchEvent(event('copy'));
    assert.equal(calls, 1);
    remove.call(receiver, 'copy', callback, { capture: true });
    window.dispatchEvent(event('copy'));
    assert.equal(calls, 1);
  }
});

test('invalid receivers are rejected by native API without allocating a registry entry', () => {
  const initial = api.report().total;
  for (const receiver of [0, false, 'invalid', {}]) {
    assert.throws(() => EventTarget.prototype.addEventListener.call(receiver, 'copy', () => {}), TypeError);
    assert.throws(() => EventTarget.prototype.removeEventListener.call(receiver, 'copy', () => {}), TypeError);
  }
  assert.equal(api.report().total, initial);
});

test('named and anonymous blockers can be disabled and restored without removing benign listeners', () => {
  mode('selective');
  const target = new EventTarget();
  let benignCalls = 0;
  function blockCopy(e) { e.preventDefault(); }
  const anonymous = (0, e => e.preventDefault());
  target.addEventListener('copy', blockCopy);
  target.addEventListener('copy', anonymous);
  target.addEventListener('copy', () => benignCalls++);
  assert.equal(target.dispatchEvent(event('copy')), false);
  const rows = api.report().listeners;
  assert.ok(record('blockCopy'));
  for (const row of rows) api.setDisabled(row.id, true);
  assert.equal(target.dispatchEvent(event('copy')), true);
  assert.equal(benignCalls, 2);
  api.restore();
  assert.equal(target.dispatchEvent(event('copy')), false);
  target.removeEventListener('copy', blockCopy);
  target.removeEventListener('copy', anonymous);
});

test('disabling a keyboard blocker preserves unrelated keys, Meta is protected, off restores behavior', () => {
  const target = new EventTarget();
  let calls = 0;
  function blockKeys(e) { calls++; e.preventDefault(); }
  target.addEventListener('keydown', blockKeys);
  target.dispatchEvent(event('keydown', { metaKey: true, code: 'KeyV' }));
  api.setDisabled(record('blockKeys').id, true);
  assert.equal(target.dispatchEvent(event('keydown', { metaKey: true, code: 'KeyV' })), true);
  assert.equal(calls, 1);
  assert.equal(target.dispatchEvent(event('keydown', { code: 'ArrowLeft' })), false);
  assert.equal(calls, 2);
  // AltGr characters must still reach the application.
  target.dispatchEvent(event('keydown', { ctrlKey: true, altKey: true, code: 'Digit1', getModifierState: () => true }));
  assert.equal(calls, 3);
  mode('off');
  assert.equal(target.dispatchEvent(event('keydown', { ctrlKey: true, code: 'KeyC' })), false);
  mode('selective');
  target.removeEventListener('keydown', blockKeys);
});

test('removeEventListener keeps original reference and capture matching', () => {
  const target = new EventTarget();
  let calls = 0;
  function callback(e) { calls++; e.preventDefault(); }
  target.addEventListener('paste', callback, true);
  target.addEventListener('paste', callback, false);
  target.removeEventListener('paste', callback, { capture: true });
  target.dispatchEvent(event('paste'));
  assert.equal(calls, 1);
  target.removeEventListener('paste', callback);
  assert.equal(target.dispatchEvent(event('paste')), true);
});

test('duplicate registrations and handleEvent receiver follow native behavior', () => {
  const target = new EventTarget();
  const handler = { calls: 0, handleEvent(e) { this.calls++; e.preventDefault(); } };
  target.addEventListener('cut', handler);
  target.addEventListener('cut', handler, { once: true });
  target.dispatchEvent(event('cut'));
  target.dispatchEvent(event('cut'));
  assert.equal(handler.calls, 2);
  target.removeEventListener('cut', handler);
  assert.equal(target.dispatchEvent(event('cut')), true);
});

test('once and abort do not leave active registry entries', () => {
  const target = new EventTarget();
  let calls = 0;
  function onceBlock(e) { calls++; e.preventDefault(); }
  target.addEventListener('contextmenu', onceBlock, { once: true });
  target.dispatchEvent(event('contextmenu'));
  target.dispatchEvent(event('contextmenu'));
  assert.equal(calls, 1);
  assert.equal(record('onceBlock'), undefined);
  const controller = new AbortController();
  function abortBlock(e) { e.preventDefault(); }
  target.addEventListener('selectstart', abortBlock, { signal: controller.signal });
  target.dispatchEvent(event('selectstart'));
  assert.ok(record('abortBlock'));
  controller.abort();
  assert.equal(target.dispatchEvent(event('selectstart')), true);
  assert.equal(record('abortBlock'), undefined);
  target.addEventListener('selectstart', abortBlock, { signal: controller.signal });
  assert.equal(target.dispatchEvent(event('selectstart')), true);
});

test('beforeinput disable applies only to paste, input handlers remain untouched', () => {
  const target = new EventTarget();
  function blockBefore(e) { e.preventDefault(); }
  target.addEventListener('beforeinput', blockBefore);
  target.dispatchEvent(event('beforeinput', { inputType: 'insertFromPaste' }));
  api.setDisabled(record('blockBefore').id, true);
  assert.equal(target.dispatchEvent(event('beforeinput', { inputType: 'insertFromPaste' })), true);
  assert.equal(target.dispatchEvent(event('beforeinput', { inputType: 'insertText' })), false);
  let inputs = 0;
  target.addEventListener('input', () => inputs++);
  target.dispatchEvent(event('input'));
  assert.equal(inputs, 1);
  target.removeEventListener('beforeinput', blockBefore);
});

test('saved native cancellation is detected and functions retain the event target as this', () => {
  const target = new EventTarget();
  function legacyBlock(e) { assert.equal(this, target); originalPreventDefault.call(e); }
  target.addEventListener('dragstart', legacyBlock);
  assert.equal(target.dispatchEvent(event('dragstart')), false);
  assert.ok(record('legacyBlock'));
  target.removeEventListener('dragstart', legacyBlock);
});

test('manifest references exist and injection worlds are separated', () => {
  const root = path.join(__dirname, '..');
  const manifest = JSON.parse(fs.readFileSync(path.join(root, 'manifest.json')));
  for (const script of manifest.content_scripts) {
    for (const file of [...(script.js || []), ...(script.css || [])]) assert.ok(fs.existsSync(path.join(root, file)));
  }
  assert.equal(manifest.content_scripts[0].world, 'MAIN');
  assert.ok(manifest.permissions.includes('scripting'));
  assert.ok(fs.existsSync(path.join(root, manifest.background.service_worker)));
  assert.ok(fs.existsSync(path.join(root, manifest.action.default_popup)));
});
