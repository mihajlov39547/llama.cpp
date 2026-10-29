(() => {
  "use strict";

  const blockedDomain = "ultimatesurferprotector.com";
  const NativeURL = URL;
  function isBlocked(value) {
    try {
      const host = new NativeURL(String(value), document.baseURI).hostname
        .toLowerCase().replace(/\.$/, "");
      return host === blockedDomain || host.endsWith(`.${blockedDomain}`);
    } catch {
      return false;
    }
  }

  // Prevent direct popup creation, rather than leaving a blocked empty tab.
  // Network rules remain independent of this page-world wrapper.
  const nativeOpen = window.open;
  window.open = function (...args) {
    if (isBlocked(args[0])) return null;
    return Reflect.apply(nativeOpen, this, args);
  };

  function cancel(event) {
    event.preventDefault();
    event.stopImmediatePropagation();
  }

  function guardLink(event) {
    const link = event.composedPath().find(node =>
      node instanceof Element && node.matches("a[href], area[href]"));
    if (link && isBlocked(link.href)) cancel(event);
  }
  window.addEventListener("click", guardLink, true);
  window.addEventListener("auxclick", guardLink, true);

  window.addEventListener("submit", event => {
    const form = event.target;
    if (!(form instanceof HTMLFormElement)) return;
    const button = event.submitter;
    const action = button?.hasAttribute("formaction") ? button.formAction : form.action;
    if (isBlocked(action)) cancel(event);
  }, true);

  // form.submit() bypasses the submit event.
  const nativeSubmit = HTMLFormElement.prototype.submit;
  HTMLFormElement.prototype.submit = function (...args) {
    if (isBlocked(this.action)) return;
    return Reflect.apply(nativeSubmit, this, args);
  };
})();
