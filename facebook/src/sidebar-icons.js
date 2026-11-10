// Original Facebook artwork and sprite offsets supplied in facebook_sidebar_icons/icons.json.
(() => {
  const icons = {
  "meta-ai": {
    "name": "Meta AI",
    "file": "icons/sidebar/CHMV2nOM9jW.webp",
    "position": "0 0"
  },
  "friends": {
    "name": "Friends",
    "file": "icons/sidebar/wZBdW_qnLOB.webp",
    "position": "0 -851px"
  },
  "creator-dashboard": {
    "name": "Creator Dashboard",
    "file": "icons/sidebar/wZBdW_qnLOB.webp",
    "position": "0 -1332px"
  },
  "memories": {
    "name": "Memories",
    "file": "icons/sidebar/wZBdW_qnLOB.webp",
    "position": "0 -1221px"
  },
  "saved": {
    "name": "Saved",
    "file": "icons/sidebar/wZBdW_qnLOB.webp",
    "position": "0 -518px"
  },
  "groups": {
    "name": "Groups",
    "file": "icons/sidebar/wZBdW_qnLOB.webp",
    "position": "0 -185px"
  },
  "reels": {
    "name": "Reels",
    "file": "icons/sidebar/wZBdW_qnLOB.webp",
    "position": "0 -111px"
  },
  "ad-center": {
    "name": "Ad Center",
    "file": "icons/sidebar/wZBdW_qnLOB.webp",
    "position": "0px -1036px"
  },
  "ads-manager": {
    "name": "Ads Manager",
    "file": "icons/sidebar/wZBdW_qnLOB.webp",
    "position": "0px -407px"
  },
  "birthdays": {
    "name": "Birthdays",
    "file": "icons/sidebar/_1B5IH4MpiR.webp",
    "position": "0px 0px"
  },
  "events": {
    "name": "Events",
    "file": "icons/sidebar/wZBdW_qnLOB.webp",
    "position": "0px -666px"
  },
  "feeds": {
    "name": "Feeds",
    "file": "icons/sidebar/6H6EFrx5Jjl.webp",
    "position": "0 0"
  },
  "gaming-video": {
    "name": "Gaming Video",
    "file": "icons/sidebar/JYr05Vf7xjV.webp",
    "position": "0 0"
  },
  "marketplace": {
    "name": "Marketplace",
    "file": "icons/sidebar/wZBdW_qnLOB.webp",
    "position": "0px -999px"
  },
  "messenger": {
    "name": "Messenger",
    "file": "icons/sidebar/pyL74GbHm4L.webp",
    "position": "0px 0px"
  },
  "orders-and-payments": {
    "name": "Orders and payments",
    "file": "icons/sidebar/R4eauTzM8dl.webp",
    "position": "0 0"
  },
  "pages": {
    "name": "Pages",
    "file": "icons/sidebar/wZBdW_qnLOB.webp",
    "position": "0px -333px"
  },
  "play-games": {
    "name": "Play games",
    "file": "icons/sidebar/wZBdW_qnLOB.webp",
    "position": "0px -259px"
  },
  "your-ad-activity": {
    "name": "Your Ad Activity",
    "file": "icons/sidebar/ITvoZIONvPL.webp",
    "position": "0 0"
  }
};
  const routes = {
    '/events': 'events', '/groups': 'groups', '/marketplace': 'marketplace',
    '/saved': 'saved', '/memories': 'memories', '/onthisday': 'memories',
    '/feeds': 'feeds', '/gaming/video': 'gaming-video', '/gaming/play': 'play-games',
    '/games': 'play-games', '/messages': 'messenger', '/pages': 'pages',
    '/ad_center': 'ad-center', '/ads/manager': 'ads-manager', '/adsmanager': 'ads-manager',
    '/birthdays': 'birthdays', '/orders_and_payments': 'orders-and-payments',
    '/recent_ad_activity': 'your-ad-activity', '/professional_dashboard': 'creator-dashboard',
    '/reel': 'reels', '/reels': 'reels', '/friends': 'friends'
  };
  function resolve(item) {
    let pathname;
    try { pathname = new URL(item.href, 'https://www.facebook.com').pathname.replace(/\/$/, ''); }
    catch { return null; }
    const route = Object.keys(routes).sort((a, b) => b.length - a.length)
      .find(key => pathname === key || pathname.startsWith(key + '/'));
    const label = String(item.label || '').trim().toLowerCase();
    return (route && icons[routes[route]]) || Object.values(icons).find(icon => icon.name.toLowerCase() === label) || null;
  }
  globalThis.BetterFacebookSidebarIcons = { resolve };
})();
