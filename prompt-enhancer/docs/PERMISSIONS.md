# Permission justifications — 0.2.0

No new permission was added for the popup or setup guide.

Version 0.4.0 exports Markdown and images without new permissions. A trusted click reads the saved conversation through same-origin ChatGPT requests using the current session token in memory, resolves image assets and fetches their bytes subject to browser CORS. No bearer token is sent to image hosts. Downloads use local Blobs and an anchor, not the downloads API. Export does not contact the AI server or access other tabs.

| Access | Current use | Review |
| --- | --- | --- |
| `storage` | Save and retrieve only configuration in `chrome.storage.local`. | Retained; no prompt persistence or sync storage. |
| `clipboardWrite` | Explicit Copy actions using `navigator.clipboard.writeText`. Never reads clipboard data. | Retained pending real-Chrome removal testing; not requested for background copying. |
| `http://127.0.0.1:8080/*` host permission | Worker fetches model discovery and non-streaming completions from the local server. | Retained. API validation fixes the base URL and rejects redirects; do not rely solely on manifest URL matching to constrain network traffic. |
| Content-script match `https://chatgpt.com/*` | Locate composer, add controls, read draft and latest question-and-answer pair after Improve Prompt, detect edits/navigation, apply only after user click. | Narrow target website, no general browsing access. |
| Web-accessible `src/styles.css`, ChatGPT match only | Load packaged styles inside the content script's Shadow DOM. | No scripts/data exposed this way. |

`action`, icons, the popup and `options_page` are manifest features, not additional permissions. Opening the local setup page or Settings does not require `tabs` permission. The worker uses the existing `tabs.onRemoved` event to abort tab requests; it does not enumerate tabs or browse their history.

No `<all_urls>`, `activeTab`, `scripting`, `clipboardRead`, `history`, `cookies`, `webRequest`, `downloads`, native messaging or optional/runtime host permission is requested.

## Clipboard minimum-permission decision

Copy is a core fallback when native editor replacement cannot be verified. The current permission supports clipboard writes from the content script. A user-gesture write on a secure page may work without it, but this has **not been verified in live Chrome** for this extension, denied clipboard site settings, focus changes or Chrome versions. Removing it without that testing would risk the fallback. It has therefore not been removed automatically.

Before submission, test a separate unpacked copy with `clipboardWrite` omitted: Copy on actual ChatGPT in light/dark mode, ordinary and denied clipboard site settings, after refinement/error, and after focus changes. Verify actual paste into another application. If supported behavior is equivalent, remove the permission from the shipping manifest, rerun tests, rebuild the ZIP and update the listing/policy. Otherwise retain it with the current narrow explanation and record the observed need. No claim that removal was tested is made here.

Google requires the least access needed for implemented functionality; this outstanding clipboard check is a publication checklist item, not a reason to add broader access. [Official Use of Permissions policy](https://developer.chrome.com/docs/webstore/program-policies/permissions).
