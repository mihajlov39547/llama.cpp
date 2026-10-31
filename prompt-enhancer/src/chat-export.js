(() => {
  'use strict';
  const first = (root, selector) => root.querySelectorAll(selector)[0];
  const attr = (node, name) => node.getAttribute?.(name);
  const skipped = node => node.nodeType === 1 && (
    ['BUTTON', 'SVG', 'SCRIPT', 'STYLE', 'NOSCRIPT', 'INPUT', 'TEXTAREA'].includes(node.tagName) ||
    node.hidden || attr(node, 'aria-hidden') === 'true' || attr(node, 'data-conversation-role') ||
    attr(node, 'data-markdown-copy') === 'exclude' || node.classList.contains('sr-only'));
  const escapeText = text => text.replace(/\\/g, '\\\\').replace(/([`*_\[\]<>])/g, '\\$1')
    .replace(/^(\s*)(#{1,6}|>|[-+]|\d+[.)])(?=\s)/gm, '$1\\$2');
  function safeURL(value) {
    if (!value) return '';
    try {
      const url = new URL(value, location.href);
      return ['https:', 'http:', 'mailto:'].includes(url.protocol) ?
        url.href.replace(/[<>\s()]/g, char => encodeURIComponent(char)) : '';
    } catch { return ''; }
  }
  function markdown(root, plain = false) {
    function raw(node) {
      if (node.nodeType === 3) return node.nodeValue;
      if (node.nodeType !== 1 || skipped(node)) return '';
      if (node.tagName === 'BR') return '\n';
      return [...node.childNodes].map(raw).join('');
    }
    function read(node) {
      if (node.nodeType === 3) return plain ? node.nodeValue : escapeText(node.nodeValue);
      if (node.nodeType !== 1 || skipped(node)) return '';
      const tag = node.tagName;
      const children = () => [...node.childNodes].map(read).join('');
      if (tag === 'BR') return plain ? '\n' : '  \n';
      if (tag === 'PRE') {
        if (first(node, 'svg') && !first(node, 'code')) return '\n\n> Diagram: see the companion HTML report.\n\n';
        const code = first(node, 'code') || node;
        const text = raw(code).replace(/\r\n?/g, '\n');
        const longest = Math.max(0, ...(text.match(/`+/g) || []).map(run => run.length));
        const fence = '`'.repeat(Math.max(3, longest + 1));
        const language = (attr(code, 'class') || '').match(/\blanguage-([\w+-]+)/)?.[1] || '';
        return `\n\n${fence}${language}\n${text}${text.endsWith('\n') ? '' : '\n'}${fence}\n\n`;
      }
      if (tag === 'CODE') {
        const text = raw(node);
        const fence = '`'.repeat(Math.max(0, ...(text.match(/`+/g) || []).map(run => run.length)) + 1);
        const pad = /^[ `]|[ `]$/.test(text) ? ' ' : '';
        return `${fence}${pad}${text}${pad}${fence}`;
      }
      if (tag === 'UL' || tag === 'OL') {
        let number = Number(attr(node, 'start') || 1);
        return '\n\n' + [...node.childNodes].filter(child => child.tagName === 'LI').map(item => {
          if (attr(item, 'value') !== null) number = Number(attr(item, 'value'));
          const marker = tag === 'OL' ? `${number++}. ` : '- ';
          const text = [...item.childNodes].map(read).join('').trim();
          return marker + text.replace(/\n/g, '\n' + ' '.repeat(marker.length));
        }).join('\n') + '\n\n';
      }
      if (tag === 'TABLE') {
        const rows = [...node.querySelectorAll('tr')].map(row => [...row.childNodes]
          .filter(cell => ['TH', 'TD'].includes(cell.tagName))
          .map(cell => read(cell).trim().replace(/\|/g, '\\|').replace(/\n+/g, '<br>'))).filter(row => row.length);
        if (!rows.length) return '';
        const width = Math.max(...rows.map(row => row.length));
        const format = row => '| ' + Array.from({ length: width }, (_, i) => row[i] || '').join(' | ') + ' |';
        return '\n\n' + [format(rows[0]), format(Array(width).fill('---')), ...rows.slice(1).map(format)].join('\n') + '\n\n';
      }
      if (tag === 'IMG') {
        const alt = escapeText(attr(node, 'alt') || 'Image');
        const url = safeURL(attr(node, 'src') || '');
        return url ? `![${alt}](<${url}>)` : `[${alt}: image not embedded]`;
      }
      if (tag === 'HR' || attr(node, 'data-d-component') === 'divider') return '\n\n---\n\n';
      let text = children();
      const wrap = marker => text.trim() ? text.replace(/^(\s*)([\s\S]*?)(\s*)$/, (_, start, body, end) =>
        `${start}${marker}${body}${marker}${end}`) : text;
      if (['STRONG', 'B'].includes(tag) || attr(node, 'data-d-default-strong') !== null) return wrap('**');
      if (['EM', 'I'].includes(tag) || attr(node, 'data-d-font-style') === 'italic') return wrap('*');
      if (['DEL', 'S'].includes(tag)) return wrap('~~');
      if (tag === 'A') {
        const url = safeURL(attr(node, 'href') || '');
        return url ? `[${text.trim() || escapeText(url)}](<${url}>)` : text;
      }
      if (/^H[1-6]$/.test(tag)) return `\n\n${'#'.repeat(Number(tag[1]))} ${text.trim()}\n\n`;
      if (tag === 'BLOCKQUOTE') return '\n\n' + text.trim().replace(/^/gm, '> ') + '\n\n';
      if (tag === 'P') return '\n\n' + text + '\n\n';
      if (tag === 'DIV' && text) return '\n' + text + '\n';
      return text;
    }
    // Do not normalize internal whitespace: code, paths and user line breaks matter.
    return read(root).replace(/\r\n?/g, '\n').trim();
  }

  // Report cards are separate documents and may be absent from conversation JSON.
  // Report documents may be rendered in a portal outside the transcript.
  function reports(root = document, diagnostics = {}) {
    const groups = new Map(), pages = [], visited = new Set();
    Object.assign(diagnostics, { roots: 0, reportPages: 0, readableFrames: 0, inaccessibleFrames: 0, openShadowRoots: 0, researchCompletedMarkers: 0 });
    function walk(scope) {
      if (!scope || visited.has(scope)) return;
      visited.add(scope); diagnostics.roots++;
      for (const node of scope.querySelectorAll('*')) {
        if (node.closest('[hidden], [aria-hidden="true"], [inert], [data-prompt-enhancer-host]')) continue;
        if ([...node.childNodes].some(child => child.nodeType === 3 && /Research completed in\s/i.test(child.nodeValue || ''))) diagnostics.researchCompletedMarkers++;
        const classes = (attr(node, 'class') || '').split(/\s+/);
        if (classes.some(name => /(?:^|_)reportPage(?:_|$)/.test(name)) || attr(node, 'data-report-page') !== null) pages.push(node);
        if (node.shadowRoot) { diagnostics.openShadowRoots++; walk(node.shadowRoot); }
        if (node.tagName?.toLowerCase() === 'iframe') {
          try {
            const frameDocument = node.contentDocument;
            if (frameDocument?.documentElement) { diagnostics.readableFrames++; walk(frameDocument); }
            else diagnostics.inaccessibleFrames++;
          } catch { diagnostics.inaccessibleFrames++; }
        }
      }
    }
    walk(root);
    diagnostics.reportPages = pages.length;
    for (const page of pages) {
      let card = page;
      for (let parent = page.parentElement; parent && parent !== root; parent = parent.parentElement) {
        if (parent.querySelectorAll('button[aria-label="Export"]').length) { card = parent; break; }
      }
      if (!groups.has(card)) groups.set(card, []);
      groups.get(card).push(page);
    }
    const escapeHTML = text => String(text).replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]);
    const htmlTags = new Set('div span p h1 h2 h3 h4 h5 h6 strong b em i s del pre code blockquote ul ol li table thead tbody tfoot tr th td br hr sup sub a'.split(' '));
    const svgTags = new Set('svg g path rect circle ellipse line polyline polygon text tspan defs marker foreignobject'.split(' '));
    const svgAttrs = ['id', 'viewBox', 'width', 'height', 'x', 'y', 'x1', 'y1', 'x2', 'y2', 'cx', 'cy', 'r', 'rx', 'ry', 'd', 'points', 'transform', 'fill', 'stroke', 'stroke-width', 'text-anchor', 'markerWidth', 'markerHeight', 'markerUnits', 'refX', 'refY', 'orient', 'marker-start', 'marker-end'];
    function clean(node) {
      if (node.nodeType === 3) return escapeHTML(node.nodeValue);
      if (node.nodeType !== 1 || node.hidden || attr(node, 'aria-hidden') === 'true') return '';
      const tag = node.tagName.toLowerCase();
      if (['script', 'style', 'button', 'iframe', 'object', 'embed', 'input', 'textarea', 'link', 'meta', 'use', 'image', 'img'].includes(tag)) return '';
      const children = [...node.childNodes].map(clean).join('');
      if (!htmlTags.has(tag) && !svgTags.has(tag)) return children;
      let attrs = '';
      if (svgTags.has(tag)) {
        for (const key of svgAttrs) {
          const value = attr(node, key);
          if (value === null || value === undefined) continue;
          if (/url\(/i.test(value) && !/^url\(#[\w:.-]+\)$/.test(value)) continue;
          if (/[<>]/.test(value)) continue;
          attrs += ` ${key}="${escapeHTML(value)}"`;
        }
      }
      if (tag === 'a') {
        const href = safeURL(attr(node, 'href'));
        if (href) attrs += ` href="${escapeHTML(href)}" rel="noreferrer"`;
      }
      const outputTag = tag === 'foreignobject' ? 'foreignObject' : tag;
      return `<${outputTag}${attrs}>${children}</${outputTag}>`;
    }
    const seenReports = new Set(), result = [];
    for (const reportPages of groups.values()) {
      const title = first(reportPages[0], 'h1')?.textContent?.trim() || 'Research report';
      const body = reportPages.map(clean).join('\n');
      if (seenReports.has(body)) continue;
      seenReports.add(body);
      const note = 'Snapshot of report pages loaded in the conversation at export time. Open/expand the report and load all pages before exporting. Citation numbers without URLs and already-rendered formulas cannot be reconstructed from the page.';
      const text = reportPages.map(page => markdown(page)).join('\n\n');
      result.push({ title, markdown: `> ${note}\n\n${text}\n`, html: `<!doctype html><html><head><meta charset="utf-8"><meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; img-src 'none'; base-uri 'none'; form-action 'none'"><title>${escapeHTML(title)}</title><style>body{max-width:1000px;margin:32px auto;padding:0 20px;font:16px/1.6 system-ui;color:#222;background:white}table{border-collapse:collapse}td,th{border:1px solid #bbb;padding:8px}pre{overflow:auto;white-space:pre-wrap}svg{max-width:100%;height:auto}svg rect,svg polygon{fill:#ececff;stroke:#9370db}svg path{stroke:#444}svg foreignObject div{text-align:center}svg p{margin:0}aside{padding:12px;background:#eee}</style></head><body><aside>${escapeHTML(note)}</aside>${body}</body></html>` });
    }
    return result;
  }

  function conversationRoot() {
    return first(document, '[data-thread-find-target="conversation"]') ||
      first(document, '[data-chatgpt-conversation-selection-target]') || first(document, 'main') || document.body;
  }
  function collect(root = conversationRoot()) {
    const markers = root.querySelectorAll('[data-user-message-bubble="true"], [data-markdown-text-style="assistant-message"], [data-message-author-role], [data-conversation-role]');
    const bodies = new Set(), messages = [];
    for (const marker of markers) {
      if (marker.closest('[hidden], [aria-hidden="true"], [inert], [data-prompt-enhancer-host], form')) continue;
      const role = attr(marker, 'data-message-author-role') || attr(marker, 'data-conversation-role') ||
        (attr(marker, 'data-markdown-text-style') === 'assistant-message' ? 'assistant' : 'user');
      if (!['user', 'assistant'].includes(role)) continue;
      const wrapper = marker.closest('[data-chatgpt-search-unit-key], [data-content-search-unit-key], article, [data-testid^="conversation-turn-"]') || marker;
      let body = role === 'user' ? first(wrapper, '[data-user-message-bubble="true"]') :
        first(wrapper, '[data-markdown-text-style="assistant-message"], .markdown');
      if (!body && (attr(marker, 'data-message-author-role') || attr(marker, 'data-user-message-bubble') ||
        attr(marker, 'data-markdown-text-style'))) body = marker;
      if (!body || bodies.has(body) || body.closest('[hidden], [aria-hidden="true"], [inert]')) continue;
      bodies.add(body);
      const holder = body.closest('[data-message-id], [data-chatgpt-selection-message-id], [data-chatgpt-search-message-ids]');
      const id = holder && (attr(holder, 'data-message-id') || attr(holder, 'data-chatgpt-selection-message-id') ||
        attr(holder, 'data-chatgpt-search-message-ids')?.trim().split(/\s+/)[0]);
      const unit = body.closest('[data-chatgpt-search-unit-key], [data-content-search-unit-key]');
      const turn = body.closest('[data-turn-key], [data-testid^="conversation-turn-"]');
      const key = id || (unit && (attr(unit, 'data-chatgpt-search-unit-key') || attr(unit, 'data-content-search-unit-key'))) ||
        (turn && (attr(turn, 'data-turn-key') || attr(turn, 'data-testid')));
      const text = markdown(body, role === 'user');
      if (text) messages.push({ role, text, key: key ? `${role}:${key}` : null });
    }
    return messages;
  }
  function metadata() {
    const node = first(document, '[data-chatgpt-conversation-selection-target], [data-chatgpt-selection-conversation-id]');
    const domId = node && (attr(node, 'data-chatgpt-conversation-selection-target') || attr(node, 'data-chatgpt-selection-conversation-id'));
    const url = new URL(location.href);
    const id = url.pathname.match(/\/(?:c|share)\/([^/]+)/)?.[1] || domId?.replace(/^local-chatgpt:/, '') || '';
    const title = (document.title || '').replace(/\s*[-–—|]\s*ChatGPT\s*$/i, '').replace(/^ChatGPT\s*[-–—|]\s*/i, '').trim();
    return { title: title && !/^ChatGPT$/i.test(title) ? title : id || 'ChatGPT conversation', id, url: url.origin + url.pathname };
  }
  function filename(title) {
    let name = title.normalize('NFC').replace(/[<>:"/\\|?*\u0000-\u001f\u007f]/g, '_')
      .replace(/\s+/g, ' ').replace(/^[. ]+|[. ]+$/g, '');
    name = [...name].slice(0, 120).join('').replace(/[. ]+$/g, '') || 'ChatGPT conversation';
    if (/^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\.|$)/i.test(name)) name = '_' + name;
    return name + '.md';
  }
  function documentMarkdown(meta, messages, scanned) {
    return `# ${escapeText(meta.title)}\n\nSource: <${safeURL(meta.url)}>\n\n` +
      `> Exported from the loaded conversation${scanned ? ' after scrolling through it' : ''}. Messages not supplied by the page, other branches and attachment contents are not included.\n\n` +
      messages.map(item => `## ${item.role === 'user' ? 'You' : 'ChatGPT'}\n\n${item.text}`).join('\n\n---\n\n') + '\n';
  }
  // Read the saved branch, never infer completeness from virtualized DOM nodes.
  function branch(data) {
    if (Array.isArray(data.messages)) {
      if (data.page_info?.has_previous_page || data.page_info?.has_next_page)
        throw new Error('Conversation is incomplete. No partial file was downloaded.');
      return data.messages.map(item => item.message || item);
    }
    if (data.page_info?.has_previous_page || data.page_info?.has_next_page) throw new Error('Incomplete conversation branch.');
    if (!data.mapping || !data.current_node) throw new Error('Unsupported conversation response.');
    const seen = new Set(), ordered = [];
    let id = data.current_node;
    while (id) {
      if (seen.has(id) || !Object.hasOwn(data.mapping, id)) throw new Error('Incomplete conversation branch.');
      seen.add(id);
      const node = data.mapping[id];
      if (node.message) ordered.push(node.message);
      id = node.parent;
    }
    return ordered.reverse();
  }

  // Stored ZIP: image formats are already compressed. UTF-8 names, CRC32,
  // central directory and relative paths make the folder portable/offline.
  function archive(files) {
    const encoder = new TextEncoder(), parts = [], directory = [];
    let offset = 0, directorySize = 0;
    for (const [name, value] of files) {
      if (name.startsWith('/') || name.split('/').includes('..') || name.includes('\\')) throw new Error('Unsafe archive path.');
      const data = typeof value === 'string' ? encoder.encode(value) : value;
      const label = encoder.encode(name);
      let crc = 0xffffffff;
      for (const byte of data) {
        crc ^= byte;
        for (let bit = 0; bit < 8; bit++) crc = (crc >>> 1) ^ ((crc & 1) ? 0xedb88320 : 0);
      }
      const header = new Uint8Array(30), h = new DataView(header.buffer);
      h.setUint32(0, 0x04034b50, true); h.setUint16(4, 20, true);
      h.setUint16(6, 0x800, true); h.setUint16(12, 33, true);
      h.setUint32(14, (crc ^ 0xffffffff) >>> 0, true);
      h.setUint32(18, data.length, true); h.setUint32(22, data.length, true);
      h.setUint16(26, label.length, true);
      const entry = new Uint8Array(46), e = new DataView(entry.buffer);
      e.setUint32(0, 0x02014b50, true); e.setUint16(4, 20, true);
      entry.set(header.subarray(4), 6); e.setUint32(42, offset, true);
      parts.push(header, label, data); directory.push(entry, label);
      offset += 30 + label.length + data.length; directorySize += 46 + label.length;
    }
    const end = new Uint8Array(22), e = new DataView(end.buffer);
    e.setUint32(0, 0x06054b50, true);
    e.setUint16(8, files.size, true); e.setUint16(10, files.size, true);
    e.setUint32(12, directorySize, true); e.setUint32(16, offset, true);
    return new Blob([...parts, ...directory, end], { type: 'application/zip' });
  }

  async function exportChat({ signal, progress = () => {}, wait = ms => new Promise(resolve => setTimeout(resolve, ms)) } = {}) {
    const route = location.href, meta = metadata();
    const reportDiagnostics = {};
    const loadedReports = reports(document, reportDiagnostics);
    function captureReports() {
      for (const report of reports(document, reportDiagnostics)) {
        const existing = loadedReports.findIndex(item => item.title === report.title &&
          (item.markdown.includes(report.markdown.split('\n\n').slice(1).join('\n\n')) || report.markdown.includes(item.markdown.split('\n\n').slice(1).join('\n\n'))));
        if (existing < 0) loadedReports.push(report);
        else if (report.markdown.length > loadedReports[existing].markdown.length) loadedReports[existing] = report;
      }
    }
    // Never guess the most recent chat when a local/temporary chat has no URL ID.
    const id = new URL(route).pathname.match(/\/c\/([a-zA-Z0-9-]+)(?:\/|$)/)?.[1];
    if (!id) throw new Error('Open a saved conversation before exporting. Temporary and shared chats are not supported.');
    function check() {
      if (signal?.aborted || location.href !== route) throw new Error('Export cancelled.');
      if (document.querySelectorAll('[data-is-streaming="true"], [data-talvt-turn-state="streaming"], [data-testid="stop-button"], button[aria-label="Stop generating"]').length)
        throw new Error('Wait for the response to finish before exporting.');
    }
    async function request(url, options = {}, binary = false) {
      check();
      const controller = new AbortController();
      const abort = () => controller.abort();
      signal?.addEventListener('abort', abort, { once: true });
      const timer = setTimeout(abort, 45000);
      try {
        const response = await fetch(url, { ...options, signal: controller.signal, redirect: 'error' });
        if (!response.ok) throw Object.assign(new Error(`Export request failed (HTTP ${response.status}).`), { status: response.status });
        let result;
        if (binary) {
          const mime = (response.headers.get('content-type') || '').split(';')[0];
          const extension = { 'image/png': 'png', 'image/jpeg': 'jpg', 'image/webp': 'webp', 'image/gif': 'gif', 'image/avif': 'avif' }[mime];
          if (!extension) throw new Error('Unsupported image format.');
          // Bound streamed bytes, including responses without Content-Length.
          const reader = response.body.getReader(), chunks = [];
          let size = 0;
          try {
            while (true) {
              const { value, done } = await reader.read();
              if (done) break;
              size += value.length;
              if (size > 40 * 1024 * 1024) throw new Error('Image exceeds 40 MB.');
              chunks.push(value);
            }
          } finally { await reader.cancel(); }
          const bytes = new Uint8Array(size); let offset = 0;
          for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.length; }
          result = { bytes, extension };
        } else result = await response.json();
        check(); return result;
      } finally { clearTimeout(timer); signal?.removeEventListener('abort', abort); }
    }
    check();
    const session = await request('/api/auth/session', { credentials: 'same-origin' });
    if (!session.accessToken) throw new Error('Sign in to ChatGPT and retry the export.');
    // Token stays in this call only; never sent to images, storage, logs or AI.
    const api = path => request('/backend-api/' + path, { credentials: 'same-origin', headers: { Authorization: `Bearer ${session.accessToken}` } });
    let data;
    try { data = await api(`conversations/${id}?num_turns=100`); }
    catch (error) {
      if (![404, 405].includes(error.status)) throw error;
      data = await api(`conversation/${id}`);
    }
    if (data.conversation_id && data.conversation_id !== id) throw new Error('Conversation identity mismatch.');
    if (Array.isArray(data.messages)) {
      if (!data.page_info || data.page_info.has_next_page) throw new Error('Cannot confirm the end of this conversation.');
      let page = data, pages = 0;
      const cursors = new Set();
      while (page.page_info.has_previous_page) {
        const cursor = page.page_info.start_cursor;
        if (!cursor || cursors.has(cursor) || ++pages > 200) throw new Error('Incomplete conversation pagination.');
        cursors.add(cursor);
        page = await api(`conversations/${id}?num_turns=100&before=${encodeURIComponent(cursor)}`);
        if (!Array.isArray(page.messages) || !page.page_info || !page.messages.length ||
            (page.conversation_id && page.conversation_id !== id)) throw new Error('Incomplete conversation page.');
        data.messages = [...page.messages, ...data.messages];
        progress(data.messages.length);
      }
      data.page_info = { has_previous_page: false, has_next_page: false };
    }
    const ordered = branch(data), files = new Map(), images = new Map(), warnings = [], messages = [], seen = new Set();
    // A report may have disappeared from the DOM when the user scrolled to
    // the composer. Revisit the transcript only for an explicit research request.
    const expectsReport = reportDiagnostics.researchCompletedMarkers > 0 || ordered.some(message => message.author?.role === 'user' &&
      (message.content?.parts || []).some(part => typeof part === 'string' && /@Deep research\b/i.test(part)));
    captureReports();
    if (globalThis.chrome?.runtime?.sendMessage) {
      try {
        const response = await Promise.race([
          chrome.runtime.sendMessage({ type: 'PE_REPORT_FRAMES', requestId: crypto.randomUUID() }),
          new Promise(resolve => setTimeout(() => resolve(null), 4000))
        ]);
        check();
        reportDiagnostics.bridgeFrames = response?.frames?.length || 0;
        for (const frame of response?.frames || []) {
          for (const report of frame.reports || []) {
            if (!loadedReports.some(item => item.markdown === report.markdown)) loadedReports.push(report);
          }
        }
        if (!response?.ok) reportDiagnostics.bridgeError = 'Frame bridge unavailable; reload extension and ChatGPT.';
      } catch { check(); reportDiagnostics.bridgeError = 'Frame bridge failed; reload extension and ChatGPT.'; }
    }
    if (expectsReport && !loadedReports.length) {
      const root = conversationRoot();
      let scroller = root.closest('[data-app-action-timeline-scroll], .thread-scroll-container');
      if (!scroller) {
        for (let node = root; node && node !== document.body; node = node.parentElement) {
          if (node.scrollHeight > node.clientHeight + 10 && /auto|scroll/.test(getComputedStyle(node).overflowY)) { scroller = node; break; }
        }
      }
      scroller ||= document.scrollingElement;
      if (scroller?.clientHeight > 0 && scroller.scrollHeight > scroller.clientHeight) {
        const oldTop = scroller.scrollTop, oldBehavior = scroller.style.scrollBehavior;
        try {
          scroller.style.scrollBehavior = 'auto';
          scroller.scrollTop = 0;
          for (let step = 0; step < 100; step++) {
            await wait(step === 0 ? 700 : 250); check(); captureReports();
            if (scroller.scrollTop + scroller.clientHeight >= scroller.scrollHeight - 3) break;
            scroller.scrollTop = Math.min(scroller.scrollTop + Math.max(100, scroller.clientHeight * 0.7), scroller.scrollHeight - scroller.clientHeight);
          }
        } finally {
          if (location.href === route && scroller.isConnected) scroller.scrollTop = oldTop;
          scroller.style.scrollBehavior = oldBehavior;
        }
      }
      if (!loadedReports.length) warnings.push('A Deep research request was found, but no loaded report document was captured. Open the report with Expand, keep it open and export again. The report is NOT included; see report-diagnostics.json for document/frame discovery counts. The conversation alone is not a complete research export.');
    }
    let imageCount = 0, bytesTotal = 0;
    const assetId = pointer => typeof pointer === 'string' ? pointer.replace(/^(?:sediment|file-service):\/\//, '') : '';
    const reportLabel = value => String(value || 'unknown').replace(/[\r\n\t]/g, ' ').slice(0, 200);
    let messageContext = '';
    async function image(pointer, name = '', source = 'image content') {
      const fileId = assetId(pointer);
      if (images.has(fileId)) {
        const cached = images.get(fileId);
        if (cached.failure) warnings.push(`${messageContext}: ${cached.failure}; attachment=${reportLabel(name)}, source=${source}.`);
        return cached.output;
      }
      const number = ++imageCount;
      let output, failure;
      try {
        if (!/^file[-_][a-zA-Z0-9_-]+$/.test(fileId)) throw new Error('Unsupported image reference.');
        const info = await api(`files/download/${encodeURIComponent(fileId)}?conversation_id=${id}&inline=false`);
        const url = new URL(info.download_url);
        if (url.protocol !== 'https:' || url.username || url.password ||
            !(url.hostname === 'chatgpt.com' || url.hostname.endsWith('.oaiusercontent.com') ||
              /^oaidalle[a-z0-9]*\.blob\.core\.windows\.net$/.test(url.hostname))) throw new Error('Unsupported image download host.');
        const asset = await request(url.href, { credentials: url.origin === 'https://chatgpt.com' ? 'same-origin' : 'omit', referrerPolicy: 'no-referrer' }, true);
        bytesTotal += asset.bytes.length;
        if (bytesTotal > 250 * 1024 * 1024) throw new Error('Images exceed the 250 MB export limit.');
        const path = `export-files/image-${String(number).padStart(3, '0')}.${asset.extension}`;
        files.set(path, asset.bytes);
        output = `![Image ${number}](${path})`;
      } catch (error) {
        check();
        // Do not include expiring signed URLs or request tokens in the report.
        const reason = error.status ? `HTTP ${error.status}` : 'Image unavailable, unsupported, too large, or blocked by the browser';
        failure = `Image ${number}: ${reason}; asset=${reportLabel(fileId)}`;
        warnings.push(`${messageContext}: ${failure}; attachment=${reportLabel(name)}, source=${source}.`);
        output = `> Image ${number} could not be saved. See export-report.txt.`;
      }
      images.set(fileId, { output, failure }); return output;
    }
    for (const [messageIndex, message] of ordered.entries()) {
      check();
      if (message.id && seen.has(message.id)) continue;
      if (message.id) seen.add(message.id);
      const role = message.author?.role, content = message.content || {}, m = message.metadata || {};
      if (!['user', 'assistant', 'tool'].includes(role) ||
          ['analysis', 'justify', 'confidence'].includes(message.channel) ||
          ['thoughts', 'reasoning_recap', 'user_editable_context', 'model_editable_context'].includes(content.content_type) ||
          m.is_thinking_preamble_message || (role !== 'tool' && m.is_visually_hidden_from_conversation) ||
          (role === 'assistant' && message.recipient && message.recipient !== 'all')) continue;
      messageContext = `Branch message ${messageIndex + 1} (${role}, id=${reportLabel(message.id)}, type=${reportLabel(content.content_type)})`;
      const chunks = [], attached = new Set();
      let unsupportedPart = false;
      const attachments = Array.isArray(m.attachments) ? m.attachments : [];
      const fallback = m.model_dil_v2?.fallbackMarkdown;
      if (role !== 'tool' && typeof fallback === 'string') chunks.push(fallback);
      if (role !== 'tool' && !fallback && typeof content.text === 'string') chunks.push(content.text);
      for (const part of content.parts || []) {
        if (typeof part === 'string') { if (role !== 'tool' && !fallback) chunks.push(part); }
        else if (part?.content_type === 'image_asset_pointer') {
          const fileId = assetId(part.asset_pointer);
          const attachment = attachments.find(item => assetId(item.id) === fileId);
          if (!attached.has(fileId)) chunks.push(await image(part.asset_pointer, attachment?.name));
          attached.add(fileId);
        } else if (part != null && role !== 'tool' && !fallback) unsupportedPart = true;
      }
      for (const attachment of attachments) {
        const fileId = assetId(attachment.id);
        if (attached.has(fileId)) continue;
        attached.add(fileId);
        if (attachment.mime_type?.startsWith('image/')) {
          chunks.push(await image(attachment.id, attachment.name, 'attachment metadata'));
        } else {
          chunks.push(`> Attachment: ${escapeText(reportLabel(attachment.name || attachment.id))} (${escapeText(reportLabel(attachment.mime_type || 'file'))}). File contents are not included in this export.`);
        }
      }
      for (const item of m.aggregate_result?.messages || []) {
        if (item.message_type === 'image') chunks.push(await image(item.image_url, '', 'code execution image'));
      }
      let text = chunks.join('\n\n').trim();
      for (const ref of m.content_references || []) {
        if (ref.matched_text && /[\ue200-\ue203]/.test(ref.matched_text) && typeof ref.alt === 'string')
          text = text.split(ref.matched_text).join(ref.alt);
      }
      const knownEmpty = ['text', 'multimodal_text'].includes(content.content_type) && !unsupportedPart;
      if ((unsupportedPart || (!text && !knownEmpty)) && role !== 'tool' && !m.is_visually_hidden_from_conversation) {
        text += `${text ? '\n\n' : ''}> Unsupported message content (${escapeText(reportLabel(content.content_type))}). See export-report.txt.`;
        warnings.push(`${messageContext}: unsupported content${unsupportedPart ? ' part' : ''}; readable text and attachment labels were retained.`);
      }
      if (text) messages.push({ role: role === 'user' ? 'user' : 'assistant', text });
      progress(messages.length);
    }
    if (!messages.length) throw new Error('No exportable chat messages found.');
    meta.title = data.title || meta.title;
    const name = filename(meta.title);
    captureReports();
    const reportLinks = [];
    for (const [index, report] of loadedReports.entries()) {
      const base = `export-files/report-${String(index + 1).padStart(3, '0')}`;
      files.set(base + '.md', report.markdown);
      files.set(base + '.html', report.html);
      reportLinks.push(`- ${escapeText(report.title)}: [Markdown](${base}.md) | [HTML with diagrams](${base}.html)`);
    }
    const md = `# ${escapeText(meta.title)}\n\nSource: <${safeURL(meta.url)}>\n\n` +
      '> Saved conversation branch. Other branches and internal reasoning are excluded.\n\n' +
      (warnings.length ? `> Export has ${warnings.length} warning(s); see export-report.txt.\n\n` : '') +
      messages.map(item => `## ${item.role === 'user' ? 'You' : 'ChatGPT'}\n\n${item.text}`).join('\n\n---\n\n') + '\n' +
      (reportLinks.length ? '\n## Loaded research reports\n\n' + reportLinks.join('\n') + '\n' : '');
    check();
    if (expectsReport && !loadedReports.length) {
      files.set('report-diagnostics.json', JSON.stringify({ exporterVersion: '0.6.0', ...reportDiagnostics,
        note: 'Counts only; no conversation content or credentials. Inaccessible frames may be cross-origin or sandboxed. Closed shadow roots are not inspectable.' }, null, 2));
    }
    if (imageCount || warnings.length || loadedReports.length) {
      files.set(name, md);
      if (warnings.length) files.set('export-report.txt', warnings.join('\n'));
      return { filename: name.replace(/\.md$/, '.zip'), blob: archive(files), markdown: md, count: messages.length, scanned: true, warnings: warnings.length, reportCount: loadedReports.length, imageCount: [...files.keys()].filter(path => /^export-files\/image-/.test(path)).length };
    }
    return { filename: name, markdown: md, count: messages.length, scanned: true, warnings: 0, imageCount: 0 };
  }
  function download(result) {
    const blob = result.blob || new Blob([result.markdown], { type: 'text/markdown;charset=utf-8' });
    const url = URL.createObjectURL(blob);
    const link = document.createElement('a');
    link.href = url;
    link.download = result.filename;
    link.hidden = true;
    document.body.append(link);
    try { link.click(); }
    finally { link.remove(); setTimeout(() => URL.revokeObjectURL(url), 60000); }
  }
  globalThis.PromptEnhancerExport = { markdown, collect, metadata, filename, documentMarkdown, reports, branch, archive, exportChat, download };
})();
