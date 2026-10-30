# Composite Extension

Standalone Chrome Manifest V3 extension, following the existing prompt-enhancer project's plain JavaScript structure. No build, model server, dependencies or configuration needed. Prompt Enhancer remains a separate extension.

## Install

1. Open `chrome://extensions` in Chrome (111 or later).
2. Enable **Developer mode**.
3. Click **Load unpacked** and select `C:\llama.cpp\composite-extension`.
4. Refresh existing Yahoo Mail and Pirate Bay tabs. Pin the extension to view its rule summary.

## Cosmetic ad hiding on all websites (0.3.0)

On HTTP/HTTPS pages, including matching embedded frames, CSS hides common Google ad containers with `display: none !important`. Elements stay in the DOM. This includes the supplied `ins.adsbygoogle.adsbygoogle-noablate` fixed banner and its entire contents. CSS also applies to newly inserted elements.

Google advertising network rules and the DOM-removal script were removed in 0.3.0. Ad requests and scripts are allowed to load, including tracking and cookie syncing. Only the separate Pirate Bay unwanted-navigation blocker retains network blocking. Reload the extension and refresh pages to discard the previous removal script and reload previously blocked resources.

Cosmetic hiding cannot guarantee identical site behavior: hidden elements have no layout size, so size-sensitive or lazy-loaded ads may behave differently. Server/CORS errors, document.write warnings and blocking by other extensions may remain. This extension no longer generates network blocks for Google advertising requests.

Reload the extension and refresh open pages after upgrading. Chrome may request access to all websites; allow that access for global ad removal. Chrome's protected pages (such as chrome:// pages and the Web Store) do not allow these content scripts. Incognito requires separately enabling the extension there.

This targets common AdSense/Google Ad Manager ads, not every possible ad format: YouTube video ads, sponsored search results, first-party/proxied ads and closed shadow DOM content are not comprehensively covered. Some sites may show anti-adblock notices. No page text or browsing data is collected or transmitted.

## Billboard and AdOcean banners on all websites (0.2.3)

Any container labeled `data-placeholder-caption="Oglas"` that contains `.wrapperAd` is hidden in full, regardless of the ad slot ID. This covers `Billboard_2`, `Billboard_3`, `P1` and sticky variants, including their placeholder spacing, on all HTTP/HTTPS sites. It also applies when the ad slot is inserted later.

`src/billboards.css` runs on all HTTP/HTTPS websites and matching frames. It hides `#Billboard.wrapperAd` slots and the supplied `Oglas`, `.container.desktop-bnr` and `.bnr.billboard` wrappers when they contain that slot. It also hides AdOcean divs identified by their ID prefix and their `.banner`, `.banner-wrapper` and `.banner-inner` ancestors. Matching the outer wrappers removes their reserved space as well.

The previous Informer footer rule now applies globally: it hides the entire AdOcean footer billboard, including its translucent background, using the `billboard` ID prefix and AdOcean close-control class. Randomized suffixes do not matter. CSS also applies to banners inserted later. These are cosmetic rules; they do not block AdOcean network requests or hide every generic element named banner.

## RTS compatibility (0.2.4)

RTS calls `Cookies.get('promo_seen')` and `Cookies.set(...)` in its mobile app promotion code. A bundled js-cookie 3.0.5 fallback runs only on https://www.rts.rs/ and https://rts.rs/, before page scripts, and only if `Cookies` is undefined. It preserves an existing implementation and does not read or write cookies at initialization. The site's own calls retain their normal behavior; no consent or promo value is fabricated. Source: https://www.npmjs.com/package/js-cookie/v/3.0.5 (MIT license bundled in src/vendor/js-cookie-LICENSE.txt). No library is downloaded at runtime.

Browser document.write, preload and unsupported-feature warnings are not suppressed. This fallback does not establish the cause of any persistent loading indicator.

## Yahoo Mail rules

On `https://mail.yahoo.com/*`, `src/yahoo-mail.css` hides:

- The immediate div parent of a Taboola Yahoo Mail recommendation link.
- `section[data-test-id="novation-right-rail"]`, including its ads and Calendar/Starred/Contacts shortcuts as requested.

CSS applies to matching elements inserted later without polling or reading mail. It uses the link endpoint and stable data attribute, not generated classes, ad text or tracking IDs. Hiding does not stop Yahoo from fetching ads. Future markup changes may require updating the selectors.

## Pirate Bay

On Pirate Bay (HTTP/HTTPS, including subdomains), a document-start script cancels direct blocked-domain link clicks, middle clicks, form submissions and `window.open` calls. Other destinations pass through.

Version 0.1.2 removes matching links and their contents, embedded frames, forms, and scripts with literal `ultimatesurferprotector.com` references. It also strips attributes containing that domain, including inline event handlers. An isolated content script handles existing elements, dynamically inserted banners and changed attributes. It runs in matching Pirate Bay frames and related about:blank frames. Banners hosted in unrelated third-party frames are outside this script's scope unless the embedding frame's attributes contain the domain. Removing a script after it has executed cannot undo its listeners or timers; encoded or dynamically assembled URLs may not contain a literal domain reference. The popup guard and network block remain as fallbacks.

The static Chrome network rule separately blocks main-frame and subframe requests to `ultimatesurferprotector.com` and its subdomains whose initiator is `piratebay.party` or its subdomains. This also covers server redirects in those requests, because the initiator stays the same across redirects. Direct visits from the address bar and navigation from unrelated sites are not intentionally blocked.

Limitations: an indirectly created popup can still leave a blank or Chrome-blocked tab. A later navigation initiated by an unrelated intermediate page or third-party frame may have a different initiator and fall outside this scoped rule. Page scripts can interfere with the page-world guard; the Chrome network rule remains independent. This is a targeted blocker, not a general popup blocker.

## Privacy and permissions

The `declarativeNetRequest` permission is used only for the Pirate Bay unwanted-navigation rule. Ad-hiding CSS runs on all HTTP/HTTPS sites; Yahoo, RTS and Pirate Bay features remain limited to their respective sites. The extension has no analytics, external services, saved browsing history, email capture or remote code. Websites' own advertising and tracking requests are allowed.

## Verify

Run `node --test composite-extension/tests/*.test.cjs` from `C:\llama.cpp`.

After loading in Chrome, check the extension's Errors panel, then verify the two Yahoo targets disappear on initial load and after mailbox navigation. Confirm ordinary messages remain visible. On Pirate Bay, confirm direct links/popups to the blocked domain do not open and normal links still work. Check network-blocked navigations in DevTools. Actual live-site behavior requires verification in your browser.

Implementation references: [Chrome network rules](https://developer.chrome.com/docs/extensions/reference/api/declarativeNetRequest/) and [content scripts](https://developer.chrome.com/docs/extensions/reference/manifest/content-scripts).
