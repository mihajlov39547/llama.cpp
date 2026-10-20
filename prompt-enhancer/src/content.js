(() => {
  'use strict';
  globalThis.__promptEnhancerCleanup?.();
  const { findEditor, readEditorText, replaceEditorText } = globalThis.PromptEnhancerEditor;
  const host = document.createElement('div');
  host.dataset.promptEnhancerHost = '';
  const shadow = host.attachShadow({ mode: 'open' });
  // Keys used within our controls must not reach ChatGPT's composer handlers.
  // No keyboard listeners are installed on the editor itself.
  shadow.addEventListener('keydown', event => event.stopPropagation());
  shadow.addEventListener('keyup', event => event.stopPropagation());
  shadow.addEventListener('click', event => event.stopPropagation());
  const stylesheet = document.createElement('link');
  stylesheet.rel = 'stylesheet';
  stylesheet.href = chrome.runtime.getURL('src/styles.css');
  shadow.append(stylesheet);
  function element(tag, text, parent, attributes = {}) {
    const node = document.createElement(tag);
    if (text) node.textContent = text;
    for (const [key, value] of Object.entries(attributes)) node.setAttribute(key, value);
    parent.append(node);
    return node;
  }
  const panel = element('section', '', shadow, { 'aria-label': 'Improved Prompt', hidden: '' });
  element('h2', 'Improved Prompt', panel);
  const status = element('p', '', panel, { role: 'status', 'aria-live': 'polite' });
  const preview = element('pre', '', panel, { tabindex: '0' });
  const actions = element('div', '', panel, { class: 'actions' });
  function button(text, parent, action) {
    const node = element('button', text, parent, { type: 'button' });
    node.addEventListener('click', action);
    return node;
  }
  const apply = button('Apply', actions, applyRewrite);
  const copy = button('Copy', actions, () => copyText(rewrite));
  const retry = button('Retry', actions, start);
  const cancelButton = button('Cancel', actions, cancel);
  const recovery = element('details', '', panel);
  element('summary', 'Original prompt (recovery copy)', recovery);
  const original = element('textarea', '', recovery, { readonly: '', 'aria-label': 'Original prompt' });
  button('Copy original', recovery, () => copyText(original.value));
  const bar = element('div', '', shadow, { class: 'bar' });
  const improve = button('✦ Improve Prompt', bar, start);
  improve.dataset.promptEnhancerButton = '';
  let editor = null, route = location.href, snapshot = null, rewrite = '';
  let pending = null, applying = false, disposed = false, scheduled = false;
  const editorEvents = new AbortController();

  function message(text, error = false) {
    status.textContent = text;
    status.classList.toggle('error', error);
  }
  function dirty() {
    if (snapshot && !applying) {
      snapshot.changed = true;
      message('Your draft changed. Apply is disabled. Retry will improve the current draft.', true);
    }
    update();
  }
  function current() {
    return snapshot && !snapshot.changed && editor === snapshot.editor &&
      editor?.isConnected && location.href === snapshot.route &&
      readEditorText(editor) === snapshot.text;
  }
  function update() {
    improve.disabled = !!pending || applying || !editor || !readEditorText(editor).trim();
    improve.textContent = pending ? '◌ Improving…' : '✦ Improve Prompt';
    improve.setAttribute('aria-busy', String(!!pending));
    apply.disabled = !!pending || applying || !rewrite || !current();
    copy.disabled = !rewrite;
    cancelButton.disabled = applying;
    retry.disabled = !!pending || applying || !editor || !readEditorText(editor).trim();
    recovery.hidden = !snapshot;
  }
  function stopRequest() {
    const request = pending;
    pending = null;
    if (request) {
      clearTimeout(request.timer);
      try {
        chrome.runtime.sendMessage({ type: 'PE_CANCEL', requestId: request.id }).catch(() => {});
      } catch { /* Extension may have been reloaded. */ }
    }
  }
  function cancel() {
    if (applying) return;
    stopRequest();
    panel.hidden = true;
    update();
  }
  function reconcile() {
    scheduled = false;
    if (disposed) return;
    const root = document.documentElement;
    const theme = root.classList.contains('dark') || root.dataset.theme === 'dark' ? 'dark' :
      root.classList.contains('light') || root.dataset.theme === 'light' ? 'light' : 'light dark';
    if (host.style.colorScheme !== theme) host.style.colorScheme = theme;
    const found = findEditor();
    if (found !== editor || route !== location.href) {
      if (snapshot) {
        snapshot.changed = true;
        stopRequest();
        message('The composer or chat changed. Copy the suggestion, or Retry with the current draft.', true);
      }
      editor = found;
      route = location.href;
    }
    if (editor) {
      const container = editor.closest('[data-composer-body]') ||
        editor.closest('form') || editor.parentElement;
      if (host.parentElement !== container) container.append(host);
      host.hidden = false;
    } else {
      // Keep recovery/error accessible during composer removal.
      if (!host.isConnected && snapshot) document.body.append(host);
      host.hidden = !snapshot;
    }
    if (snapshot && !snapshot.changed && !applying &&
        readEditorText(editor) !== snapshot.text) dirty();
    update();
  }
  function schedule() {
    if (!scheduled) {
      scheduled = true;
      queueMicrotask(reconcile);
    }
  }
  async function start() {
    if (pending || applying) return;
    reconcile();
    panel.hidden = false;
    if (!editor) { message('ChatGPT editor could not be found.', true); return; }
    const text = readEditorText(editor);
    if (!text.trim()) { message('Enter a prompt first.', true); return; }
    if (text.length > 20000) { message('Prompt exceeds 20,000 characters.', true); return; }
    snapshot = { text, editor, route: location.href, changed: false };
    original.value = text;
    rewrite = '';
    preview.textContent = '';
    const request = { id: crypto.randomUUID(), timer: null };
    pending = request;
    request.timer = setTimeout(() => {
      if (pending !== request) return;
      stopRequest();
      message('The background request stopped responding or timed out. Your draft is unchanged. Retry; if the extension was reloaded, refresh ChatGPT.', true);
      update();
    }, 65000);
    message('Improving with your local model…');
    update();
    try {
      const result = await chrome.runtime.sendMessage({
        type: 'PE_IMPROVE', requestId: request.id, prompt: text
      });
      if (pending !== request || disposed) return;
      if (!result?.ok) throw new Error(result?.error?.message || 'The background worker returned no response. Retry.');
      if (typeof result.text !== 'string' || !result.text.trim()) throw new Error('No usable rewrite was returned.');
      rewrite = result.text;
      preview.textContent = rewrite;
      message(current() ? 'Review the rewrite before applying. Apply never sends the message.' :
        'Your draft or composer changed. Copy the suggestion, or Retry with the current draft.', !current());
    } catch (error) {
      if (pending !== request || disposed) return;
      message(`${error.message} Your draft is unchanged.`, true);
    } finally {
      if (pending === request) {
        clearTimeout(request.timer);
        pending = null;
        update();
      }
    }
  }
  async function applyRewrite() {
    if (!current() || pending || applying || !rewrite) return;
    const saved = snapshot;
    applying = true;
    update();
    try {
      await replaceEditorText(saved.editor, saved.text, rewrite,
        () => snapshot === saved && !saved.changed && location.href === saved.route && editor === saved.editor);
      saved.changed = true; // Prevent a second Apply; preserve original recovery.
      message('Applied to the draft. Nothing was submitted. Original text remains available below.');
    } catch (error) {
      saved.changed = true;
      message(error.message, true);
    } finally {
      applying = false;
      update();
    }
  }
  async function copyText(text) {
    try {
      await navigator.clipboard.writeText(text);
      message('Copied to clipboard.');
    } catch {
      message('Clipboard access failed. Select the text in the panel and press Ctrl+C.', true);
    }
  }
  document.addEventListener('input', event => {
    if (editor && (event.target === editor || editor.contains(event.target))) dirty();
  }, { signal: editorEvents.signal });
  const observer = new MutationObserver(schedule);
  observer.observe(document.documentElement, {
    subtree: true, childList: true, characterData: true,
    attributes: true, attributeFilter: ['contenteditable', 'hidden', 'aria-hidden']
  });
  const routeTimer = setInterval(reconcile, 1000);
  function cleanup() {
    if (disposed) return;
    disposed = true;
    stopRequest();
    observer.disconnect();
    clearInterval(routeTimer);
    editorEvents.abort();
    host.remove();
    window.removeEventListener('pagehide', onPageHide);
    window.removeEventListener('pageshow', onPageShow);
  }
  function onPageHide(event) { if (!event.persisted) cleanup(); else stopRequest(); }
  function onPageShow() { reconcile(); }
  window.addEventListener('pagehide', onPageHide);
  window.addEventListener('pageshow', onPageShow);
  globalThis.__promptEnhancerCleanup = cleanup;
  reconcile();
})();
