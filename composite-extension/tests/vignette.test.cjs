const { test } = require('node:test');
const assert = require('node:assert/strict');
const vm = require('node:vm');
const fs = require('node:fs');
const path = require('node:path');
const source = fs.readFileSync(path.join(__dirname, '../src/vignette.js'), 'utf8');
function setup({ overlay = true, modal = false, hash = '#google_vignette' } = {}) {
  function node(values = {}) {
    const entries = new Map(Object.entries(values)), priorities = new Map(), attrs = new Map();
    return { style: { getPropertyValue: p => entries.get(p) || '', getPropertyPriority: p => priorities.get(p) || '',
      setProperty(p,v,priority) { entries.set(p,v); priorities.set(p,priority); }, removeProperty(p) { entries.delete(p); priorities.delete(p); } },
      getAttribute: p => attrs.get(p) ?? null, setAttribute: (p,v) => attrs.set(p,v), matches: () => true, closest: () => null };
  }
  const ad = node({ display: 'block' }), body = node({ overflow: 'hidden' }), html = node();
  const location = { href: 'https://www.politika.rs/article?x=1' + hash, hash };
  let observer, replaced;
  const history = { state: { page: 3 }, replaceState(state, _, href) { replaced = { state, href }; location.href = href; location.hash = new URL(href).hash; } };
  const document = { body, documentElement: html, querySelectorAll: selector => selector.startsWith('ins') ? (overlay ? [ad] : []) : (modal ? [node()] : []) };
  vm.runInNewContext(source, { document, location, history, URL, WeakMap, queueMicrotask: fn => fn(),
    getComputedStyle: () => ({ display: 'block', visibility: 'visible' }), window: { addEventListener() {} },
    MutationObserver: class { constructor(fn) { observer = fn; } observe() {} } });
  return { ad, body, history, get replaced() { return replaced; }, mutate() { observer([{ type: 'attributes', target: ad }]); } };
}
test('Politika overlay is hidden inline, scroll unlocked and only vignette hash removed', () => {
  const f = setup();
  assert.equal(f.ad.style.getPropertyValue('display'), 'none');
  assert.equal(f.ad.style.getPropertyPriority('display'), 'important');
  assert.equal(f.body.style.getPropertyValue('overflow'), '');
  assert.equal(f.replaced.href, 'https://www.politika.rs/article?x=1');
  assert.equal(f.replaced.state, f.history.state);
  assert.equal(f.ad.getAttribute('aria-hidden'), 'true');
  f.ad.style.setProperty('display','block','important'); f.mutate();
  assert.equal(f.ad.style.getPropertyValue('display'), 'none');
});
test('ordinary modals retain scroll locks and unrelated fragments remain', () => {
  const f = setup({ modal: true, hash: '#article-section' });
  assert.equal(f.body.style.getPropertyValue('overflow'), 'hidden');
  assert.equal(f.replaced, undefined);
});
test('hash alone without matching overlay does not modify site state', () => {
  const f = setup({ overlay: false });
  assert.equal(f.body.style.getPropertyValue('overflow'), 'hidden');
  assert.equal(f.replaced, undefined);
});
