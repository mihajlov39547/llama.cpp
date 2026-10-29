# Composite Extension

Standalone Chrome Manifest V3 extension, following the existing prompt-enhancer project's plain JavaScript structure. No build, model server, dependencies or configuration needed. Prompt Enhancer remains a separate extension.

## Install

1. Open `chrome://extensions` in Chrome (111 or later).
2. Enable **Developer mode**.
3. Click **Load unpacked** and select `C:\llama.cpp\composite-extension`.
4. Refresh existing Yahoo Mail and Pirate Bay tabs. Pin the extension to view its rule summary.

## Yahoo Mail

On `https://mail.yahoo.com/*`, `src/yahoo-mail.css` hides:

- The immediate div parent of a Taboola Yahoo Mail recommendation link.
- `section[data-test-id="novation-right-rail"]`, including its ads and Calendar/Starred/Contacts shortcuts as requested.

CSS applies to matching elements inserted later without polling or reading mail. It uses the link endpoint and stable data attribute, not generated classes, ad text or tracking IDs. Hiding does not stop Yahoo from fetching ads. Future markup changes may require updating the selectors.

## Pirate Bay

On Pirate Bay (HTTP/HTTPS, including subdomains), a document-start script cancels direct blocked-domain link clicks, middle clicks, form submissions and `window.open` calls. Other destinations pass through.

Version 0.1.1 also removes `href` and `target` from matching banner links, including `lp-direct.php`, disabling their normal navigation and context-menu open-link actions. An isolated content script handles existing links, dynamically inserted banners and rewritten destinations. It runs in matching Pirate Bay frames and related about:blank frames. Banner text stays visible. Banners hosted in unrelated third-party frames are outside this script's scope.

The static Chrome network rule separately blocks main-frame and subframe requests to `ultimatesurferprotector.com` and its subdomains whose initiator is `piratebay.party` or its subdomains. This also covers server redirects in those requests, because the initiator stays the same across redirects. Direct visits from the address bar and navigation from unrelated sites are not intentionally blocked.

Limitations: an indirectly created popup can still leave a blank or Chrome-blocked tab. A later navigation initiated by an unrelated intermediate page or third-party frame may have a different initiator and fall outside this scoped rule. Page scripts can interfere with the page-world guard; the Chrome network rule remains independent. This is a targeted blocker, not a general popup blocker.

## Privacy and permissions

Only the `declarativeNetRequest` permission is requested for Chrome's built-in blocking rule. Content scripts are limited to the two specified sites. No analytics, external services, saved browsing history, email capture or remote code.

## Verify

Run `node --test composite-extension/tests/guard.test.cjs` from `C:\llama.cpp`.

After loading in Chrome, check the extension's Errors panel, then verify the two Yahoo targets disappear on initial load and after mailbox navigation. Confirm ordinary messages remain visible. On Pirate Bay, confirm direct links/popups to the blocked domain do not open and normal links still work. Check network-blocked navigations in DevTools. Actual live-site behavior requires verification in your browser.

Implementation references: [Chrome network rules](https://developer.chrome.com/docs/extensions/reference/api/declarativeNetRequest/) and [content scripts](https://developer.chrome.com/docs/extensions/reference/manifest/content-scripts).
