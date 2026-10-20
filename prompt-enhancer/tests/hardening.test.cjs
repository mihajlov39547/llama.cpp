const { test } = require('node:test');
const assert = require('node:assert/strict');
const vm = require('node:vm');
const fs = require('node:fs');
const path = require('node:path');
const { read, tick, deferred, dom, contentHarness } = require('./helpers.cjs');

function editorFixture() {
  const fixture = dom();
  const ctx = vm.createContext({ ...fixture, setTimeout });
  vm.runInContext(read('editor.js'), ctx);
  return { ...fixture, api: ctx.PromptEnhancerEditor };
}
test('realistic ChatGPT fixture selects the composer, not unrelated editables', () => {
  const f = editorFixture(), e = f.element;
  f.document.body.append(e('div', { contenteditable: 'true', role: 'textbox' }, 'Unrelated'));
  const { editor } = f.composer(e('p', {}, 'Draft'));
  assert.equal(f.api.findEditor(), editor);
  assert.equal(f.api.readEditorText(editor), 'Draft');
});
test('nested ordered/unordered lists preserve hierarchy, start numbers and item values', () => {
  const f = editorFixture(), e = f.element;
  const { editor } = f.composer(e('ol', { start: '3' },
    e('li', {}, e('p', {}, 'Install'), e('ul', {},
      e('li', {}, e('p', {}, 'Use C:\\tools\\llama.exe')),
      e('li', {}, e('p', {}, 'See https://example.com/a?x=1&y=2'),
        e('ol', {}, e('li', {}, e('p', {}, 'Keep nested step')))))),
    e('li', { value: '7' }, e('p', {}, 'Finish'))));
  assert.equal(f.api.readEditorText(editor),
    '3. Install\n   - Use C:\\tools\\llama.exe\n   - See https://example.com/a?x=1&y=2\n     1. Keep nested step\n7. Finish');
});
test('multiple blank paragraphs, leading/trailing spaces and inline code survive', () => {
  const f = editorFixture(), e = f.element;
  const { editor } = f.composer(e('p', {}, e('br')), e('p', {}, e('br')),
    e('p', {}, '  Run ', e('code', {}, 'C:\\src\\file.js'), '  '),
    e('p', {}, e('br')), e('p', {}, e('br')));
  assert.equal(f.api.readEditorText(editor), '\n\n  Run C:\\src\\file.js  \n\n');
});
test('fenced code, PRE/CODE whitespace, URLs and literal Windows escapes survive exactly', () => {
  const f = editorFixture(), e = f.element;
  const source = '```js\nconst path = "C:\\\\new\\\\test.js";\n\tfetch("https://a.test/x?q=1&b=2");  \n\n```\n';
  const { editor } = f.composer(e('pre', {}, e('code', { class: 'language-js' }, source)));
  assert.equal(f.api.readEditorText(editor), source);
});
test('adapter preserves output indentation and blank lines while normalizing CRLF', async () => {
  const ctx = vm.createContext({ AbortController, setTimeout, clearTimeout, fetch });
  for (const file of ['settings.js', 'prompt-template.js', 'llama-api.js']) vm.runInContext(read(file), ctx);
  const result = await ctx.PromptEnhancerAPI.run('Keep this code', undefined, {
    fetchImpl: async url => ({ ok: true, json: async () => url.endsWith('/models') ?
      { data: [{ id: 'model' }] } :
      { choices: [{ message: { content: '  if (ready) {\r\n\tgo();\r\n  }\r\n\r\n' } }] } })
  });
  assert.equal(result.text, '  if (ready) {\n\tgo();\n  }\n\n');
});
test('literal code BR and hard breaks survive; only terminal editor placeholders disappear', () => {
  const f = editorFixture(), e = f.element;
  const { editor } = f.composer(
    e('pre', {}, e('code', {}, e('br'))),
    e('p', {}, 'first', e('br'), e('br'), 'last', e('br'),
      e('br', { class: 'ProseMirror-trailingBreak' })));
  assert.equal(f.api.readEditorText(editor), '\n\nfirst\n\nlast\n');
});
test('focus-triggered composer replacement aborts before any native edit', async () => {
  const f = editorFixture(), e = f.element;
  const { editor, form } = f.composer(e('p', {}, 'Draft'));
  editor.addEventListener('focus', () => {
    form.remove();
    f.composer(e('p', {}, 'Draft'));
  });
  f.document.execCommand = () => assert.fail('must not edit detached editor');
  await assert.rejects(f.api.replaceEditorText(editor, 'Draft', 'Rewrite', () => true), /before Apply/);
});
test('failure to focus the editor never invokes a native edit', async () => {
  const f = editorFixture(), { editor } = f.composer(f.element('p', {}, 'Draft'));
  editor.focus = () => {};
  f.document.execCommand = () => assert.fail('must not edit another focused control');
  await assert.rejects(f.api.replaceEditorText(editor, 'Draft', 'Rewrite', () => true), /receive focus/);
});
test('failed native command restores the original caret selection, without text rollback', async () => {
  const f = editorFixture(), { editor } = f.composer(f.element('p', {}, 'Draft'));
  const caret = f.document.createRange();
  caret.selectNodeContents(editor);
  caret.collapse(false);
  f.selection.addRange(caret);
  let calls = 0;
  f.document.execCommand = () => { calls++; return false; };
  await assert.rejects(f.api.replaceEditorText(editor, 'Draft', 'Rewrite', () => true), /use Copy/);
  assert.equal(calls, 1);
  assert.equal(f.selection.getRangeAt(0).collapsed, true);
  assert.equal(f.api.readEditorText(editor), 'Draft');
  assert.equal(editor.listeners.get('input').size, 0);
});
test('native replacement uses one insertText command, verifies text and does not refocus later', async () => {
  const f = editorFixture(), { editor } = f.composer(f.element('p', {}, 'Draft'));
  const other = f.element('button');
  f.document.body.append(other);
  const calls = [];
  f.document.execCommand = (...args) => {
    calls.push(args);
    editor.textContent = args[2]; // Simulates native editing only inside the test double.
    editor.emit('input');
    other.focus();
    return true;
  };
  await f.api.replaceEditorText(editor, 'Draft', 'New\n\nDraft', () => true);
  assert.deepEqual(calls, [['insertText', false, 'New\n\nDraft']]);
  assert.equal(f.document.activeElement, other);
  assert.equal(editor.listeners.get('input').size, 0);
});
test('input after native command invalidates verification even if final text matches', async () => {
  const f = editorFixture(), { editor } = f.composer(f.element('p', {}, 'Draft'));
  f.document.execCommand = () => {
    editor.textContent = 'Rewrite';
    queueMicrotask(() => editor.emit('input'));
    return true;
  };
  await assert.rejects(f.api.replaceEditorText(editor, 'Draft', 'Rewrite', () => true), /use Copy/);
  assert.equal(editor.listeners.get('input').size, 0);
});

