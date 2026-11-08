const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

async function setup(mode = 'strong') {
  const handlers = new Map();
  const calls = [];
  let settingsChanged;
  const active = { tagName: 'TEXTAREA', selectionStart: 1, selectionEnd: 4, selectionDirection: 'forward',
    focus() { calls.push(['focus']); }, setSelectionRange(...args) { calls.push(['selection', ...args]); } };
  const createElement = () => ({ style: {}, setAttribute() {}, remove() {}, focus() {}, select() {},
    attachShadow() { return { append() {} }; } });
  const selection = { rangeCount: 0, toString: () => 'selected', removeAllRanges() {}, addRange() {} };
  const document = {
    activeElement: active, body: { innerText: 'Page text' }, createElement,
    documentElement: { append(node) { node.isConnected = true; } },
    execCommand(command, ui, value) {
      calls.push([command, value]);
      if (command === 'paste') handlers.get('paste')({ stopImmediatePropagation() {}, preventDefault() {},
        clipboardData: { getData: () => '<b>literal</b>' } });
      return true;
    }
  };
  const window = { addEventListener(type, fn) { handlers.set(type, fn); }, dispatchEvent() {}, getSelection: () => selection };
  const chrome = {
    runtime: { sendMessage: async () => ({ ok: true }) },
    storage: { local: { get: async () => ({ settings: { mode, css: true } }) },
      onChanged: { addListener(fn) { settingsChanged = fn; } } }
  };
  vm.runInNewContext(fs.readFileSync(path.join(__dirname, '../content.js'), 'utf8'), {
    document, window, chrome, console, setTimeout: () => 1, clearTimeout() {},
    CustomEvent: class { constructor(type, args) { this.type = type; this.detail = args.detail; } },
    unblockcpCSS: { setEnabled(value) { calls.push(['css', value]); } }
  });
  await Promise.resolve();
  function key(code, fields = {}) {
    const e = { code, ctrlKey: true, altKey: true,
      preventDefault() { this.prevented = true; }, stopImmediatePropagation() { this.stopped = true; }, ...fields };
    handlers.get('keydown')(e);
    return e;
  }
  return { calls, key, handlers, active, settingsChanged };
}

test('four shortcuts route to selection, page text, plain paste and native rich paste', async () => {
  const { calls, key } = await setup();
  key('Digit1');
  assert.equal(calls.at(-1)[0], 'copy');
  key('Digit2');
  assert.deepEqual(calls.at(-1), ['selection', 1, 4, 'forward']);
  assert.equal(calls.filter(item => item[0] === 'copy').length, 2);
  key('Digit3');
  assert.deepEqual(calls.slice(-2), [['paste', undefined], ['insertText', '<b>literal</b>']]);
  key('Digit4');
  assert.deepEqual(calls.at(-1), ['paste', undefined]);
});

test('selective mode leaves ordinary events to the page; strong blocks handlers but keeps default', async () => {
  const { key, handlers, settingsChanged } = await setup('selective');
  assert.equal(key('KeyV', { altKey: false }).stopped, undefined);
  const paste = { stopImmediatePropagation() { this.stopped = true; } };
  handlers.get('paste')(paste);
  assert.equal(paste.stopped, undefined);
  settingsChanged({ settings: { newValue: { mode: 'strong' } } }, 'local');
  const standard = key('KeyV', { altKey: false });
  assert.equal(standard.stopped, true);
  assert.equal(standard.prevented, undefined);
  handlers.get('paste')(paste);
  assert.equal(paste.stopped, true);
});

test('off, readonly, repeat and AltGr guards prevent shortcut mutations', async () => {
  const { calls, key, active, settingsChanged } = await setup();
  const initial = calls.length;
  active.readOnly = true;
  key('Digit3');
  active.readOnly = false;
  key('Digit1', { repeat: true });
  key('Digit1', { getModifierState: () => true });
  assert.equal(calls.length, initial);
  settingsChanged({ settings: { newValue: { mode: 'off' } } }, 'local');
  assert.deepEqual(calls.at(-1), ['css', false]);
  const afterOff = calls.length;
  assert.equal(key('Digit1').prevented, undefined);
  assert.equal(calls.length, afterOff);
});
