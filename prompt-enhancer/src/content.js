(() => {
  'use strict';
  globalThis.__promptEnhancerCleanup?.();
  const { findEditor, readEditorText, replaceEditorText } = globalThis.PromptEnhancerEditor;
  const Settings = globalThis.PromptEnhancerSettings;
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
    node.addEventListener('click', event => {
      // A page script can see the open shadow root; synthetic clicks must not
      // authorize reading/sending a draft, applying text or writing clipboard.
      if (event.isTrusted) return action(event);
    });
    return node;
  }
  const apply = button('Apply', actions, applyRewrite);
  const copy = button('Copy', actions, () => copyText(rewrite));
  const refine = button('Refine Further', actions, () => start('refine'));
  const cancelButton = button('Cancel', actions, cancel);
  const recovery = element('details', '', panel);
  element('summary', 'Original prompt (recovery copy)', recovery);
  const original = element('textarea', '', recovery, { readonly: '', 'aria-label': 'Original prompt' });
  button('Copy original', recovery, () => copyText(original.value));
  const bar = element('div', '', shadow, { class: 'bar' });
  element('span', 'Improve Prompt sends this draft to your local AI server (127.0.0.1:8080).', bar, { class: 'disclosure' });
  const improve = button('✦ Improve Prompt', bar, () => start('improve'));
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
      message('Your draft changed. Apply and Refine Further are disabled. Use Improve Prompt to start again with the current draft.', true);
    }
    update();
  }
  function current() {
    return snapshot && !snapshot.changed && editor === snapshot.editor &&
      editor?.isConnected && location.href === snapshot.route &&
      readEditorText(editor) === snapshot.text;
  }
  function update() {
    // Do not inspect the draft merely to disable an empty-state button.
    // The explicit Improve action validates emptiness before sending anything.
    improve.disabled = !!pending || applying || !editor;
    improve.textContent = pending ? '◌ Improving…' : '✦ Improve Prompt';
    improve.setAttribute('aria-busy', String(!!pending));
    apply.disabled = !!pending || applying || !rewrite || !current();
    copy.disabled = !rewrite;
    cancelButton.disabled = applying;
    refine.disabled = !!pending || applying || !rewrite || !current();
    refine.setAttribute('aria-busy', String(pending?.mode === 'refine'));
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
        message('The composer or chat changed. Copy the suggestion, or use Improve Prompt with the current draft.', true);
      }
      editor = found;
      route = location.href;
    }
    if (editor) {
      // Keep our row out of ChatGPT's editor/footer layout. In particular,
      // appending to a flex/grid composer body can put us beside Send.
      const anchor = editor.closest('form') || editor.closest('[data-composer-body]') ||
        editor.closest('[data-composer-input]') || editor;
      if (host.parentElement !== anchor.parentElement || host.nextSibling !== anchor) {
        anchor.parentElement.insertBefore(host, anchor);
      }
      if (host.hidden) host.hidden = false;
    } else {
      // Keep recovery/error accessible during composer removal.
      if (!host.isConnected && snapshot) document.body.append(host);
      if (host.hidden !== !snapshot) host.hidden = !snapshot;
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
  async function start(mode = 'improve') {
    if (pending || applying) return;
    reconcile();
    const refining = mode === 'refine';
    if (refining && (!rewrite || !current())) return;
    panel.hidden = false;
    if (!editor) { message('ChatGPT editor could not be found.', true); return; }
    const text = refining ? snapshot.text : readEditorText(editor);
    const previousImprovement = refining ? rewrite : undefined;
    function validate(config) {
      if (refining) Settings.validateRefinement(text, previousImprovement, config);
      else Settings.validatePrompt(text, config);
    }
    try { validate(Settings.defaults); }
    catch (error) { message(error.message, true); return; }
    if (!refining) {
      snapshot = { text, editor, route: location.href, changed: false };
      original.value = text;
      rewrite = '';
      preview.textContent = '';
    }
    const request = { id: crypto.randomUUID(), timer: null, mode };
    pending = request;
    request.timer = setTimeout(() => {
      if (pending !== request) return;
      stopRequest();
      message('The background request stopped responding or timed out. Your draft is unchanged. Try Refine Further again if a preview exists, or use Improve Prompt. If the extension was reloaded, refresh ChatGPT.', true);
      update();
    }, Settings.responseTimeoutMs);
    message(refining ? 'Refining the previous improvement with your local model…' : 'Improving with your local model…');
    update();
    try {
      const { settings } = await chrome.storage.local.get('settings');
      if (pending !== request || disposed) return;
      validate(Settings.settings(settings));
      const result = await chrome.runtime.sendMessage(refining ? {
        type: 'PE_REFINE', requestId: request.id, originalPrompt: text, previousImprovement
      } : { type: 'PE_IMPROVE', requestId: request.id, prompt: text });
      if (pending !== request || disposed) return;
      if (!result?.ok) throw new Error(result?.error?.message || 'The background worker returned no response. Retry.');
      if (typeof result.text !== 'string' || !result.text.trim()) throw new Error('No usable rewrite was returned.');
      rewrite = result.text;
      preview.textContent = rewrite;
      message(current() ? 'Review the rewrite before applying. Apply never sends the message.' :
        'Your draft or composer changed. Copy the suggestion, or use Improve Prompt with the current draft.', !current());
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
      panel.hidden = true;
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
  function onPageHide(event) {
    if (!event.persisted) cleanup();
    else if (pending) {
      stopRequest();
      message('Request cancelled when leaving this page. Use Improve Prompt to start again, or Refine Further if the preview still matches this draft.');
      update();
    }
  }
  function onPageShow() { reconcile(); }
  window.addEventListener('pagehide', onPageHide);
  window.addEventListener('pageshow', onPageShow);
  globalThis.__promptEnhancerCleanup = cleanup;
  reconcile();
})();
