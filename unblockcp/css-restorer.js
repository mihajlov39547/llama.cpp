/* Isolated world: reversible overrides for open shadow trees. */
(() => {
  "use strict";
  const sheets = new Map();
  let observer;
  let timer;
  let enabled = false;
  let queued = false;
  const css = ":host, * { -webkit-user-select: text !important; user-select: text !important; -webkit-touch-callout: default !important; }";

  function scan(root = document) {
    for (const element of root.querySelectorAll("*")) {
      const shadow = element.shadowRoot;
      if (!shadow) continue;
      let sheet = sheets.get(shadow);
      if (!sheet) {
        sheet = new CSSStyleSheet();
        sheet.replaceSync(css);
        sheets.set(shadow, sheet);
        observer.observe(shadow, { childList: true, subtree: true });
      }
      if (!shadow.adoptedStyleSheets.includes(sheet)) {
        shadow.adoptedStyleSheets = [...shadow.adoptedStyleSheets, sheet];
      }
      scan(shadow);
    }
  }

  function update() {
    if (!enabled) return;
    for (const [root, sheet] of sheets) {
      if (!root.host.isConnected) {
        root.adoptedStyleSheets = root.adoptedStyleSheets.filter(item => item !== sheet);
        sheets.delete(root);
      }
    }
    scan();
  }

  globalThis.unblockcpCSS = {
    setEnabled(value) {
      if (enabled === value) return;
      enabled = value;
      if (enabled) {
        observer = new MutationObserver(() => {
          if (queued) return;
          queued = true;
          setTimeout(() => { queued = false; update(); }, 100);
        });
        observer.observe(document, { childList: true, subtree: true });
        update();
        // attachShadow on an existing host does not emit a document mutation.
        timer = setInterval(update, 2000);
      } else {
        observer?.disconnect();
        clearInterval(timer);
        for (const [root, sheet] of sheets) {
          root.adoptedStyleSheets = root.adoptedStyleSheets.filter(item => item !== sheet);
        }
        sheets.clear();
      }
    }
  };
})();
