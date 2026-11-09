(() => {
  const rows = new Map();
  const extraSections = [
    ["groups", "Groups"], ["events", "Events"],
    ["map", "Check-ins"], ["reviews_given", "Reviews given"]
  ];
  let navigationRequest = 0;

  function matchesSection(element, target) {
    if (!element.href) return false;
    const url = new URL(element.href, location.href);
    return url.origin === target.origin && url.pathname === target.pathname &&
      url.searchParams.get("id") === target.searchParams.get("id") &&
      (url.searchParams.get("sk") || "") === (target.searchParams.get("sk") || "");
  }

  function activateSection(tabs, target) {
    const request = ++navigationRequest;
    const nativeTab = Array.from(tabs.querySelectorAll('a[role="tab"][href]'))
      .find(tab => matchesSection(tab, target));
    if (nativeTab) {
      nativeTab.click();
      return;
    }
    const more = tabs.querySelector('[role="tab"][aria-label="More profile sections"]');
    if (!more) return;
    if (more.getAttribute("aria-expanded") !== "true") more.click();
    let attempts = 0;
    function activateMenuItem() {
      if (request !== navigationRequest || !tabs.isConnected ||
          !document.documentElement.hasAttribute("data-better-facebook")) return;
      const menu = document.getElementById(more.getAttribute("aria-controls"));
      const item = Array.from((menu || document).querySelectorAll('a[role="menuitemradio"][href], a[role="menuitem"][href]'))
        .find(link => matchesSection(link, target) && link.getClientRects().length);
      if (item) item.click();
      else if (++attempts < 15) setTimeout(activateMenuItem, 100);
      // Leave Facebook's menu available if its markup changes; never force a reload.
    }
    activateMenuItem();
  }

  function update() {
    for (const [tabs, row] of rows) {
      if (!tabs.isConnected) {
        row.remove();
        rows.delete(tabs);
      }
    }
    for (const more of document.querySelectorAll('[role="tab"][aria-label="More profile sections"]')) {
      const tabs = more.closest('[role="tablist"]');
      const source = tabs?.querySelector('a[role="tab"][href]');
      if (!source) continue;
      const base = new URL(source.href, location.href);
      if (base.origin !== location.origin || base.pathname !== "/profile.php") continue;
      base.searchParams.delete("sk");
      base.hash = "";
      let row = rows.get(tabs);
      if (!row) {
        row = document.createElement("nav");
        row.className = "bf-profile-sections";
        row.setAttribute("aria-label", "Profile sections");
        tabs.after(row);
        rows.set(tabs, row);
      }
      // React may remove an inserted sibling while retaining the original tabs.
      if (tabs.nextElementSibling !== row) tabs.after(row);
      const height = `${tabs.getBoundingClientRect().height}px`;
      if (row.style.getPropertyValue("--bf-native-height") !== height) {
        row.style.setProperty("--bf-native-height", height);
      }
      const sections = new Map();
      for (const tab of tabs.querySelectorAll('a[role="tab"][href]')) {
        const url = new URL(tab.href, location.href);
        if (url.origin !== base.origin || url.pathname !== base.pathname ||
            url.searchParams.get("id") !== base.searchParams.get("id")) continue;
        const label = tab.textContent.trim();
        if (label) sections.set(url.searchParams.get("sk") || "", label);
      }
      for (const [section, label] of extraSections) {
        if (!sections.has(section)) sections.set(section, label);
      }
      const key = JSON.stringify([base.href, location.href, [...sections]]);
      if (row.dataset.key === key) continue;
      row.dataset.key = key;
      row.replaceChildren();
      for (const [section, label] of sections) {
        const link = document.createElement("a");
        const url = new URL(base);
        if (section) url.searchParams.set("sk", section);
        link.href = url.href;
        link.textContent = label;
        link.addEventListener("click", event => {
          // Preserve open-in-new-tab/window behavior for modified clicks.
          if (event.button !== 0 || event.ctrlKey || event.metaKey || event.shiftKey || event.altKey) return;
          event.preventDefault();
          activateSection(tabs, url);
        });
        if ((new URL(location.href).searchParams.get("sk") || "") === section) {
          link.setAttribute("aria-current", "page");
        }
        row.append(link);
      }
      const manage = document.createElement("button");
      manage.type = "button";
      manage.textContent = "Manage sections";
      manage.addEventListener("click", () => {
        const currentMore = tabs.querySelector('[role="tab"][aria-label="More profile sections"]');
        if (!currentMore) return;
        if (currentMore.getAttribute("aria-expanded") !== "true") currentMore.click();
        let attempts = 0;
        function openManage() {
          if (!document.documentElement.hasAttribute("data-better-facebook") || !currentMore.isConnected) return;
          const menu = document.getElementById(currentMore.getAttribute("aria-controls"));
          const candidates = (menu || document).querySelectorAll('[role="menuitemradio"], [role="menuitem"]');
          const item = Array.from(candidates).find(element =>
            element.textContent.trim() === "Manage sections" && element.getClientRects().length);
          if (item) item.click();
          else if (++attempts < 10) setTimeout(openManage, 100);
          // If Facebook changed its menu, leave the native menu open for access.
        }
        openManage();
      });
      row.append(manage);
    }
  }

  let pending = false;
  new MutationObserver(() => {
    if (pending) return;
    pending = true;
    setTimeout(() => { pending = false; update(); }, 100);
  }).observe(document, { childList: true, subtree: true, attributes: true, attributeFilter: ["href"] });
  window.addEventListener("popstate", update);
  window.addEventListener("resize", update);
  update();
})();
