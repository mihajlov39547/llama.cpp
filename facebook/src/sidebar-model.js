(() => {
  const defaults = [
    ["/", "Home"], ["/me/", "Your profile"], ["/events/", "Events"],
    ["/groups/", "Groups"], ["/marketplace/", "Marketplace"],
    ["/saved/", "Saved"], ["/memories/", "Memories"], ["/feeds/", "Feeds"]
  ].map(([href, label]) => ({ href, label }));
  function clean(items) {
    const result = [];
    const seen = new Set();
    for (const item of Array.isArray(items) ? items.slice(0, 80) : []) {
      if (!item || typeof item.href !== "string" || typeof item.label !== "string") continue;
      let url;
      try { url = new URL(item.href, "https://www.facebook.com"); } catch { continue; }
      if (url.protocol !== "https:" || !["facebook.com", "www.facebook.com"].includes(url.hostname)) continue;
      if (/^\/(friends|login|logout|checkpoint|privacy|policies|help)(\/|\.|$)/i.test(url.pathname)) continue;
      // Store only navigation destinations, never account IDs, names or tracking queries.
      const profile = url.pathname === "/profile.php" || url.pathname === "/me/";
      const href = profile ? "/me/" : url.pathname;
      const key = href.replace(/\/$/, "") || "/";
      const label = profile ? "Your profile" : item.label.replace(/[\u200b-\u200f\ufeff]/g, "").trim().slice(0, 60);
      if (!label || seen.has(key)) continue;
      seen.add(key);
      result.push({ href, label });
    }
    return result;
  }
  function active(href, current) {
    const path = new URL(href, "https://www.facebook.com").pathname.replace(/\/$/, "") || "/";
    const here = new URL(current, "https://www.facebook.com").pathname.replace(/\/$/, "") || "/";
    return path === "/" ? here === "/" : here === path || here.startsWith(path + "/");
  }
  globalThis.BetterFacebookSidebar = { defaults, clean, active };
})();
