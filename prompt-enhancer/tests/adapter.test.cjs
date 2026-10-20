const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const root = path.resolve(__dirname, '..');
function context(extra = {}) {
  const ctx = vm.createContext({ AbortController, setTimeout, clearTimeout, fetch, URL, ...extra });
  for (const file of ['settings.js', 'prompt-template.js', 'llama-api.js']) {
    vm.runInContext(fs.readFileSync(path.join(root, 'src', file), 'utf8'), ctx);
  }
  return ctx;
}
const json = data => ({ ok: true, status: 200, json: async () => data });
const models = () => json({ data: [{ id: 'discovered-model.gguf' }] });
function mockCompletion(response, calls = []) {
  return async (url, options) => {
    calls.push({ url, ...options });
    return url.endsWith('/models') ? models() : response;
  };
}
test('manifest is valid and every declared file exists; classic scripts parse', () => {
  const manifest = JSON.parse(fs.readFileSync(path.join(root, 'manifest.json')));
  assert.equal(manifest.manifest_version, 3);
  assert.deepEqual(manifest.host_permissions, ['http://127.0.0.1:8080/*']);
  const files = [manifest.background.service_worker, manifest.options_page, ...Object.values(manifest.icons || {}),
    ...manifest.content_scripts.flatMap(item => item.js),
    ...manifest.web_accessible_resources.flatMap(item => item.resources)];
  for (const file of files) assert.ok(fs.existsSync(path.join(root, file)), file);
  for (const file of fs.readdirSync(path.join(root, 'src')).filter(file => file.endsWith('.js'))) {
    new vm.Script(fs.readFileSync(path.join(root, 'src', file), 'utf8'), { filename: file });
  }
});
test('discovers model and sends independent non-streaming requests with complete instruction', async () => {
  const ctx = context(), calls = [];
  const fetchImpl = mockCompletion(json({ choices: [{ message: { content: 'Improved\nprompt' }, finish_reason: 'stop' }] }), calls);
  for (const prompt of ['fix this\nC:\\file.js', 'second prompt']) {
    const result = await ctx.PromptEnhancerAPI.run(prompt, undefined, { fetchImpl });
    assert.equal(result.text, 'Improved\nprompt');
    const request = JSON.parse(calls.at(-1).body);
    assert.equal(request.model, 'discovered-model.gguf');
    assert.equal(request.stream, false);
    assert.equal(request.temperature, 0.2);
    assert.equal(request.max_tokens, 2048);
    assert.equal(request.messages.length, 2);
    assert.equal(request.messages[0].content, ctx.PromptEnhancerInstruction);
    assert.match(request.messages[0].content, /12\. Return only/);
    assert.equal(request.messages[1].content, prompt);
    assert.equal(calls.at(-1).redirect, 'error');
  }
  assert.equal(calls.length, 4);
});
for (const [name, response, code] of [
  ['HTTP error', { ok: false, status: 503 }, 'HTTP'],
  ['invalid JSON', { ok: true, json: async () => { throw new SyntaxError(); } }, 'JSON'],
  ['empty content', json({ choices: [{ message: { content: ' ' } }] }), 'EMPTY'],
  ['invalid response shape', json({ choices: [] }), 'EMPTY'],
  ['stream chunk instead of completion', json({ choices: [{ delta: { content: 'wrong format' } }] }), 'EMPTY'],
  ['truncated completion', json({ choices: [{ finish_reason: 'length', message: { content: 'partial' } }] }), 'TRUNCATED']
]) {
  test(name, async () => {
    await assert.rejects(context().PromptEnhancerAPI.run('draft', undefined, {
      fetchImpl: mockCompletion(response)
    }), error => error.code === code);
  });
}
test('offline server', async () => {
  await assert.rejects(context().PromptEnhancerAPI.run('draft', undefined, {
    fetchImpl: async () => { throw new TypeError('fetch failed'); }
  }), error => error.code === 'NETWORK');
});
test('missing model and malformed model list', async () => {
  for (const data of [[], {}, null]) {
    await assert.rejects(context().PromptEnhancerAPI.run('draft', undefined, {
      fetchImpl: async () => json({ data })
    }), error => error.code === 'MODEL');
  }
});
test('invalid prompts fail before network access', async () => {
  for (const prompt of ['', '  ', 1, null, 'x'.repeat(20001)]) {
    await assert.rejects(context().PromptEnhancerAPI.run(prompt, undefined, {
      fetchImpl: () => { assert.fail('must not fetch'); }
    }), error => error.code === 'INPUT');
  }
});
test('fixed origin and bounded configuration', () => {
  const api = context().PromptEnhancerAPI;
  for (const config of [{ baseUrl: 'http://example.com' }, { timeoutMs: 61000 },
    { maxInputLength: 20001 }, { temperature: NaN }, { maxTokens: 0 }]) {
    assert.throws(() => api.settings(config), error => error.code === 'SETTINGS');
  }
});
test('timeout aborts fetch', async () => {
  await assert.rejects(context().PromptEnhancerAPI.run('draft', { timeoutMs: 1000 }, {
    fetchImpl: (_, { signal }) => new Promise((_, reject) => {
      signal.addEventListener('abort', () => reject(new Error('aborted')), { once: true });
    })
  }), error => error.code === 'TIMEOUT');
});
test('explicit cancellation', async () => {
  const controller = new AbortController();
  controller.abort();
  await assert.rejects(context().PromptEnhancerAPI.run('draft', undefined, {
    signal: controller.signal,
    fetchImpl: async (_, { signal }) => { signal.throwIfAborted(); }
  }), error => error.code === 'CANCELLED');
});
test('connectivity test only discovers model', async () => {
  let calls = 0;
  const result = await context().PromptEnhancerAPI.run(undefined, undefined, {
    testOnly: true, fetchImpl: async () => { calls++; return models(); }
  });
  assert.equal(result.model, 'discovered-model.gguf');
  assert.equal(calls, 1);
});

