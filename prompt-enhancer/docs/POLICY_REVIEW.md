# Chrome Web Store policy review

Reviewed 20 October 2026 against official Google documentation. This is a source-level engineering review, not Google approval. Live Chrome acceptance and publisher/dashboard declarations remain outstanding.

| Area | Code assessment / action | Publication requirement |
| --- | --- | --- |
| Single purpose | Improve/refine ChatGPT drafts using a user-operated local llama.cpp server. Status, Settings and setup support that purpose. | Use the same scope in the listing and dashboard. |
| Data access | Removed passive draft serialization for empty-button detection. Composer metadata/URL are inspected for integration; prompt and latest question-and-answer context extraction starts with Improve Prompt. Active preview safety comparisons continue after that action. Inline disclosure precedes that button. | Verify this with the real page; do not claim the extension handles no user data. |
| Transmission | Worker-only client fixes `127.0.0.1:8080`, omits credentials and rejects redirects. Popup only discovers models; no draft in status requests. | Explain loopback HTTP, user-controlled server logs/forwarding and ChatGPT draft handling. |
| Data retention | Settings only in `storage.local`; original prompt/rewrite in memory, clipboard only on Copy. Cancel/Apply do not erase memory instantly. | Host the accurate policy and disclose website content, including local handling. |
| Limited Use | No sales, ads, analytics, lending decisions or developer human prompt access. | Publish Limited Use disclosure and complete dashboard attestations truthfully. |
| Minimum permission | No expansion. `clipboardWrite` retained because removal has not been browser-tested. | Complete comparison in PERMISSIONS.md before declaring permission minimization finished. |
| MV3 executable code | Packaged JS/CSS only, no eval, remote scripts, CDN or execution of model output. Model output is text. | Declare no remote executable code; distinguish inference data from code. |
| User control | No automatic send. Apply verifies native editing; Copy fallback remains. | Verify real ProseMirror behavior, undo and ordinary Send manually. |
| Listing accuracy | Local server required; ChatGPT only; model compatibility not universal. | Capture real screenshots and supply reviewer setup instructions. |

Google's user-data FAQ explicitly includes locally processed data in disclosure requirements. It also distinguishes communication with a native program on the same computer from ordinary remote transmission requirements; the loopback design relies on that deployment, not on HTTP being encrypted. [User Data FAQ](https://developer.chrome.com/docs/webstore/program-policies/user-data-faq).

The dashboard requires a single-purpose explanation, permission reasons, remote-code declaration and accurate data practices. Prompt text is website content even when it never reaches the publisher. Review the current categories and disclose relevant personal/sensitive content when applicable; do not use “no developer server” to justify a blanket “no user data handled” answer. [Privacy fields](https://developer.chrome.com/docs/webstore/cws-dashboard-privacy).

Limited Use applies to allowed use/transfer and other restrictions; the product's disclosure must agree with its actual behavior. [Limited Use](https://developer.chrome.com/docs/webstore/program-policies/limited-use). Packaged logic and text-only model responses follow the distinction between remote data and remotely executed logic. [MV3 requirements](https://developer.chrome.com/docs/webstore/program-policies/mv3-requirements).

No screenshots have been fabricated. Browser automation tool discovery was unavailable during this preparation; no live extension screenshots or browser acceptance results are claimed. Screenshot requirements and capture plan are in `store/SCREENSHOTS.md`.
