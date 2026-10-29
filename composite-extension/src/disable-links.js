(() => {
  "use strict";

  const domainReference = /\bultimatesurferprotector\.com\b/i;
  const referencesDomain = value => domainReference.test(value || "");

  function cleanElement(element) {
    // Remove the clickable banner itself, not just its destination. This also
    // removes listeners attached to that element and its descendants.
    if (element.matches("a, area, iframe, frame, object, embed, script, form") &&
        (Array.from(element.attributes).some(attr => referencesDomain(attr.value)) ||
          (element.matches("script") && referencesDomain(element.textContent)))) {
      element.remove();
      return;
    }
    // Strip remaining literal references, including inline click handlers.
    for (const attr of Array.from(element.attributes)) {
      if (referencesDomain(attr.value)) element.removeAttribute(attr.name);
    }
  }

  function scan(root) {
    if (root instanceof Element) cleanElement(root);
    root.querySelectorAll?.("*").forEach(cleanElement);
  }

  // Watch newly inserted banner content and rewritten destinations.
  new MutationObserver(records => {
    for (const record of records) {
      if (record.type === "attributes") cleanElement(record.target);
      else if (record.type === "characterData") {
        if (record.target.parentElement?.matches("script")) cleanElement(record.target.parentElement);
      } else {
        if (record.target instanceof Element && record.target.matches("script")) cleanElement(record.target);
        record.addedNodes.forEach(scan);
      }
    }
  }).observe(document, {
    childList: true, subtree: true, attributes: true, characterData: true
  });
  scan(document);
})();