function setupContent(config) {
  const f = contentHarness(config);
  f.composerState = f.composer(f.element('p', {}, 'Original draft'));
  f.load();
  return f;
}
test('mutation bursts settle without duplicate controls or changes to editor/Send placement', async () => {
  const f = setupContent();
  const { editor, body, form, send } = f.composerState;
  const editorParent = editor.parentElement, sendParent = send.parentElement;
  for (let n = 0; n < 30; n++) body.append(f.element('span', {}, 'unrelated'));
  await f.flushMutations();
  assert.equal(f.document.querySelectorAll('[data-prompt-enhancer-host]').length, 1);
  assert.equal(f.host().nextSibling, form);
  assert.equal(body.contains(f.host()), false);
  assert.equal(editor.parentElement, editorParent);
  assert.equal(send.parentElement, sendParent);
  f.load(); // Reinjection must dispose the old instance.
  await f.flushMutations();
  assert.equal(f.document.querySelectorAll('[data-prompt-enhancer-host]').length, 1);
  assert.equal(f.intervals.size, 1);
  f.ctx.__promptEnhancerCleanup();
  assert.equal(f.intervals.size, 0);
  assert.equal(f.document.listeners.get('input').size, 0);
});
test('composer recreation reuses one host and disables stale Apply', async () => {
  const f = setupContent(), host = f.host();
  f.improve().emit('click');
  await tick();
  f.messages[0].response.resolve({ ok: true, text: 'Rewrite' });
  await tick();
  assert.equal(f.control('Apply').disabled, false);
  f.composerState.form.remove();
  const next = f.composer(f.element('p', {}, 'Original draft'));
  await f.flushMutations();
  assert.equal(f.host(), host);
  assert.equal(host.nextSibling, next.form);
  assert.equal(f.control('Apply').disabled, true);
  assert.equal(f.preview(), 'Rewrite');
});
test('Cancel then immediate new request ignores both late success and late error', async () => {
  for (const reject of [false, true]) {
    const f = setupContent();
    f.improve().emit('click');
    await tick();
    const old = f.messages[0];
    f.control('Cancel').emit('click');
    f.improve().emit('click');
    await tick();
    const newer = f.messages.filter(message => message.type === 'PE_IMPROVE')[1];
    newer.response.resolve({ ok: true, text: 'New result' });
    await tick();
    if (reject) old.response.reject(new Error('old channel closed'));
    else old.response.resolve({ ok: true, text: 'Stale result' });
    await tick();
    assert.equal(f.preview(), 'New result');
    assert.equal(f.control('Apply').disabled, false);
    assert.equal(f.messages.filter(message => message.type === 'PE_IMPROVE').length, 2);
  }
});
test('cancel during settings read cannot dispatch a late inference request', async () => {
  const f = setupContent(), readSettings = deferred();
  f.chrome.storage.local.get = () => readSettings.promise;
  f.improve().emit('click');
  f.control('Cancel').emit('click');
  readSettings.resolve({});
  await tick();
  assert.equal(f.messages.filter(message => message.type === 'PE_IMPROVE').length, 0);
});
test('saved input limit is enforced by content and adapter using the same validator', async () => {
  const f = setupContent({ maxInputLength: 5 });
  vm.runInContext(read('llama-api.js'), f.ctx);
  assert.equal(f.ctx.PromptEnhancerAPI.validatePrompt, f.ctx.PromptEnhancerSettings.validatePrompt);
  f.improve().emit('click');
  await tick();
  assert.equal(f.messages.length, 0);
  assert.match(f.status(), /exceeds 5 characters/);
  assert.equal(f.improve().disabled, false);
  assert.throws(() => f.ctx.PromptEnhancerAPI.validatePrompt('Original draft',
    f.ctx.PromptEnhancerAPI.settings({ maxInputLength: 5 })), /exceeds 5 characters/);
});
test('duplicate Improve clicks during settings loading dispatch only one request', async () => {
  const f = setupContent(), storage = deferred();
  f.chrome.storage.local.get = () => storage.promise;
  f.improve().emit('click');
  f.improve().emit('click'); // Even programmatic delivery bypassing disabled is guarded.
  storage.resolve({});
  await tick();
  assert.equal(f.messages.filter(message => message.type === 'PE_IMPROVE').length, 1);
  assert.equal(f.improve().disabled, true);
  f.messages[0].response.resolve({ ok: true, text: 'Rewrite' });
  await tick();
  assert.equal(f.improve().disabled, false);
});
test('options and worker dependencies exist and options bounds come from shared settings', () => {
  const html = read('options.html'), background = read('background.js');
  const files = [...html.matchAll(/(?:src|href)="([^"]+)"/g)].map(match => match[1]);
  const imports = background.match(/importScripts\(([^)]+)\)/)[1];
  files.push(...[...imports.matchAll(/'([^']+)'/g)].map(match => match[1]));
  for (const file of files) assert.ok(fs.existsSync(path.join(__dirname, '../src', file)), file);
  const ctx = vm.createContext({});
  vm.runInContext(read('settings.js'), ctx);
  const elements = new Map();
  for (const id of ['status', 'baseUrl', 'temperature', 'maxTokens', 'maxInputLength', 'timeout', 'settings', 'test']) {
    elements.set(id, { addEventListener() {} });
  }
  ctx.document = { getElementById: id => elements.get(id) };
  ctx.chrome = { storage: { local: { get: async () => ({}) } } };
  vm.runInContext(read('options.js'), ctx);
  for (const [key, limit] of Object.entries(ctx.PromptEnhancerSettings.limits)) {
    const field = elements.get(key === 'timeoutMs' ? 'timeout' : key);
    const scale = key === 'timeoutMs' ? 1000 : 1;
    assert.equal(field.min, limit.min / scale);
    assert.equal(field.max, limit.max / scale);
  }
});
test('worker channel rejection enables explicit Retry but never resends automatically', async () => {
  const f = setupContent();
  f.improve().emit('click');
  await tick();
  f.messages[0].response.reject(new Error('Message port closed'));
  await tick();
  assert.match(f.status(), /Message port closed/);
  assert.equal(f.control('Retry').disabled, false);
  assert.equal(f.messages.length, 1);
  assert.equal(f.timers.size, 0);
});
test('watchdog cancels hung worker, enables Retry and ignores its eventual response', async () => {
  const f = setupContent();
  f.improve().emit('click');
  await tick();
  const first = f.messages[0];
  const watchdog = [...f.timers.values()].find(timer => timer.delay === f.ctx.PromptEnhancerSettings.responseTimeoutMs);
  watchdog.fn();
  assert.match(f.status(), /stopped responding/);
  assert.equal(f.control('Retry').disabled, false);
  assert.equal(f.messages.filter(message => message.type === 'PE_IMPROVE').length, 1);
  f.control('Retry').emit('click');
  await tick();
  const newer = f.messages.filter(message => message.type === 'PE_IMPROVE')[1];
  newer.response.resolve({ ok: true, text: 'Retry result' });
  await tick();
  first.response.resolve({ ok: true, text: 'Expired result' });
  await tick();
  assert.equal(f.preview(), 'Retry result');
});
test('editing then undoing while processing still disables Apply', async () => {
  const f = setupContent(), { editor } = f.composerState;
  f.improve().emit('click');
  await tick();
  editor.textContent = 'Changed';
  f.document.emit('input', { target: editor });
  editor.textContent = 'Original draft';
  f.document.emit('input', { target: editor });
  f.messages[0].response.resolve({ ok: true, text: 'Rewrite' });
  await tick();
  assert.equal(f.control('Apply').disabled, true);
  assert.equal(f.preview(), 'Rewrite');
});
test('bfcache departure cancels loading with a visible Retry explanation on return', async () => {
  const f = setupContent();
  f.improve().emit('click');
  await tick();
  f.window.emit('pagehide', { persisted: true });
  f.window.emit('pageshow');
  assert.match(f.status(), /Request cancelled/);
  assert.equal(f.improve().disabled, false);
  assert.equal(f.messages.filter(message => message.type === 'PE_IMPROVE').length, 1);
});
function workerHarness() {
  let listener;
  const calls = [];
  const chrome = {
    runtime: {
      id: 'test', getURL: file => `chrome-extension://test/${file}`,
      onInstalled: { addListener() {} }, onMessage: { addListener(fn) { listener = fn; } }
    },
    storage: { local: { get: async () => ({}) } },
    tabs: { onRemoved: { addListener() {} } }
  };
  const ctx = vm.createContext({ chrome, URL, AbortController, importScripts() {},
    PromptEnhancerAPI: { run(prompt, settings, options) {
      const result = deferred();
      calls.push({ prompt, ...options, result });
      return result.promise;
    } }
  });
  vm.runInContext(read('background.js'), ctx);
  function send(type, requestId) {
    const response = deferred();
    listener({ type, requestId, prompt: 'Draft' }, {
      id: 'test', frameId: 0, tab: { id: 1, url: 'https://chatgpt.com/' }, url: 'https://chatgpt.com/'
    }, response.resolve);
    return response.promise;
  }
  return { chrome, calls, send };
}
test('worker Cancel releases busy slot immediately; old finally cannot release newer request', async () => {
  const f = workerHarness();
  const old = f.send('PE_IMPROVE', 'old');
  await tick();
  f.send('PE_CANCEL', 'old');
  const newer = f.send('PE_IMPROVE', 'new');
  await tick();
  assert.equal(f.calls.length, 2);
  assert.equal(f.calls[0].signal.aborted, true);
  f.calls[0].result.resolve({ text: 'Stale' });
  assert.equal((await old).error.code, 'CANCELLED');
  await tick();
  assert.equal((await f.send('PE_IMPROVE', 'third')).error.code, 'BUSY');
  f.calls[1].result.resolve({ text: 'New' });
  assert.equal((await newer).text, 'New');
});
test('stale cancellation ID cannot abort a newer request', async () => {
  const f = workerHarness();
  const current = f.send('PE_IMPROVE', 'new');
  await tick();
  await f.send('PE_CANCEL', 'old');
  assert.equal(f.calls[0].signal.aborted, false);
  f.calls[0].result.resolve({ text: 'New' });
  assert.equal((await current).ok, true);
});
test('worker cancellation before storage resolves never calls inference', async () => {
  const f = workerHarness(), storage = deferred();
  f.chrome.storage.local.get = () => storage.promise;
  const result = f.send('PE_IMPROVE', 'early');
  await f.send('PE_CANCEL', 'early');
  storage.resolve({});
  assert.equal((await result).error.code, 'CANCELLED');
  assert.equal(f.calls.length, 0);
});
