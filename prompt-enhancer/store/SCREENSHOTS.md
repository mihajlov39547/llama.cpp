# Store graphics and screenshot capture plan

No live browser screenshots were captured during release preparation; automation tool discovery was unavailable. Do not use icon-preview.png or generated UI mockups as proof of working extension behavior.

Capture real Chrome behavior with the release package loaded, using synthetic text only. Target **1280 × 800 pixels** for each listing screenshot, PNG or JPEG as accepted by the dashboard. Supply at least one and up to five actual screenshots. Also prepare the required **440 × 280** small promotional tile; the **1400 × 560** marquee is optional. Verify the current dashboard specifications before uploading. [Official image requirements](https://developer.chrome.com/docs/webstore/images).

Suggested sequence:

1. **Toolbar status:** open the actual popup with the local server connected. Show product name, version 0.2.0, actual model name, endpoint and setup/settings actions. A popup is smaller than 1280×800: capture it in the full Chrome window, rather than stretching its pixels.
2. **Initial improvement:** ChatGPT composer containing a harmless synthetic draft with the real successful Improved Prompt preview open. Show the local-processing disclosure and Apply/Copy/Refine Further/Cancel.
3. **Refinement:** after a successful Refine Further call, show the actual updated suggestion and preserved original recovery view. Do not replace model text in an image editor.
4. **User control:** after Apply, show the resulting draft and closed preview, with no submitted message. Use only a test conversation/account with no private information.
5. **Setup/Settings:** show the real packaged guide or settings page, including the independently running local server requirement.

Procedure: load the ZIP contents unpacked in a clean Chrome profile, start the server, use a 1280×800 capture region at a readable scale, take unaltered captures, and check exact output dimensions. Use a clean test profile rather than painting over personal data. Name captures `01-toolbar.png` through `05-setup.png` under `store/screenshots/` after capture. Do not create placeholder files with those names.

The runtime icon is original geometric pencil/sparkle artwork, exported at 16, 32, 48 and 128 pixels; `icons/icon128.png` can serve as the store icon subject to dashboard requirements. The editable master and preview are development assets excluded from the release ZIP.
