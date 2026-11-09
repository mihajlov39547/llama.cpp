(() => {
  const { normalize } = globalThis.BetterFacebook;
  let settings = normalize();
  let loaded = false;
  const expandAttempts = new WeakMap();
  let expandTimer;

  function expandExploreItems() {
    if (!loaded || !settings.enabled || expandTimer) return;
    for (const button of document.querySelectorAll('[role="button"][aria-label="See less explore items"]')) {
      expandAttempts.delete(button);
    }
    for (const button of document.querySelectorAll('[role="button"][aria-label="See more explore items"]')) {
      const attempts = expandAttempts.get(button) || 0;
      if (attempts >= 5 || button.getAttribute("aria-disabled") === "true") continue;
      expandAttempts.set(button, attempts + 1);
      button.click();
      // Retry briefly if Facebook has rendered the control before its handler.
      if (!expandTimer) expandTimer = setTimeout(() => {
        expandTimer = undefined;
        expandExploreItems();
      }, 500);
    }
  }

  function markShortcuts() {
    const matches = new Set();
    for (const heading of document.querySelectorAll("h3")) {
      if (heading.textContent.trim() !== "Your shortcuts") continue;
      // The supplied section has a heading wrapper followed by a direct ul.
      // Stop at the nearest matching section rather than hiding the sidebar.
      let section = heading.parentElement;
      while (section && section !== document.body) {
        if (section.matches("div") && section.querySelector(":scope > ul") &&
            section.querySelectorAll("h3").length === 1) {
          matches.add(section);
          break;
        }
        section = section.parentElement;
      }
    }
    for (const section of document.querySelectorAll("[data-bf-shortcuts]")) {
      if (!matches.has(section)) section.removeAttribute("data-bf-shortcuts");
    }
    for (const section of matches) section.setAttribute("data-bf-shortcuts", "");
  }

  function markProfileSuggestions() {
    const matches = new Set();
    if (location.pathname === "/profile.php") {
      for (const heading of document.querySelectorAll("h2")) {
        if (heading.textContent.trim().toLowerCase() !== "people you may know") continue;
        const card = heading.closest('div[style*="--card-corner-radius"]');
        if (!card) continue;
        // Include the supplied card wrapper and its dedicated spacing container.
        let section = card;
        if (card.parentElement?.matches("div.html-div")) {
          section = card.parentElement;
          if (section.parentElement?.matches("div") && section.parentElement.children.length === 1) {
            section = section.parentElement;
          }
        }
        matches.add(section);
      }
    }
    for (const section of document.querySelectorAll("[data-bf-profile-suggestions]")) {
      if (!matches.has(section)) section.removeAttribute("data-bf-profile-suggestions");
    }
    for (const section of matches) section.setAttribute("data-bf-profile-suggestions", "");
  }

  function markSuggestedPages() {
    const matches = new Set();
    for (const close of document.querySelectorAll('[role="button"][aria-label="Close promotion"]')) {
      const card = close.closest('div[style*="--card-corner-radius"]');
      if (!card || !Array.from(card.querySelectorAll('span[dir="auto"]')).some(
        span => span.textContent.trim() === "Suggested Pages for you"
      )) continue;
      let section = card;
      if (card.parentElement?.matches("div.html-div")) {
        section = card.parentElement;
        if (section.parentElement?.matches("div.html-div") && section.parentElement.children.length === 1) {
          section = section.parentElement;
        }
      }
      matches.add(section);
    }
    for (const section of document.querySelectorAll("[data-bf-suggested-pages]")) {
      if (!matches.has(section)) section.removeAttribute("data-bf-suggested-pages");
    }
    for (const section of matches) section.setAttribute("data-bf-suggested-pages", "");
  }

  // Facebook inserts and replaces sidebar sections and profile cards after navigation.
  let scanTimer;
  const observer = new MutationObserver(() => {
    if (scanTimer) return;
    scanTimer = setTimeout(() => {
      scanTimer = undefined;
      markShortcuts();
      markProfileSuggestions();
      markSuggestedPages();
      expandExploreItems();
    }, 100);
  });
  observer.observe(document, {
    childList: true, characterData: true, subtree: true,
    attributes: true, attributeFilter: ["aria-label", "aria-disabled"]
  });
  markShortcuts();
  markProfileSuggestions();
  markSuggestedPages();
  window.addEventListener("popstate", markProfileSuggestions);

  function apply() {
    const root = document.documentElement;
    if (!root || !loaded) return;
    root.toggleAttribute("data-better-facebook", settings.enabled);
    root.toggleAttribute("data-bf-focus", settings.enabled && settings.focus);
    if (settings.enabled) root.dataset.bfText = settings.textSize;
    else root.removeAttribute("data-bf-text");
    expandExploreItems();
  }

  // Register first so settings changes also reach already-open Facebook tabs.
  let changed = false;
  chrome.storage.onChanged.addListener((changes, area) => {
    if (area !== "local" || !changes.betterFacebook) return;
    changed = true;
    loaded = true;
    settings = normalize(changes.betterFacebook.newValue);
    apply();
  });
  chrome.storage.local.get("betterFacebook").then((result) => {
    if (!changed) settings = normalize(result.betterFacebook);
    loaded = true;
    apply();
  }).catch(() => {
    // Keep Facebook untouched if extension settings cannot be loaded.
  });
  document.addEventListener("DOMContentLoaded", apply, { once: true });
})();
