(() => {
  "use strict";

  function disableLink(link) {
    if (!link.matches("a[href], area[href]")) return;
    try {
      const host = new URL(link.getAttribute("href"), document.baseURI)
        .hostname.toLowerCase().replace(/\.$/, "");
      if (host !== "ultimatesurferprotector.com" &&
          !host.endsWith(".ultimatesurferprotector.com")) return;
      link.removeAttribute("href");
      link.removeAttribute("target");
      link.setAttribute("aria-disabled", "true");
    } catch {
      // Leave malformed or unsupported links unchanged.
    }
  }

  function scan(root) {
    if (root instanceof Element) disableLink(root);
    root.querySelectorAll?.("a[href], area[href]").forEach(disableLink);
  }

  // Watch newly inserted banner content and rewritten destinations.
  new MutationObserver(records => {
    for (const record of records) {
      if (record.type === "attributes") disableLink(record.target);
      else record.addedNodes.forEach(scan);
    }
  }).observe(document, {
    childList: true, subtree: true, attributes: true, attributeFilter: ["href"]
  });
  scan(document);
})();
