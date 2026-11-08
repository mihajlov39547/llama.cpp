(() => {
  "use strict";

  let plainPaste = false;
  let plainPasteResult = null;
  let notice;
  let noticeTimer;
  let settings = { mode: "off", css: true };
  let settingsRevision = 0;

  function applySettings(value = {}) {
    settings = {
      mode: ["strong", "selective", "off"].includes(value.mode) ? value.mode : "strong",
      css: value.css !== false
    };
    window.dispatchEvent(new CustomEvent("unblockcp:mode", { detail: settings.mode }));
    globalThis.unblockcpCSS.setEnabled(settings.mode !== "off" && settings.css);
    chrome.runtime.sendMessage({ type: "unblockcp:css" }).then(result => {
      if (!result?.ok) console.warn("UnblockCP CSS:", result?.error);
    }).catch(error => console.warn("UnblockCP CSS:", error.message));
  }

  chrome.storage.onChanged.addListener((changes, area) => {
    if (area === "local" && changes.settings) {
      settingsRevision++;
      applySettings(changes.settings.newValue);
    }
  });
  const initialRevision = settingsRevision;
  chrome.storage.local.get("settings").then(({ settings: value }) => {
    if (settingsRevision === initialRevision) applySettings(value);
  }).catch(error => console.warn("UnblockCP settings:", error.message));

  function notify(message) {
    if (!document.documentElement) return;
    if (!notice?.isConnected) {
      notice = document.createElement("div");
      const root = notice.attachShadow({ mode: "closed" });
      const label = document.createElement("div");
      label.setAttribute("role", "status");
      label.style.cssText = "font:14px/1.5 system-ui;color:white;background:#172536;padding:12px 16px;border-radius:10px;box-shadow:0 4px 24px #0004;max-width:360px";
      root.append(label);
      notice.label = label;
      notice.style.cssText = "all:initial!important;position:fixed!important;right:20px!important;bottom:20px!important;z-index:2147483647!important;pointer-events:none!important";
      document.documentElement.append(notice);
    }
    notice.label.textContent = `UnblockCP: ${message}`;
    clearTimeout(noticeTimer);
    noticeTimer = setTimeout(() => notice.remove(), 2600);
  }

  function focusedElement() {
    let element = document.activeElement;
    while (element?.shadowRoot?.activeElement) element = element.shadowRoot.activeElement;
    return element;
  }

  function editable(element) {
    if (!element || element.disabled || element.readOnly) return false;
    if (element.isContentEditable || document.designMode === "on") return true;
    return element.tagName === "TEXTAREA" ||
      (element.tagName === "INPUT" && /^(text|search|url|tel|email|password)$/.test(element.type));
  }

  // Keep browser default actions, but prevent page handlers from cancelling them.
  // Register on window in capture phase before ordinary page scripts execute.
  for (const type of ["copy", "cut", "paste", "selectstart", "contextmenu", "dragstart"]) {
    window.addEventListener(type, (event) => {
      if (settings.mode === "off") return;
      if (settings.mode === "strong" || plainPaste) event.stopImmediatePropagation();
      if (type === "paste" && plainPaste) {
        event.preventDefault();
        const text = event.clipboardData?.getData("text/plain");
        plainPasteResult = typeof text === "string" && text.length > 0 &&
          document.execCommand("insertText", false, text);
      }
    }, true);
  }

  // Some pages cancel beforeinput as an additional paste restriction.
  window.addEventListener("beforeinput", (event) => {
    if ((settings.mode === "strong" && /^insertFromPaste/.test(event.inputType)) || plainPaste) event.stopImmediatePropagation();
  }, true);

  function copySelection() {
    const element = focusedElement();
    const fieldSelected = element && typeof element.selectionStart === "number" &&
      element.selectionEnd > element.selectionStart;
    if (!fieldSelected && !window.getSelection()?.toString()) {
      notify("Prvo selektuj tekst.");
      return;
    }
    // Native copy preserves both text/plain and text/html when available.
    const success = document.execCommand("copy");
    notify(success ? "Selekcija je kopirana." : "Kopiranje nije uspelo u ovom polju.");
  }

  function copyAll() {
    const text = document.body?.innerText || "";
    if (!text.trim()) {
      notify("Na stranici nema dostupnog teksta.");
      return;
    }
    const active = focusedElement();
    const selection = window.getSelection();
    const ranges = [];
    if (selection) {
      for (let i = 0; i < selection.rangeCount; i++) ranges.push(selection.getRangeAt(i).cloneRange());
    }
    const fieldRange = active && typeof active.selectionStart === "number"
      ? [active.selectionStart, active.selectionEnd, active.selectionDirection] : null;
    const field = document.createElement("textarea");
    field.value = text;
    field.style.cssText = "position:fixed;left:-10000px;top:0;opacity:0";
    document.documentElement.append(field);
    let success = false;
    try {
      field.focus({ preventScroll: true });
      field.select();
      success = document.execCommand("copy");
    } finally {
      field.remove();
      active?.focus({ preventScroll: true });
      if (selection) {
        selection.removeAllRanges();
        for (const range of ranges) selection.addRange(range);
      }
      if (fieldRange) active.setSelectionRange(...fieldRange);
    }
    notify(success ? "Tekst stranice je kopiran." : "Kopiranje nije uspelo.");
  }

  function paste(asPlainText) {
    if (!editable(focusedElement())) {
      notify("Prvo klikni u polje za unos teksta.");
      return;
    }
    plainPaste = asPlainText;
    plainPasteResult = null;
    let success = false;
    try {
      // The extension's clipboardRead permission enables native paste, including
      // on HTTP pages. Let Chrome sanitize rich HTML instead of using innerHTML.
      success = document.execCommand("paste");
      if (asPlainText) success = plainPasteResult === true;
    } finally {
      plainPaste = false;
    }
    notify(success
      ? (asPlainText ? "Tekst je nalepljen bez formatiranja." : "Sadržaj je nalepljen sa dostupnim formatiranjem.")
      : "Lepljenje nije uspelo ili je clipboard prazan. Probaj Ctrl+V.");
  }

  function shortcut(event) {
    if (!event.ctrlKey || !event.altKey || event.shiftKey || event.metaKey) return null;
    // Avoid stealing characters typed with the separate AltGr key.
    if (event.getModifierState?.("AltGraph")) return null;
    return /^(Digit|Numpad)[1-4]$/.test(event.code) ? event.code.slice(-1) : null;
  }

  for (const type of ["keydown", "keypress", "keyup"]) {
    window.addEventListener(type, (event) => {
      if (settings.mode === "off") return;
      const action = shortcut(event);
      if (action) {
        event.preventDefault();
        event.stopImmediatePropagation();
        if (type !== "keydown" || event.repeat) return;
        try {
          if (action === "1") copySelection();
          else if (action === "2") copyAll();
          else paste(action === "3");
        } catch (error) {
          console.warn("UnblockCP:", error);
          notify("Browser nije dozvolio ovu operaciju.");
        }
        return;
      }
      // Ordinary copy/paste/select-all retain the browser's default behavior.
      if (settings.mode !== "strong") return;
      if ((event.ctrlKey || event.metaKey) && !event.altKey &&
          ["KeyC", "KeyV", "KeyX", "KeyA", "Insert"].includes(event.code)) {
        event.stopImmediatePropagation();
      }
      if (event.shiftKey && event.code === "Insert") event.stopImmediatePropagation();
    }, true);
  }
})();
