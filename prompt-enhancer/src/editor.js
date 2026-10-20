(() => {
  'use strict';
  const selectors = [
    '[data-composer-input] [contenteditable="true"][role="textbox"]',
    '[data-composer-markdown][contenteditable="true"]',
    '[contenteditable="true"].ProseMirror[role="textbox"]'
  ];
  function findEditor() {
    for (const selector of selectors) {
      const editor = [...document.querySelectorAll(selector)].find(element =>
        element.isConnected && element.getClientRects().length &&
        !element.closest('[data-prompt-enhancer-host], [inert], [aria-hidden="true"]'));
      if (editor) return editor;
    }
    return null;
  }
  // Serialize blocks explicitly: innerText inserts double newlines between <p>s.
  function readEditorText(editor) {
    if (!editor) return '';
    const blocks = new Set(['P', 'DIV', 'LI', 'UL', 'OL', 'PRE', 'BLOCKQUOTE',
      'H1', 'H2', 'H3', 'H4', 'H5', 'H6']);
    function readList(node) {
      let number = Number(node.getAttribute?.('start') ?? 1);
      if (!Number.isInteger(number)) number = 1;
      return [...node.childNodes].filter(child => child.tagName === 'LI').map(item => {
        const explicit = item.getAttribute?.('value');
        if (explicit != null && Number.isInteger(Number(explicit))) number = Number(explicit);
        const marker = node.tagName === 'OL' ? `${number++}. ` : '- ';
        // Indent every continuation line, including nested lists. Literal text
        // inside each item (paths, code, spaces) is otherwise left untouched.
        return marker + read(item).replace(/\n/g, '\n' + ' '.repeat(marker.length));
      }).join('\n');
    }
    function read(node) {
      if (node.nodeType === 3) return node.nodeValue;
      if (node.nodeType !== 1) return '';
      if (node.tagName === 'BR') return '\n';
      if (node.tagName === 'UL' || node.tagName === 'OL') return readList(node);
      let text = '';
      let previousBlock = false;
      let hasPrevious = false;
      for (const child of node.childNodes) {
        // Ignore only the editor's actual terminal caret placeholder. A plain
        // BR in PRE/CODE is a real line break, including when it is the only child.
        if (child === node.lastChild && child.tagName === 'BR' &&
            (child.classList.contains('ProseMirror-trailingBreak') ||
              (node.childNodes.length === 1 && ['P', 'DIV'].includes(node.tagName)))) continue;
        const block = blocks.has(child.tagName);
        if (hasPrevious && (block || previousBlock)) text += '\n';
        text += read(child);
        previousBlock = block;
        hasPrevious = true;
      }
      return text;
    }
    return read(editor).replace(/\r\n?/g, '\n');
  }
  async function replaceEditorText(editor, expected, replacement, isCurrent) {
    if (!editor?.isConnected || findEditor() !== editor || !isCurrent()) {
      throw new Error('The composer changed. Copy the rewrite or improve the current draft again.');
    }
    if (readEditorText(editor) !== expected) {
      throw new Error('Your draft changed. It was not replaced. Copy the rewrite or improve the new draft.');
    }
    editor.focus({ preventScroll: true });
    if (!editor.isConnected || findEditor() !== editor || !isCurrent() ||
        readEditorText(editor) !== expected) throw new Error('The draft changed before Apply. Use Copy.');
    if (document.activeElement !== editor && !editor.contains(document.activeElement)) {
      throw new Error('The editor could not receive focus. Use Copy.');
    }
    const selection = window.getSelection();
    if (!selection) throw new Error('Editor selection is unavailable. Use Copy.');
    const previousRanges = [];
    for (let index = 0; index < selection.rangeCount; index++) {
      const previous = selection.getRangeAt(index);
      if (editor.contains(previous.commonAncestorContainer)) previousRanges.push(previous.cloneRange());
    }
    const range = document.createRange();
    range.selectNodeContents(editor);
    selection.removeAllRanges();
    selection.addRange(range);
    // Native editing preserves the undo stack and lets ProseMirror observe input.
    // Never write innerHTML/textContent or synthesize Enter/Send.
    let accepted = false, executing = true, editedAfterCommand = false;
    const onInput = () => { if (!executing) editedAfterCommand = true; };
    editor.addEventListener('input', onInput);
    try {
      try { accepted = document.execCommand('insertText', false, replacement); }
      catch { /* Report the Copy fallback below. */ }
      finally { executing = false; }
      // A rejected command must not leave the whole draft selected, where the
      // next keystroke could accidentally delete it. Never roll back text.
      if (!accepted && editor.isConnected && document.activeElement === editor &&
          readEditorText(editor) === expected) {
        selection.removeAllRanges();
        if (previousRanges.length) previousRanges.forEach(previous => selection.addRange(previous));
        else { range.collapse(false); selection.addRange(range); }
      }
      await new Promise(resolve => setTimeout(resolve, 100));
      const first = editor.isConnected && readEditorText(editor) === replacement;
      await new Promise(resolve => setTimeout(resolve, 200));
      if (!accepted || !first || editedAfterCommand || !isCurrent() || findEditor() !== editor ||
          readEditorText(editor) !== replacement) {
        throw new Error('Replacement could not be verified. Check the draft and use Copy. The original is available below; Ctrl+Z can undo native edits.');
      }
    } finally {
      editor.removeEventListener('input', onInput);
    }
  }
  globalThis.PromptEnhancerEditor = { findEditor, readEditorText, replaceEditorText };
})();
