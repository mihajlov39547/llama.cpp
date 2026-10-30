const { test } = require('node:test');
const assert = require('node:assert/strict');
const vm = require('node:vm');
const { dom, read, contentHarness, tick } = require('./helpers.cjs');

function fixture() {
  const f = dom();
  f.document.title = 'Istraživanje GPU-a - ChatGPT';
  const location = { href: 'https://chatgpt.com/c/chat-123?private=omit' };
  const ctx = vm.createContext({ ...f, location, URL, Blob, AbortController, setTimeout, clearTimeout, TextEncoder,
    getComputedStyle: () => ({ overflowY: 'auto' }) });
  vm.runInContext(read('chat-export.js'), ctx);
  const root = f.element('div', { 'data-thread-find-target': 'conversation',
    'data-chatgpt-conversation-selection-target': 'local-chatgpt:local-id' });
  f.document.body.append(root);
  function pair(index, question = 'Pitanje', answer = 'Odgovor') {
    const user = f.element('div', { 'data-chatgpt-search-unit-key': `fallback-turn-${index}:0:user`,
      'data-chatgpt-search-message-ids': `user-${index}` },
      f.element('div', { 'data-user-message-bubble': 'true' },
        f.element('svg', {}, 'ICON'), f.element('div', {}, question)),
      f.element('button', {}, 'Copy message'));
    const assistant = f.element('div', { 'data-content-search-unit-key': `fallback-turn-${index}:2:assistant`,
      'data-chatgpt-search-message-ids': `answer-${index} answer-${index}` },
      f.element('h4', { 'data-conversation-role': 'assistant', class: 'sr-only' }, 'ChatGPT said:'),
      f.element('div', { 'data-markdown-text-style': 'assistant-message' },
        f.element('div', { hidden: '' }, 'HIDDEN'),
        f.element('p', {}, f.element('span', { 'data-d-stream-word': '' }, answer))),
      f.element('button', {}, 'Read aloud'));
    return [user, assistant];
  }
  return { ...f, ctx, root, location, pair, api: ctx.PromptEnhancerExport };
}

