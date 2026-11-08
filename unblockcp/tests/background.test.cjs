const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

function setup() {
  let listener;
  let settings = { mode: 'strong', css: true };
  const calls = [];
  const chrome = {
    runtime: { onMessage: { addListener(fn) { listener = fn; } } },
    storage: { local: { get: async () => ({ settings }) } },
    scripting: {
      async removeCSS(args) { calls.push(['remove', args]); },
      async insertCSS(args) { calls.push(['insert', args]); }
    }
  };
  vm.runInNewContext(fs.readFileSync(path.join(__dirname, '../background.js'), 'utf8'), { chrome });
  const sender = { tab: { id: 9 }, frameId: 3, documentId: 'document-a' };
  return { calls, chrome, setSettings(value) { settings = value; },
    send: () => new Promise(resolve => listener({ type: 'unblockcp:css' }, sender, resolve)) };
}

test('CSS is inserted as USER origin for the sending document, and removed when disabled', async () => {
  const env = setup();
  assert.equal((await env.send()).ok, true);
  assert.deepEqual(env.calls.map(item => item[0]), ['remove', 'insert']);
  const injection = env.calls[1][1];
  assert.equal(injection.origin, 'USER');
  assert.equal(injection.target.tabId, 9);
  assert.equal(injection.target.documentIds[0], 'document-a');
  env.setSettings({ mode: 'off', css: true });
  assert.equal((await env.send()).enabled, false);
  assert.equal(env.calls.at(-1)[0], 'remove');
  env.setSettings({ mode: 'strong', css: false });
  assert.equal((await env.send()).enabled, false);
});

test('CSS injection errors are returned to content script instead of reporting success', async () => {
  const env = setup();
  env.chrome.scripting.insertCSS = async () => { throw new Error('document navigated'); };
  const result = await env.send();
  assert.equal(result.ok, false);
  assert.equal(result.error, 'document navigated');
});
