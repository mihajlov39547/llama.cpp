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
    const blocks = new Set(['P', 'DIV', 'LI', 'UL', 'OL', 'PRE', 'BLOCKQUOTE', 'H1', 'H2', 'H3']);
    function read(node) {
      if (node.nodeType === 3) return node.nodeValue;
      if (node.nodeType !== 1) return '';
      if (node.tagName === 'BR') return '\n';
      let text = '';
      let previousBlock = false;
      let hasPrevious = false;
      for (const child of node.childNodes) {
        const block = blocks.has(child.tagName);
        if (hasPrevious && (block || previousBlock)) text += '\n';
        text += read(child);
        previousBlock = block;
        hasPrevious = true;
      }
      // ProseMirror's terminal BR is a caret placeholder, not another line.
      if (node.lastChild?.tagName === 'BR' &&
          (node.lastChild.classList.contains('ProseMirror-trailingBreak') || node.childNodes.length === 1)) {
        text = text.slice(0, -1);
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
    if (!isCurrent() || readEditorText(editor) !== expected) throw new Error('The draft changed before Apply.');
    const selection = window.getSelection();
    const range = document.createRange();
    range.selectNodeContents(editor);
    selection.removeAllRanges();
    selection.addRange(range);
    // Native editing preserves the undo stack and lets ProseMirror observe input.
    // Never write innerHTML/textContent or synthesize Enter/Send.
    let accepted = false;
    try { accepted = document.execCommand('insertText', false, replacement); }
    catch { /* Report the Copy fallback below. */ }
    await new Promise(resolve => setTimeout(resolve, 100));
    const first = editor.isConnected && readEditorText(editor) === replacement;
    await new Promise(resolve => setTimeout(resolve, 200));
    if (!accepted || !first || !isCurrent() || findEditor() !== editor ||
        readEditorText(editor) !== replacement) {
      throw new Error('Replacement could not be verified. Check the draft and use Copy. The original is available below; Ctrl+Z can undo native edits.');
    }
  }
  globalThis.PromptEnhancerEditor = { findEditor, readEditorText, replaceEditorText };
})();