test('supplied search-unit structure exports both roles in order without controls or duplicate headings', () => {
  const f = fixture();
  f.root.append(...f.pair(0, 'What is happening?', 'Could you clarify?'),
    ...f.pair(1, 'pričaj mi o istoriji', 'Pregledao sam istoriju.'));
  const messages = f.api.collect();
  assert.deepEqual(Array.from(messages, message => message.role), ['user', 'assistant', 'user', 'assistant']);
  assert.deepEqual(Array.from(messages, message => message.text),
    ['What is happening?', 'Could you clarify?', 'pričaj mi o istoriji', 'Pregledao sam istoriju.']);
  const result = f.api.documentMarkdown(f.api.metadata(), messages, false);
  assert.match(result, /^# Istraživanje GPU-a/);
  assert.match(result, /## You\n\nWhat is happening\?/);
  assert.doesNotMatch(result, /HIDDEN|ICON|Copy message|Read aloud|private=omit/);
});

test('classic role markup exports once and excludes hidden alternate branches and draft', () => {
  const f = fixture(), e = f.element;
  f.root.append(e('article', {}, e('div', { 'data-message-author-role': 'assistant', 'data-message-id': 'a' },
    e('div', { class: 'markdown' }, e('p', {}, 'Answer')))),
    e('article', { hidden: '' }, e('div', { 'data-message-author-role': 'user' }, 'Hidden branch')));
  f.composer(e('p', {}, 'UNSENT DRAFT'));
  assert.equal(f.api.collect().length, 1);
  assert.equal(f.api.collect()[0].text, 'Answer');
});

test('Markdown preserves DIL emphasis, headings, links, lists, quotes, tables and fenced code', () => {
  const f = fixture(), e = f.element;
  const body = e('div', {},
    e('h2', {}, 'Tema'),
    e('p', {}, e('span', { 'data-d-default-strong': '' }, 'važno '),
      e('span', { 'data-d-font-style': 'italic' }, 'zašto'), ' ',
      e('a', { href: 'https://example.com/docs' }, 'izvor')),
    e('ul', {}, e('li', {}, 'Prvo', e('ul', {}, e('li', {}, 'Podstavka')))),
    e('ol', { start: '3' }, e('li', {}, 'Treće')),
    e('blockquote', {}, e('p', {}, 'Citat')),
    e('pre', {}, e('button', {}, 'Copy code'), e('code', { class: 'language-js' }, 'const path = "C:\\tmp";\n\n\n```\n')),
    e('table', {}, e('tr', {}, e('th', {}, 'A'), e('th', {}, 'B')),
      e('tr', {}, e('td', {}, 'x|y'), e('td', {}, 'z'))));
  const md = f.api.markdown(body);
  assert.match(md, /## Tema/);
  assert.match(md, /\*\*važno\*\* \*zašto\*/);
  assert.match(md, /\[izvor\]\(<https:\/\/example.com\/docs>\)/);
  assert.match(md, /- Prvo\n[\s\n]*  - Podstavka/);
  assert.match(md, /3\. Treće/);
  assert.match(md, /> Citat/);
  assert.ok(md.includes('````js\nconst path = "C:\\tmp";\n\n\n```\n````'));
  assert.ok(md.includes('| A | B |\n| --- | --- |\n| x\\|y | z |'));
  assert.doesNotMatch(md, /Copy code/);
});

test('unsafe URLs are not exported as active links and user Markdown stays literal', () => {
  const f = fixture(), e = f.element;
  assert.equal(f.api.markdown(e('a', { href: 'javascript:alert(1)' }, 'label')), 'label');
  const text = '# My prompt\n\n```python\n  print("x")\n```';
  assert.equal(f.api.markdown(e('div', {}, text), true), text);
});

test('filenames are safe on Windows and title falls back to route or local conversation ID', () => {
  const f = fixture();
  assert.equal(f.api.filename('Tema: GPU / CPU?'), 'Tema_ GPU _ CPU_.md');
  assert.equal(f.api.filename('CON'), '_CON.md');
  assert.equal(f.api.filename(' .. '), 'ChatGPT conversation.md');
  assert.equal(f.api.filename('Ćirilica и ћирилица'), 'Ćirilica и ћирилица.md');
  f.document.title = 'ChatGPT';
  assert.equal(f.api.metadata().title, 'chat-123');
  f.location.href = 'https://chatgpt.com/';
  assert.equal(f.api.metadata().title, 'local-id');
});

function message(id, role, text, parent) {
  return { id, parent, message: { id, author: { role }, content: { content_type: 'text', parts: [text] } } };
}
function mockAPI(f, data, imageOK = true) {
  f.ctx.fetch = async (url, options) => {
    if (url === '/api/auth/session') return { ok: true, json: async () => ({ accessToken: 'PRIVATE_TOKEN' }) };
    if (String(url).startsWith('/backend-api/')) {
      assert.equal(options.headers.Authorization, 'Bearer PRIVATE_TOKEN');
      if (String(url).includes('/files/download/')) return { ok: true, json: async () => ({ download_url: 'https://files.oaiusercontent.com/image' }) };
      return { ok: true, json: async () => data };
    }
    assert.equal(options.headers, undefined);
    assert.equal(options.credentials, 'omit');
    if (!imageOK) throw new Error('CORS');
    let done = false;
    return { ok: true, headers: { get: () => 'image/png' }, body: { getReader: () => ({
      read: async () => done ? { done: true } : (done = true, { value: new Uint8Array([137,80,78,71]), done: false }),
      cancel: async () => {}
    }) } };
  };
}

test('full saved branch exports 248 messages without DOM scrolling and excludes alternative branches', async () => {
  const f = fixture(), mapping = {};
  for (let i = 0; i < 248; i++) mapping[i] = message(String(i), i % 2 ? 'assistant' : 'user', `Message ${i}`, i ? String(i - 1) : null);
  mapping.other = message('other', 'assistant', 'WRONG BRANCH', '0');
  mockAPI(f, { title: 'AES nestabilnost', mapping, current_node: '247' });
  const result = await f.api.exportChat();
  assert.equal(result.count, 248);
  assert.ok(result.markdown.indexOf('Message 0') < result.markdown.indexOf('Message 247'));
  assert.doesNotMatch(result.markdown, /WRONG BRANCH|PRIVATE_TOKEN/);
});

test('pagination prepends older messages and deduplicates overlapping IDs', async () => {
  const f = fixture();
  const old = message('a', 'user', 'First', null).message, recent = message('b', 'assistant', 'Last', null).message;
  const requests = [];
  f.ctx.fetch = async url => {
    requests.push(url);
    const data = url.includes('session') ? { accessToken: 'TOKEN' } : url.includes('before=') ?
      { messages: [old, recent], page_info: { has_previous_page: false, has_next_page: true } } :
      { title: 'Paged', messages: [recent], page_info: { has_previous_page: true, has_next_page: false, start_cursor: 'b' } };
    return { ok: true, json: async () => data };
  };
  const result = await f.api.exportChat();
  assert.equal(result.count, 2);
  assert.ok(result.markdown.indexOf('First') < result.markdown.indexOf('Last'));
  assert.match(requests[2], /before=b/);
});

test('uploaded and generated images are packaged once and text continues after image failures', async () => {
  for (const success of [true, false]) {
    const f = fixture();
    const mapping = { a: message('a', 'user', 'Before', null), b: message('b', 'tool', 'PRIVATE TOOL LOG', 'a'), c: message('c', 'assistant', 'After image', 'b') };
    for (const id of ['a', 'b']) mapping[id].message.content.parts.push({ content_type: 'image_asset_pointer', asset_pointer: 'sediment://file_123' });
    mockAPI(f, { title: 'Images', mapping, current_node: 'c' }, success);
    const result = await f.api.exportChat();
    assert.equal(result.filename, 'Images.zip');
    assert.match(result.markdown, /After image/);
    assert.doesNotMatch(result.markdown, /PRIVATE TOOL LOG|PRIVATE_TOKEN/);
    assert.equal(result.imageCount, success ? 1 : 0);
    assert.equal(result.warnings, success ? 0 : 1);
    if (success) assert.equal(result.markdown.split('export-files/image-001.png').length - 1, 2);
    const zip = Buffer.from(await result.blob.arrayBuffer());
    assert.equal(zip.readUInt32LE(0), 0x04034b50);
    assert.equal(zip.readUInt32LE(zip.length - 22), 0x06054b50);
    assert.ok(zip.includes(Buffer.from(success ? 'export-files/image-001.png' : 'export-report.txt')));
  }
});

test('missing branch nodes and unfinished pages fail instead of producing partial files', async () => {
  const f = fixture();
  mockAPI(f, { mapping: { a: message('a', 'user', 'Hi', 'missing') }, current_node: 'a' });
  await assert.rejects(f.api.exportChat(), /Incomplete/);
  mockAPI(f, { messages: [], page_info: { has_next_page: true } });
  await assert.rejects(f.api.exportChat(), /confirm the end/);
});

test('cancellation, navigation and streaming prevent download', async () => {
  const f = fixture(), controller = new AbortController();
  controller.abort();
  await assert.rejects(f.api.exportChat({ signal: controller.signal }), /cancelled/i);
  f.ctx.fetch = async () => { f.location.href = 'https://chatgpt.com/c/other'; return { ok: true, json: async () => ({}) }; };
  await assert.rejects(f.api.exportChat(), /cancelled/i);
  f.root.append(f.element('div', { 'data-is-streaming': 'true' }));
  await assert.rejects(f.api.exportChat(), /finish/);
});

test('export UI requires a trusted click, sends nothing to AI and leaves draft untouched', async () => {
  const f = contentHarness();
  const composer = f.composer(f.element('p', {}, 'Private draft'));
  let exports = 0, downloads = 0;
  f.ctx.PromptEnhancerExport = {
    async exportChat() { exports++; return { filename: 'Chat.md', count: 2 }; },
    download() { downloads++; }
  };
  f.load();
  f.control('Export chat').emit('click', { isTrusted: false }); await tick();
  assert.equal(exports, 0);
  f.control('Export chat').emit('click'); await tick();
  assert.equal(exports, 1); assert.equal(downloads, 1);
  assert.equal(f.messages.length, 0);
  assert.equal(composer.editor.textContent, 'Private draft');
  assert.equal(f.control('Export chat').disabled, false);
});

test('download uses a UTF-8 Markdown blob, requested filename and delayed URL cleanup', async () => {
  const f = fixture();
  let blob, clicked, revoked, cleanup;
  f.ctx.URL = {
    createObjectURL(value) { blob = value; return 'blob:export-test'; },
    revokeObjectURL(value) { revoked = value; }
  };
  f.ctx.setTimeout = fn => { cleanup = fn; };
  f.document.createElement = tag => {
    const node = f.element(tag);
    node.click = () => { clicked = { href: node.href, filename: node.download }; };
    return node;
  };
  f.api.download({ markdown: '# Ćirilica и ћирилица\n', filename: 'Razgovor.md' });
  assert.deepEqual(clicked, { href: 'blob:export-test', filename: 'Razgovor.md' });
  assert.equal(blob.type, 'text/markdown;charset=utf-8');
  assert.equal(await blob.text(), '# Ćirilica и ћирилица\n');
  assert.equal(f.document.querySelectorAll('a').length, 0);
  assert.equal(revoked, undefined);
  cleanup();
  assert.equal(revoked, 'blob:export-test');
});