// Minimal DOM fixtures test serialization and replacement guards, not Chrome/ProseMirror integration.
const text = nodeValue => ({ nodeType: 3, nodeValue });
function el(tagName, ...children) {
  return {
    nodeType: 1, tagName, childNodes: children,
    lastChild: children.at(-1), classList: { contains: () => false }
  };
}
function editorContext(editor, command = () => true) {
  const ctx = vm.createContext({
    setTimeout, document: {
      querySelectorAll: () => [editor], execCommand: command,
      createRange: () => ({ selectNodeContents() {}, collapse() {} })
    },
    window: { getSelection: () => ({ removeAllRanges() {}, addRange() {} }) }
  });
  Object.assign(editor, {
    isConnected: true, getClientRects: () => [1], closest: () => null,
    focus() { ctx.document.activeElement = editor; }, contains: node => node === editor,
    addEventListener() {}, removeEventListener() {}
  });
  vm.runInContext(fs.readFileSync(path.join(root, 'src/editor.js'), 'utf8'), ctx);
  return ctx.PromptEnhancerEditor;
}
test('paragraphs, blank lines, hard breaks, inline code and whitespace are preserved', () => {
  const editor = el('DIV', el('P', el('BR')), el('P', text('first'), el('BR'), text('second')),
    el('P', el('BR')), el('P', el('CODE', text('  C:\\file.js  '))));
  assert.equal(editorContext(editor).readEditorText(editor), '\nfirst\nsecond\n\n  C:\\file.js  ');
});
test('stale draft cannot invoke native replacement', async () => {
  const editor = el('DIV', el('P', text('new draft')));
  const api = editorContext(editor, () => assert.fail('must not edit'));
  await assert.rejects(api.replaceEditorText(editor, 'old draft', 'rewrite', () => true), /draft changed/);
});
test('failed native edit produces Copy fallback', async () => {
  const editor = el('DIV', el('P', text('draft')));
  const api = editorContext(editor, () => false);
  await assert.rejects(api.replaceEditorText(editor, 'draft', 'rewrite', () => true), /use Copy/);
  assert.equal(api.readEditorText(editor), 'draft');
});
test('replacement verification detects subsequent editor reconciliation', async () => {
  const editor = el('DIV', el('P', text('draft')));
  const api = editorContext(editor, () => {
    editor.childNodes = [el('P', text('rewrite'))];
    setTimeout(() => { editor.childNodes = [el('P', text('draft'))]; }, 150);
    return true;
  });
  await assert.rejects(api.replaceEditorText(editor, 'draft', 'rewrite', () => true), /use Copy/);
});
test('worker rejects unexpected senders and message types without fetching', () => {
  let listener;
  const ctx = context({
    importScripts() {},
    chrome: {
      runtime: { id: 'test-id', getURL: file => `chrome-extension://test-id/${file}`,
        onInstalled: { addListener() {} }, onMessage: { addListener(fn) { listener = fn; } } },
      tabs: { onRemoved: { addListener() {} } }
    }
  });
  vm.runInContext(fs.readFileSync(path.join(root, 'src/background.js'), 'utf8'), ctx);
  assert.equal(listener({ type: 'UNKNOWN' }, {}, () => assert.fail()), false);
  for (const sender of [{}, { id: 'test-id', tab: { id: 1, url: 'https://chatgpt.com/' },
    frameId: 0, url: 'https://evil.example/' }]) {
    let response;
    listener({ type: 'PE_IMPROVE', requestId: '123', prompt: 'draft' }, sender, value => { response = value; });
    assert.equal(response.error.code, 'SENDER');
  }
});
