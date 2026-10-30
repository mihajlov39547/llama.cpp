(() => {
  "use strict";
  const selector = 'ins.adsbygoogle, iframe[id^="google_ads_iframe_"], iframe[data-google-query-id], div[id^="div-gpt-ad-"]';

  function clean(root) {
    if (root instanceof Element && root.matches(selector)) {
      root.remove();
      return;
    }
    root.querySelectorAll?.(selector).forEach(ad => ad.remove());
  }

  // Only inspect inserted subtrees or elements whose ad markers changed.
  // Removing the container also handles inline !important styles.
  new MutationObserver(records => {
    for (const record of records) {
      if (record.type === "attributes") {
        if (record.target.matches(selector)) record.target.remove();
      } else record.addedNodes.forEach(clean);
    }
  }).observe(document, {
    childList: true,
    subtree: true,
    attributes: true,
    attributeFilter: ["class", "id", "data-google-query-id"]
  });
  clean(document);
})();
