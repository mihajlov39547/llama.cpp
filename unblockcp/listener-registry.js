/* MAIN-world instrumentation. No clipboard data or extension APIs here. */
(() => {
  "use strict";
  if (Object.hasOwn(window, "__unblockcpInspector")) return;
  const nativeAdd = EventTarget.prototype.addEventListener;
  const nativeRemove = EventTarget.prototype.removeEventListener;
  const nativePrevent = Event.prototype.preventDefault;
  const watched = new Set(["copy", "cut", "paste", "keydown", "keyup", "keypress",
    "contextmenu", "selectstart", "dragstart", "beforeinput"]);
  const clipboardEvents = new Set(["copy", "cut", "paste", "contextmenu", "selectstart", "dragstart"]);
  const byTarget = new WeakMap();
  const records = new Map();
  let sequence = 0;
  let current = null;
  let mode = "strong";

  function relevant(event) {
    if (clipboardEvents.has(event.type)) return true;
    if (event.type === "beforeinput") return /^insertFromPaste/.test(event.inputType || "");
    if (!event.type.startsWith("key") || event.getModifierState?.("AltGraph")) return false;
    if (event.shiftKey && event.code === "Insert") return true;
    if (!(event.ctrlKey || event.metaKey)) return false;
    if (event.altKey) return !event.shiftKey && /^(Digit|Numpad)[1-4]$/.test(event.code);
    return ["KeyC", "KeyV", "KeyX", "KeyA", "Insert"].includes(event.code) ||
      ["c", "v", "x", "a"].includes(event.key?.toLowerCase());
  }

  function capture(options) {
    return typeof options === "boolean" ? options : Boolean(options?.capture);
  }

  function forget(record) {
    records.delete(record.id);
    const target = record.target.deref();
    const list = target && byTarget.get(target);
    if (list) {
      const index = list.indexOf(record);
      if (index >= 0) list.splice(index, 1);
    }
    if (record.signal && record.abort) nativeRemove.call(record.signal, "abort", record.abort);
  }

  function mark(record, event) {
    if (mode === "off" || !relevant(event)) return;
    record.cancelled++;
    record.lastEvent = event.type;
  }

  Event.prototype.preventDefault = function () {
    const result = nativePrevent.call(this);
    if (current?.event === this && this.defaultPrevented) {
      current.marked = true;
      mark(current.record, this);
    }
    return result;
  };

  EventTarget.prototype.addEventListener = function (type, listener, options) {
    // Browser global calls (including detached aliases used by web-vitals) use
    // Window when the receiver is null/undefined. This strict wrapper does not
    // get that native Web IDL normalization automatically.
    const target = this == null ? window : this;
    if ((typeof target !== "object" && typeof target !== "function")) {
      return nativeAdd.call(target, type, listener, options);
    }
    if (!watched.has(type) || !listener ||
        (typeof listener !== "function" && typeof listener !== "object")) {
      return nativeAdd.call(target, type, listener, options);
    }
    const useCapture = capture(options);
    const list = byTarget.get(target) || [];
    if (list.some(record => record.type === type && record.listener === listener && record.capture === useCapture)) return;
    // Normalize once: native listener lifecycle remains responsible for once/passive/signal.
    const normalized = typeof options === "object" && options !== null
      ? { capture: useCapture, once: Boolean(options.once), passive: Boolean(options.passive), signal: options.signal }
      : { capture: useCapture };
    if (normalized.signal?.aborted) return;
    const record = {
      id: ++sequence, type, listener, capture: useCapture, target: new WeakRef(target),
      disabled: false, cancelled: 0, lastEvent: null,
      name: typeof listener === "function" ? (listener.name || "(anonimni)") : "handleEvent",
      source: new Error().stack?.split("\n").slice(2, 5).join("\n") || "",
      signal: normalized.signal
    };
    record.wrapper = function (event) {
      if (normalized.once) forget(record);
      // Preserve unrelated keys and ordinary typing even for disabled keyboard handlers.
      if (mode !== "off" && record.disabled && relevant(event)) return;
      const previous = current;
      const context = { record, event, marked: false };
      const alreadyCancelled = event.defaultPrevented;
      current = context;
      try {
        if (typeof listener === "function") return listener.call(this, event);
        return listener.handleEvent.call(listener, event);
      } finally {
        // Also detects returnValue=false and calls through a saved native method.
        if (!context.marked && !alreadyCancelled && event.defaultPrevented) mark(record, event);
        current = previous;
      }
    };
    nativeAdd.call(target, type, record.wrapper, normalized);
    list.push(record);
    byTarget.set(target, list);
    records.set(record.id, new WeakRef(record));
    if (normalized.signal) {
      record.abort = () => forget(record);
      nativeAdd.call(normalized.signal, "abort", record.abort, { once: true });
    }
  };

  EventTarget.prototype.removeEventListener = function (type, listener, options) {
    const target = this == null ? window : this;
    if ((typeof target !== "object" && typeof target !== "function")) {
      return nativeRemove.call(target, type, listener, options);
    }
    const useCapture = capture(options);
    const record = byTarget.get(target)?.find(item =>
      item.type === type && item.listener === listener && item.capture === useCapture);
    if (!record) return nativeRemove.call(target, type, listener, options);
    nativeRemove.call(target, type, record.wrapper, { capture: useCapture });
    forget(record);
  };

  function liveRecords() {
    const live = [];
    for (const [id, reference] of records) {
      const record = reference.deref();
      if (!record?.target.deref()) records.delete(id);
      else live.push(record);
    }
    return live;
  }

  function describe(target) {
    if (target === window) return "window";
    if (target === document) return "document";
    return `${target?.nodeName || "EventTarget"}${target?.id ? `#${target.id}` : ""}`.slice(0, 160);
  }

  const api = {
    report() {
      const live = liveRecords();
      return {
        mode, total: live.length,
        listeners: live.filter(item => item.cancelled || item.disabled).slice(0, 200).map(item => ({
          id: item.id, type: item.type, name: item.name.slice(0, 100),
          target: describe(item.target.deref()), capture: item.capture,
          cancelled: item.cancelled, disabled: item.disabled, source: item.source.slice(0, 1000)
        }))
      };
    },
    setDisabled(id, disabled) {
      const record = records.get(id)?.deref();
      if (!record || !record.cancelled || typeof disabled !== "boolean") return false;
      record.disabled = disabled;
      return true;
    },
    restore() {
      for (const item of liveRecords()) item.disabled = false;
      return true;
    }
  };
  Object.defineProperty(window, "__unblockcpInspector", { value: Object.freeze(api), configurable: true });
  nativeAdd.call(window, "unblockcp:mode", event => {
    if (["strong", "selective", "off"].includes(event.detail)) mode = event.detail;
  });
})();
