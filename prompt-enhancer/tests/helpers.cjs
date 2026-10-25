// Deliberately small DOM/Chrome test doubles. These are not a browser or a
// ProseMirror implementation; layout and native editing require manual tests.
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const read = file => fs.readFileSync(path.join(__dirname, '..', 'src', file), 'utf8');
const tick = async () => { for (let i = 0; i < 12; i++) await Promise.resolve(); };
function deferred() {
  let resolve, reject;
  const promise = new Promise((yes, no) => { resolve = yes; reject = no; });
  return { promise, resolve, reject };
}
function dom() {
  const observers = [], records = [];
  class Target {
    constructor() { this.listeners = new Map(); }
    addEventListener(type, fn, options = {}) {
      if (!this.listeners.has(type)) this.listeners.set(type, new Set());
      this.listeners.get(type).add(fn);
      options.signal?.addEventListener('abort', () => this.removeEventListener(type, fn), { once: true });
    }
    removeEventListener(type, fn) { this.listeners.get(type)?.delete(fn); }
    emit(type, extra = {}) {
      const event = { type, target: this, isTrusted: true, stopPropagation() {}, preventDefault() {}, ...extra };
      return [...(this.listeners.get(type) || [])].map(fn => fn(event));
    }
  }
  function matches(node, selector) {
    return selector.split(',').some(part => {
      const chain = part.trim().split(/\s+(?![^\[]*\])/);
      function simple(element, pattern) {
        if (!element?.tagName) return false;
        const tag = pattern.match(/^[a-z][\w-]*/i)?.[0];
        if (tag && element.tagName !== tag.toUpperCase()) return false;
        for (const match of pattern.matchAll(/\.([\w-]+)/g)) {
          if (!element.classList.contains(match[1])) return false;
        }
        for (const match of pattern.matchAll(/\[([\w-]+)(?:(\^?=)"([^"]*)")?\]/g)) {
          if (!element.attributes.has(match[1])) return false;
          if (match[2] === '=' && element.getAttribute(match[1]) !== match[3]) return false;
          if (match[2] === '^=' && !element.getAttribute(match[1]).startsWith(match[3])) return false;
        }
        return true;
      }
      if (!simple(node, chain.pop())) return false;
      let ancestor = node.parentElement;
      while (chain.length) {
        const pattern = chain.pop();
        while (ancestor && !simple(ancestor, pattern)) ancestor = ancestor.parentElement;
        if (!ancestor) return false;
        ancestor = ancestor.parentElement;
      }
      return true;
    });
  }
  class Node extends Target {
    constructor(tag, value = '') {
      super();
      this.nodeType = tag ? 1 : 3;
      this.tagName = tag?.toUpperCase();
      this.nodeValue = tag ? null : value;
      this.childNodes = [];
      this.parentNode = null;
      this.attributes = new Map();
      this.style = {};
      this.value = '';
      this.disabled = false;
      this.dataset = new Proxy({}, {
        get: (_, key) => this.getAttribute('data-' + key.replace(/[A-Z]/g, ch => '-' + ch.toLowerCase())) ?? undefined,
        set: (_, key, val) => { this.setAttribute('data-' + key.replace(/[A-Z]/g, ch => '-' + ch.toLowerCase()), val); return true; }
      });
      this.classList = {
        contains: name => (this.getAttribute('class') || '').split(' ').includes(name),
        toggle: (name, enabled) => {
          const names = new Set((this.getAttribute('class') || '').split(' ').filter(Boolean));
          if (enabled) names.add(name); else names.delete(name);
          this.setAttribute('class', [...names].join(' '));
        }
      };
    }
    get parentElement() { return this.parentNode?.nodeType === 1 ? this.parentNode : null; }
    get lastChild() { return this.childNodes.at(-1); }
    get nextSibling() { return this.parentNode?.childNodes[this.parentNode.childNodes.indexOf(this) + 1] || null; }
    get isConnected() { return this === document.documentElement || !!this.parentNode?.isConnected; }
    get hidden() { return this.attributes.has('hidden'); }
    set hidden(value) { if (value) this.setAttribute('hidden', ''); else this.removeAttribute('hidden'); }
    get textContent() { return this.nodeType === 3 ? this.nodeValue : this.childNodes.map(child => child.textContent).join(''); }
    set textContent(value) {
      for (const child of this.childNodes) child.parentNode = null;
      this.childNodes = [];
      if (value) this.append(new Node(null, String(value)));
      records.push({ type: 'childList', target: this });
    }
    setAttribute(key, value) {
      this.attributes.set(key, String(value));
      records.push({ type: 'attributes', attributeName: key, target: this });
    }
    getAttribute(key) { return this.attributes.get(key) ?? null; }
    removeAttribute(key) {
      if (this.attributes.delete(key)) records.push({ type: 'attributes', attributeName: key, target: this });
    }
    append(...nodes) { for (const node of nodes) this.insertBefore(node, null); }
    insertBefore(node, anchor) {
      node.remove();
      const index = anchor ? this.childNodes.indexOf(anchor) : this.childNodes.length;
      if (index < 0) throw new Error('Invalid fixture anchor');
      this.childNodes.splice(index, 0, node);
      node.parentNode = this;
      records.push({ type: 'childList', target: this });
    }
    remove() {
      if (!this.parentNode) return;
      const parent = this.parentNode;
      parent.childNodes.splice(parent.childNodes.indexOf(this), 1);
      this.parentNode = null;
      records.push({ type: 'childList', target: parent });
    }
    contains(node) { return node === this || this.childNodes.some(child => child.contains(node)); }
    closest(selector) {
      for (let node = this; node; node = node.parentElement) if (matches(node, selector)) return node;
      return null;
    }
    querySelectorAll(selector) {
      return this.childNodes.flatMap(child => [
        ...(matches(child, selector) ? [child] : []), ...child.querySelectorAll(selector)
      ]);
    }
    getClientRects() { return this.isConnected && !this.hidden ? [1] : []; }
    focus() { document.activeElement = this; this.emit('focus'); }
    attachShadow() { this.shadowRoot = new Node('shadow-root'); return this.shadowRoot; }
  }
  const document = new Target();
  document.documentElement = new Node('html');
  document.body = new Node('body');
  document.documentElement.append(document.body);
  document.createElement = tag => new Node(tag);
  document.querySelectorAll = selector => document.documentElement.querySelectorAll(selector);
  document.activeElement = document.body;
  document.createRange = () => ({
    commonAncestorContainer: null, collapsed: false,
    selectNodeContents(node) { this.commonAncestorContainer = node; },
    collapse() { this.collapsed = true; },
    cloneRange() { return { ...this }; }
  });
  const selection = {
    ranges: [], get rangeCount() { return this.ranges.length; },
    getRangeAt(index) { return this.ranges[index]; },
    removeAllRanges() { this.ranges = []; }, addRange(range) { this.ranges.push(range); }
  };
  const window = new Target();
  window.getSelection = () => selection;
  class MutationObserver {
    constructor(callback) { this.callback = callback; }
    observe(target, options) { this.target = target; this.options = options; observers.push(this); }
    disconnect() { this.target = null; }
  }
  async function flushMutations() {
    for (let round = 0; round < 30; round++) {
      const batch = records.splice(0);
      for (const observer of observers) {
        const filtered = batch.filter(record => observer.target?.contains(record.target) &&
          (record.type !== 'attributes' || observer.options.attributeFilter.includes(record.attributeName)));
        if (filtered.length) observer.callback(filtered);
      }
      await tick();
      if (!records.length) return;
    }
    throw new Error('Mutation observer did not settle');
  }
  const element = (tag, attrs = {}, ...children) => {
    const node = new Node(tag);
    Object.entries(attrs).forEach(([key, value]) => node.setAttribute(key, value));
    node.append(...children.map(child => typeof child === 'string' ? new Node(null, child) : child));
    return node;
  };
  // Same stable hierarchy/attributes as ChatGPT's supplied ProseMirror markup.
  function composer(...paragraphs) {
    const editor = element('div', { contenteditable: 'true', role: 'textbox', class: 'ProseMirror',
      'data-composer-markdown': '', 'aria-label': 'Ask ChatGPT' }, ...paragraphs);
    const input = element('div', { 'data-composer-input': '' }, editor);
    const send = element('button', { type: 'submit', 'aria-label': 'Send prompt' }, 'Send');
    const body = element('div', { 'data-composer-body': '' }, input, element('div', {}, send));
    const form = element('form', {}, body);
    document.body.append(form);
    return { editor, body, form, send };
  }
  return { document, window, selection, MutationObserver, element, composer, flushMutations };
}
function contentHarness(config = {}) {
  const fixture = dom(), timers = new Map(), intervals = new Map(), messages = [];
  let nextId = 1;
  const chrome = {
    runtime: {
      getURL: file => `chrome-extension://test/${file}`,
      sendMessage(message) {
        const response = deferred();
        messages.push({ ...message, response });
        if (message.type === 'PE_CANCEL') response.resolve({ ok: true });
        return response.promise;
      }
    },
    storage: { local: { get: async () => ({ settings: config }) } }
  };
  const ctx = vm.createContext({
    ...fixture, chrome, AbortController, queueMicrotask,
    location: { href: 'https://chatgpt.com/' },
    navigator: { clipboard: { writeText: async () => {} } },
    crypto: { randomUUID: () => `id-${nextId++}` },
    setTimeout(fn, delay) { const id = nextId++; timers.set(id, { fn, delay }); return id; },
    clearTimeout(id) { timers.delete(id); },
    setInterval(fn) { const id = nextId++; intervals.set(id, fn); return id; },
    clearInterval(id) { intervals.delete(id); }
  });
  for (const file of ['settings.js', 'editor.js']) vm.runInContext(read(file), ctx);
  function load() { vm.runInContext(read('content.js'), ctx); }
  function host() { return fixture.document.querySelectorAll('[data-prompt-enhancer-host]')[0]; }
  function control(label) {
    return host().shadowRoot.querySelectorAll('button').find(node => node.textContent === label);
  }
  function improve() {
    return host().shadowRoot.querySelectorAll('[data-prompt-enhancer-button]')[0];
  }
  function preview() { return host().shadowRoot.querySelectorAll('pre')[0].textContent; }
  function status() { return host().shadowRoot.querySelectorAll('[role="status"]')[0].textContent; }
  return { ...fixture, ctx, chrome, load, host, control, improve, preview, status, messages, timers, intervals };
}
module.exports = { read, tick, deferred, dom, contentHarness };
