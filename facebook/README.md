# Better Facebook

A small, build-free Manifest V3 extension for Chrome and Edge. Version 0.1.0 adds softer cards, more comfortable post line spacing, visible keyboard focus, optional larger post text, and optional focus mode. Facebook controls its own light/dark colors.

## Install

1. Open `chrome://extensions` (Chrome) or `edge://extensions` (Edge).
2. Enable **Developer mode** and select **Load unpacked**.
3. Select `C:\llama.cpp\facebook`.
4. Refresh existing Facebook tabs, then pin **Better Facebook** to your toolbar.
5. Open its toolbar popup to enable or pause Better Facebook. Changes apply immediately to open tabs. The compact English popup summarizes the cleaner layout and hidden Friends navigation/recommendations; previously saved text-size and focus preferences are preserved.

After editing the extension files, reload the extension on the extensions page and refresh Facebook.

## Persistent Facebook menu

The persistent menu uses the original 36px Facebook artwork supplied in `facebook_sidebar_icons/icons.json`. WebP resources are bundled under `icons/sidebar`, with no runtime CDN requests. Icons are matched by destination or label; Home, Your profile, and unknown items retain vector fallbacks. Only the bundled sidebar images are exposed to Facebook through the manifest.

Open Home once after updating so Better Facebook can read the expanded Shortcuts navigation. When that navigation is absent on Events, Groups, profiles, or another route, a separate menu remains on the left. Existing page-specific controls remain available beside it. On windows 1200px wide or narrower, the persistent menu uses icons with accessible labels and hover titles.

Navigation labels and destinations are stored locally so the menu survives reloads. Profile.php links are replaced by the generic Your profile link; query parameters are discarded. Friends, the Your shortcuts section, and footer links are excluded. Direct entry before visiting Home uses a basic menu. Disabling Better Facebook restores the original layout. Login screens and fullscreen views do not show the extra menu.

When a matching Facebook link exists, the menu activates that link to preserve in-page navigation. Otherwise it follows the destination normally and restores the menu after loading. The layout reserves space for the menu and offsets fixed left navigation panels. Facebook-specific layouts still need signed-in checks, particularly Events filters, Marketplace, and Messenger.

Run `node --test facebook/tests/*.test.cjs` from the workspace root for menu-data checks. Live browser validation is still required for layout and navigation behavior.

## Scope and privacy

- Runs only on `https://facebook.com/*` and `https://www.facebook.com/*`.
- Uses only the `storage` permission. Preferences are stored locally on this device.
- No analytics, remote scripts, network requests, or collection of posts/account information.
- Disabling it removes all styling hooks immediately.
- Focus mode hides complementary sidebars at widths of 1100px or more, preserving their layout space. This may include contacts or contextual panels; turn focus mode off to access them.
- Text size affects post messages, not the entire interface.

## Development and verification

`manifest.json` registers the content CSS/JS and popup. Shared defaults and validation live in `src/settings.js`. Styling uses semantic roles and post-message attributes instead of Facebook's generated class names. CSS automatically applies to dynamically added posts. A batched mutation observer identifies the English “Your shortcuts” heading and marks its section for CSS hiding, including after navigation. The Friends navigation item and People you may know card are also hidden. All hidden elements remain in the DOM and reappear when the extension is disabled.

Facebook changes its markup frequently, so some enhancements may not apply to every feed variant. Signed-in feed appearance has not yet been verified. Before relying on this version, check Home, profiles, Groups, and Marketplace in both Facebook themes; verify text sizing, focus mode, keyboard navigation, and that disabling restores the original appearance. On narrow screens, verify sidebars remain available.
