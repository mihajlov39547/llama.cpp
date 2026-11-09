(() => {
  const { defaults, clean, active } = globalThis.BetterFacebookSidebar;
  const nativeSelector = '[role="navigation"][aria-label="Shortcuts"]';
  const cacheKey = "betterFacebookMenu";
  let links = defaults;
  let captured = false;
  let signature = "";
  let rail;
  let timer;
  let lastLocation = "";
  const shifted = new Set();

  const symbols = {
    Home: "M3 11 12 3l9 8M5 10v11h5v-7h4v7h5V10",
    Events: "M5 5h14v16H5zM8 3v4m8-4v4M5 10h14",
    Groups: "M9 11a3 3 0 1 0 0-6 3 3 0 0 0 0 6M3 21v-3a6 6 0 0 1 12 0v3m1-15a3 3 0 0 1 0 6m3 9v-3a5 5 0 0 0-2-4",
    Marketplace: "M4 10v11h16V10M3 10l2-6h14l2 6zM9 21v-7h6v7",
    Saved: "M6 3h12v19l-6-4-6 4z",
    Memories: "M3 10a9 9 0 1 1 2 9M3 4v6h6m3-3v6l4 2",
    "Your profile": "M12 11a4 4 0 1 0 0-8 4 4 0 0 0 0 8M4 21a8 8 0 0 1 16 0",
    Feeds: "M4 4h16v6H4zM4 14h16v6H4z"
  };

  function capture(nav) {
    const items = [];
    for (const anchor of nav.querySelectorAll('a[href]')) {
      if (anchor.closest('[data-bf-shortcuts], footer')) continue;
      // Exclude the separate Your shortcuts section even before it is marked.
      const list = anchor.closest("ul");
      const heading = list?.previousElementSibling?.querySelector("h3");
      const shortcut = heading?.textContent.trim() === "Your shortcuts";
      if (!shortcut) items.push({ href: anchor.href, label: anchor.textContent.trim() });
    }
    const next = clean(items);
    if (next.length < 2) return;
    if (!next.some(item => item.href === "/")) next.unshift(defaults[0]);
    const key = JSON.stringify(next);
    if (key === JSON.stringify(links)) return;
    links = next;
    captured = true;
    chrome.storage.local.set({ [cacheKey]: next }).catch(() => {});
  }

  function render() {
    if (!rail) {
      rail = document.createElement("nav");
      rail.id = "bf-persistent-sidebar";
      rail.setAttribute("aria-label", "Facebook Menu");
      rail.addEventListener("click", event => {
        const link = event.target.closest("a[href]");
        if (!link || event.button !== 0 || event.ctrlKey || event.metaKey || event.shiftKey || event.altKey) return;
        // Keep Facebook's own router when a matching original link exists.
        const target = new URL(link.href);
        const original = Array.from(document.querySelectorAll('a[href]')).find(anchor => {
          if (rail.contains(anchor) || anchor.closest('.bf-profile-sections')) return false;
          const url = new URL(anchor.href, location.href);
          return url.origin === target.origin && url.pathname.replace(/\/$/, "") === target.pathname.replace(/\/$/, "") && !url.searchParams.has("id");
        });
        if (original) { event.preventDefault(); original.click(); }
        // Otherwise use the real link; the stored menu survives full navigation.
      });
    }
    if (!rail.isConnected) document.body.append(rail);
    const nextSignature = JSON.stringify([links, location.pathname]);
    if (nextSignature === signature) return;
    signature = nextSignature;
    const heading = document.createElement("div");
    heading.className = "bf-sidebar-heading";
    heading.textContent = "Facebook Menu";
    rail.replaceChildren(heading);
    for (const item of links) {
      const link = document.createElement("a");
      link.href = item.href;
      link.title = item.label;
      link.setAttribute("aria-label", item.label);
      if (active(item.href, location.href)) link.setAttribute("aria-current", "page");
      const svg = document.createElementNS("http://www.w3.org/2000/svg", "svg");
      svg.setAttribute("viewBox", "0 0 24 24");
      svg.setAttribute("aria-hidden", "true");
      const path = document.createElementNS("http://www.w3.org/2000/svg", "path");
      path.setAttribute("d", symbols[item.label] || "M4 4h6v6H4zM14 4h6v6h-6zM4 14h6v6H4zM14 14h6v6h-6z");
      svg.append(path);
      const label = document.createElement("span");
      label.textContent = item.label;
      link.append(svg, label);
      rail.append(link);
    }
  }

  function resetLayout() {
    document.documentElement.removeAttribute("data-bf-persistent-sidebar");
    for (const element of shifted) element.removeAttribute("data-bf-shift-panel");
    shifted.clear();
  }

  function update() {
    const root = document.documentElement;
    if (!root || !document.body) return;
    const enabled = root.hasAttribute("data-better-facebook");
    const login = /^\/(login|logout|checkpoint|recover)(\/|\.|$)/.test(location.pathname) || document.querySelector('input[type="password"]');
    const native = document.querySelector(nativeSelector);
    if (enabled && native) capture(native);
    const nativeVisible = native && native.getBoundingClientRect().width > 0 && getComputedStyle(native).visibility !== "hidden";
    const show = enabled && !login && !document.fullscreenElement && !nativeVisible;
    if (!show) {
      resetLayout();
      return;
    }
    render();
    if (lastLocation !== location.href) { resetLayout(); lastLocation = location.href; }
    if (!root.hasAttribute("data-bf-persistent-sidebar")) {
      root.style.setProperty("--bf-original-body-padding", getComputedStyle(document.body).paddingLeft);
      root.setAttribute("data-bf-persistent-sidebar", "");
    }
    // Normal-flow content follows body padding. Fixed route menus need a separate offset.
    for (const element of document.querySelectorAll('[role="navigation"], [role="complementary"], [role="main"]')) {
      if (element === rail || shifted.has(element) || element.closest('[data-bf-shift-panel]')) continue;
      const rect = element.getBoundingClientRect();
      if (getComputedStyle(element).position === "fixed" && rect.left < 80 && rect.width > 100) {
        element.setAttribute("data-bf-shift-panel", "");
        shifted.add(element);
      }
    }
  }

  function schedule() {
    if (timer) return;
    timer = setTimeout(() => { timer = undefined; update(); }, 120);
  }
  new MutationObserver(records => {
    if (records.some(record => !rail?.contains(record.target))) schedule();
  }).observe(document, {
    childList: true, subtree: true, attributes: true,
    attributeFilter: ["data-better-facebook", "aria-label", "href"]
  });
  window.addEventListener("popstate", schedule);
  window.addEventListener("resize", () => { resetLayout(); schedule(); });
  document.addEventListener("fullscreenchange", schedule);
  chrome.storage.local.get(cacheKey).then(result => {
    if (!captured) {
      const saved = clean(result[cacheKey]);
      if (saved.length) links = saved;
    }
    schedule();
  }).catch(schedule);
  schedule();
})();
