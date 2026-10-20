const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { read, tick, deferred, dom, contentHarness } = require('./helpers.cjs');
const { runtimeFiles, validateReferences, buildZip, validateZip } = require('../scripts/build-release.cjs');

test('loading, mutation and typing do not extract draft text before Improve Prompt', async () => {
  const f = contentHarness();
  const { editor } = f.composer(f.element('p', {}, 'private draft'));
  let reads = 0;
  const originalRead = f.ctx.PromptEnhancerEditor.readEditorText;
  f.ctx.PromptEnhancerEditor.readEditorText = node => { reads++; return originalRead(node); };
  f.load();
  await f.flushMutations();
  f.document.emit('input', { target: editor });
  for (const fn of f.intervals.values()) fn();
  assert.equal(reads, 0);
  assert.equal(f.messages.length, 0);
  f.improve().emit('click');
  await tick();
  assert.ok(reads > 0);
  assert.equal(f.messages[0].prompt, 'private draft');
});
test('empty prompt is rejected on explicit click, without an API message', async () => {
  const f = contentHarness();
  f.composer(f.element('p', {}, f.element('br')));
  f.load();
  assert.equal(f.improve().disabled, false);
  f.improve().emit('click');
  await tick();
  assert.match(f.status(), /Enter a prompt/);
  assert.equal(f.messages.length, 0);
});
test('synthetic page clicks cannot authorize capturing a draft', async () => {
  const f = contentHarness();
  f.composer(f.element('p', {}, 'private draft'));
  let reads = 0;
  f.ctx.PromptEnhancerEditor.readEditorText = () => { reads++; return 'private draft'; };
  f.load();
  f.improve().emit('click', { isTrusted: false });
  await tick();
  assert.equal(reads, 0);
  assert.equal(f.messages.length, 0);
});
function statusWorker() {
  let listener;
  const calls = [];
  const ctx = vm.createContext({
    AbortController, setTimeout, clearTimeout, URL, importScripts() {},
    fetch: async (url, options) => {
      calls.push({ url, ...options });
      return { ok: true, json: async () => ({ data: [{ id: 'real-discovered-id' }] }) };
    },
    chrome: {
      runtime: { id: 'test', getURL: file => `chrome-extension://test/${file}`,
        onInstalled: { addListener() {} }, onMessage: { addListener(fn) { listener = fn; } } },
      storage: { local: { get: async () => ({}) } },
      tabs: { onRemoved: { addListener() {} } }
    }
  });
  for (const file of ['settings.js', 'prompt-template.js', 'llama-api.js', 'background.js']) vm.runInContext(read(file), ctx);
  const sender = { id: 'test', url: 'chrome-extension://test/src/popup.html' };
  const send = (message = {}, from = sender) => new Promise(resolve =>
    listener({ type: 'PE_STATUS', requestId: 'status-id', ...message }, from, resolve));
  return { calls, send, sender };
}
test('popup status performs model discovery only, even if message includes a draft', async () => {
  const f = statusWorker();
  const response = await f.send({ prompt: 'never send me', originalPrompt: 'also private', previousImprovement: 'private' });
  assert.equal(response.ok, true);
  assert.equal(response.model, 'real-discovered-id');
  assert.equal(response.endpoint, 'http://127.0.0.1:8080');
  assert.equal(f.calls.length, 1);
  assert.equal(f.calls[0].url, 'http://127.0.0.1:8080/v1/models');
  assert.equal(f.calls[0].method, 'GET');
  assert.equal(f.calls[0].body, undefined);
});
test('status sender isolation rejects website, options, wrong extension and spoofed popup URL', async () => {
  const f = statusWorker();
  for (const sender of [
    { id: 'test', url: 'https://chatgpt.com/', tab: { id: 1, url: 'https://chatgpt.com/' }, frameId: 0 },
    { id: 'test', url: 'chrome-extension://test/src/options.html' },
    { id: 'other', url: f.sender.url },
    { id: 'test', url: f.sender.url + '?spoof' }
  ]) assert.equal((await f.send({}, sender)).error.code, 'SENDER');
  assert.equal((await f.send({ type: 'PE_IMPROVE', prompt: 'draft' })).error.code, 'SENDER');
  assert.equal((await f.send({ type: 'PE_TEST' })).error.code, 'SENDER');
  assert.equal(f.calls.length, 0);
});
function popupHarness() {
  const f = dom(), requests = [], timers = new Map();
  const ids = ['status', 'model', 'detail', 'refresh', 'version', 'endpoint', 'settings'];
  const nodes = new Map(ids.map(id => [id, f.element('div', { id })]));
  f.document.getElementById = id => nodes.get(id);
  let optionsOpened = 0;
  const ctx = vm.createContext({
    document: f.document, crypto: { randomUUID: () => 'status-id' },
    setTimeout(fn) { const id = timers.size + 1; timers.set(id, fn); return id; },
    clearTimeout(id) { timers.delete(id); },
    chrome: { runtime: {
      getManifest: () => ({ version: '0.2.0' }),
      sendMessage(message) { const response = deferred(); requests.push({ message, response }); return response.promise; },
      openOptionsPage: async () => { optionsOpened++; }
    } }
  });
  vm.runInContext(read('settings.js'), ctx);
  vm.runInContext(read('popup.js'), ctx);
  return { nodes, requests, timers, get optionsOpened() { return optionsOpened; } };
}
test('popup shows checking/connected, renders model as text, and opens Settings', async () => {
  const f = popupHarness();
  assert.equal(f.nodes.get('status').textContent, 'Checking…');
  assert.equal(f.nodes.get('version').textContent, 'Version 0.2.0');
  assert.deepEqual(Object.keys(f.requests[0].message).sort(), ['requestId', 'type']);
  assert.equal(f.requests[0].message.type, 'PE_STATUS');
  f.nodes.get('refresh').emit('click');
  assert.equal(f.requests.length, 1);
  f.requests[0].response.resolve({ ok: true, model: '<script>not markup</script>', endpoint: 'http://127.0.0.1:8080' });
  await tick();
  assert.equal(f.nodes.get('status').textContent, 'Connected');
  assert.equal(f.nodes.get('model').textContent, '<script>not markup</script>');
  assert.equal(f.nodes.get('model').hidden, false);
  f.nodes.get('settings').emit('click');
  await tick();
  assert.equal(f.optionsOpened, 1);
});
test('popup disconnect and explicit refresh recover without automatic retries', async () => {
  const f = popupHarness();
  f.requests[0].response.resolve({ ok: false, error: { message: 'Server offline' } });
  await tick();
  assert.equal(f.nodes.get('status').textContent, 'Disconnected');
  assert.match(f.nodes.get('detail').textContent, /Server offline/);
  assert.equal(f.requests.length, 1);
  f.nodes.get('refresh').emit('click');
  f.requests[1].response.resolve({ ok: true, model: 'model' });
  await tick();
  assert.equal(f.nodes.get('status').textContent, 'Connected');
});
test('popup watchdog ignores late status after a new check', async () => {
  const f = popupHarness();
  [...f.timers.values()][0]();
  await tick();
  assert.equal(f.nodes.get('status').textContent, 'Disconnected');
  f.nodes.get('refresh').emit('click');
  f.requests[1].response.resolve({ ok: true, model: 'latest' });
  await tick();
  f.requests[0].response.resolve({ ok: true, model: 'stale' });
  await tick();
  assert.equal(f.nodes.get('model').textContent, 'latest');
});
test('runtime allowlist creates a valid reproducible ZIP with every manifest/page dependency', () => {
  const files = new Map(runtimeFiles.map(name => [name, fs.readFileSync(path.join(__dirname, '..', name))]));
  const manifest = validateReferences(files);
  assert.equal(manifest.version, '0.2.0');
  assert.deepEqual(manifest.permissions, ['storage', 'clipboardWrite']);
  const zip = buildZip(files), unpacked = validateZip(zip);
  assert.ok(zip.equals(buildZip(files)));
  assert.equal(unpacked.size, 20);
  for (const [name, content] of files) assert.ok(content.equals(unpacked.get(name)), name);
  assert.ok(![...unpacked.keys()].some(name => /(?:tests|docs|store|release|\.md|\.svg|\.ps1|gguf)/.test(name)));
});
test('package validator rejects missing runtime dependencies and unexpected files', () => {
  const files = new Map(runtimeFiles.map(name => [name, fs.readFileSync(path.join(__dirname, '..', name))]));
  files.delete('src/setup.html');
  assert.throws(() => validateReferences(files), /Missing packaged reference/);
  files.set('secret.env', Buffer.from('must never ship'));
  assert.throws(() => validateZip(buildZip(files)), /Unexpected/);
});
