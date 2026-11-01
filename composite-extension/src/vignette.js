(() => {
  'use strict';
  const selector = 'ins[data-vignette-loaded="true"], ins[id^="gpt_unit_"][id*="/Interstitial"]';
  let scheduled = false;
  const baseline = new WeakMap();
  function remember(node) {
    if (!node) return;
    const values = {};
    for (const property of ['overflow', 'overflow-x', 'overflow-y']) {
      const value = node.style.getPropertyValue(property);
      // Do not record an existing ad's scroll lock as a normal baseline.
      if (!/^(hidden|clip)$/.test(value)) values[property] = [value, node.style.getPropertyPriority(property)];
    }
    baseline.set(node, values);
  }
  function repair() {
    scheduled = false;
    const overlays = [...document.querySelectorAll(selector)];
    const hash = location.hash === '#google_vignette';
    let active = hash && overlays.length > 0;
    for (const node of overlays) {
      if (node.style.getPropertyValue('display') !== 'none') active = true;
      for (const [property, value] of [['display', 'none'], ['visibility', 'hidden'], ['pointer-events', 'none']]) {
        if (node.style.getPropertyValue(property) !== value || node.style.getPropertyPriority(property) !== 'important')
          node.style.setProperty(property, value, 'important');
      }
      if (node.getAttribute('aria-hidden') !== 'true') node.setAttribute('aria-hidden', 'true');
      if (node.getAttribute('tabindex') !== '-1') node.setAttribute('tabindex', '-1');
    }
    if (active) {
      // Do not release a scroll lock owned by an ordinary open modal.
      const modal = [...document.querySelectorAll('dialog[open], [aria-modal="true"]')]
        .some(node => !node.closest(selector) && getComputedStyle(node).display !== 'none' && getComputedStyle(node).visibility !== 'hidden');
      if (!modal) for (const node of [document.documentElement, document.body]) {
        if (!node) continue;
        for (const property of ['overflow', 'overflow-x', 'overflow-y']) {
          if (!/^(hidden|clip)$/.test(node.style.getPropertyValue(property))) continue;
          const [value, priority] = baseline.get(node)?.[property] || ['', ''];
          if (value) node.style.setProperty(property, value, priority);
          else node.style.removeProperty(property);
        }
      }
      if (hash) {
        const url = new URL(location.href); url.hash = '';
        history.replaceState(history.state, '', url.href);
      }
    } else if (!hash) {
      remember(document.documentElement); remember(document.body);
    }
  }
  function schedule() {
    if (scheduled) return;
    scheduled = true;
    queueMicrotask(repair);
  }
  remember(document.documentElement); remember(document.body);
  new MutationObserver(records => {
    if (records.some(record => record.type === 'childList' ||
      record.target === document.body || record.target === document.documentElement || record.target.matches?.(selector))) schedule();
  }).observe(document, { childList: true, subtree: true, attributes: true,
    attributeFilter: ['style', 'data-vignette-loaded', 'id', 'aria-hidden'] });
  window.addEventListener('hashchange', schedule);
  repair();
})();
