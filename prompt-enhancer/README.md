# Local Llama Prompt Enhancer

Vanilla JavaScript Manifest V3 extension for `https://chatgpt.com/`. Improve a draft with a local llama.cpp model, review the suggestion, then Apply, Copy, Retry, or Cancel. Apply never submits a message.

## Start the server

This machine has `C:\llama.cpp\bin\llama-server.exe`. In PowerShell, substitute the path to your GGUF:

```powershell
& C:\llama.cpp\bin\llama-server.exe -m "C:\models\your-model.gguf" --host 127.0.0.1 --port 8080
```

Keep the server running and wait for the model to load. If it is already running on port 8080, use that instance. The extension discovers its model ID through `GET /v1/models`; no model filename is hardcoded.

## Install

1. Open `chrome://extensions` in Chrome.
2. Enable **Developer mode**, click **Load unpacked**, and select `C:\llama.cpp\prompt-enhancer`.
3. Open the extension's **Details → Extension options** and click **Test saved connection**.
4. Open or refresh `https://chatgpt.com/`. Existing tabs need a refresh after installing or reloading the extension.
5. Type a draft and click **Improve Prompt** in the added row near the composer footer.

No build step or npm installation is needed. `icons/` remains available for future branding; the manifest does not reference missing icon files.

## Usage and configuration

The preview renders model output as text with line breaks. Apply attempts a native text replacement and verifies the result twice. Copy provides a clipboard alternative. Retry reads the **current draft**, including your latest changes. Cancel aborts the client request and hides the panel without replacing the draft.

If the draft, editor instance, or chat changes after a request starts, Apply is disabled. Use Retry to improve the new draft, or Copy to merge the suggestion yourself.

Expand **Original prompt (recovery copy)** to select or copy the captured original. It remains in page memory after Apply, until the next request or page unload. Native editing also allows Ctrl+Z. Copy the original before refreshing if you need durable recovery; prompts are not persisted to extension storage.

Options are stored in `chrome.storage.local`:

| Setting | Default | Allowed |
| --- | --- | --- |
| API base URL | `http://127.0.0.1:8080` | Fixed |
| Temperature | `0.2` | 0–2 |
| Max output tokens | `2048` | 1–4096 |
| Timeout | 60 seconds | 1–60 seconds |
| Maximum input | 20,000 characters | 1–20,000 |

The connectivity test checks model discovery, not inference. The origin is deliberately fixed; changing origins requires editing both manifest host permissions and adapter validation. There are no runtime permission requests.

## Architecture and files

- `manifest.json`: MV3 manifest, ChatGPT content-script matching, local host permission, options page, and packaged stylesheet resource.
- `src/editor.js`: ordered editor selectors, paragraph/line-break extraction, native replacement and verification. Loaded before `content.js` as a classic script.
- `src/content.js`: Shadow DOM controls, MutationObserver reattachment, navigation detection, changed-draft protection, request watchdog, recovery copy and cleanup.
- `src/styles.css`: isolated light/dark composer UI. Uses ChatGPT's root theme class when available, otherwise the system scheme.
- `src/background.js`: classic service worker using `importScripts`; validates message type, extension ID, top-level ChatGPT sender URL/tab, prompt and request ID. Options connectivity messages are restricted to the extension options page. Tracks one request per tab, handles cancellation and tab closure, and returns structured success/error objects.
- `src/llama-api.js`: validated settings, model discovery, timeout/cancellation, HTTP/JSON handling and non-streaming completion parsing.
- `src/prompt-template.js`: complete system instruction included on **every** rewrite request.
- `src/options.html`, `src/options.css`, `src/options.js`: saved settings and connectivity test.
- `tests/adapter.test.cjs`: dependency-free adapter, manifest, sender and editor-guard tests.
- `tests/live-smoke.cjs`: optional real-server test using a synthetic prompt.

Data flow: `content.js → chrome.runtime.sendMessage → background.js → /v1/models → /v1/chat/completions → preview`.

Each rewrite uses two messages only: the full system instruction and the captured user prompt. It sends `stream: false`, temperature and token limit, without tools or conversation history. It expects `choices[0].message.content`; the streaming `delta` chunks in the sample API trace are intentionally not used.

The content script never fetches the local server. Requests omit credentials, reject redirects, and use only the fixed local base URL. Permissions are `storage`, `clipboardWrite`, and the local host entry; there is no `<all_urls>`, `scripting`, or broad `tabs` permission. The stylesheet alone is web-accessible to ChatGPT.

## Automated checks

Requires Node.js only for tests, not for using the extension:

```powershell
cd C:\llama.cpp\prompt-enhancer
node --test tests/adapter.test.cjs
node tests/live-smoke.cjs
```

Verification performed on 2026-10-20:

- All 20 dependency-free tests passed: manifest parsing/referenced files, JS syntax, model discovery, complete independent request payloads, completion parsing, missing model, HTTP/offline/invalid JSON/empty/truncated output, input/settings validation, abort/timeout, sender rejection, multiline extraction, stale draft protection and failed replacement verification.
- Real adapter request passed against the running local server. Discovered `google_gemma-4-E2B-it-Q4_K_M.gguf` and received: “Explain how a JavaScript array works. Keep the explanation short and use one example.”
- **Not verified in Chrome:** unpacked loading, live ChatGPT button layout, navigation, clipboard, native ProseMirror Apply/undo and ordinary composer behavior. Browser automation tooling could not be discovered in this session. Editor tests use minimal DOM mocks and do not prove ProseMirror compatibility.

## Manual acceptance checklist

1. Load unpacked; confirm no manifest/service-worker errors in `chrome://extensions`. Run options connection test.
2. Check the button is visible, fits without overlapping Send, and is disabled for empty/whitespace-only drafts. Check light/dark mode and a narrow window.
3. Enter multiple paragraphs, blank lines, Shift+Enter line breaks, code, a Windows path and a URL. Improve and inspect **Original prompt** for preserved text.
4. In the service-worker inspector's Network panel, confirm model discovery and a POST with `stream: false`, the discovered model, the full system instruction and the exact draft. Repeat and confirm no history accumulates.
5. Confirm loading state prevents duplicate requests. Verify preview line breaks and that HTML-like output is shown literally.
6. Apply; confirm only the draft changes. Type another character, move focus away/back, and check the rewrite persists. Verify Ctrl+Z and Copy original recovery. Confirm no user message appeared in the conversation.
7. Copy and paste into a separate text field. Cancel a preview and cancel while processing; confirm the original draft remains untouched and late responses do not reopen the panel.
8. Modify the draft during inference and after preview. Apply must be disabled; Retry must use the changed draft. Check that editing then undoing still requires Retry.
9. Navigate between chats, start a new chat, and trigger composer recreation. There must be one button; stale suggestions must not apply to the new composer. Retry should work.
10. Stop the local server: expect a visible connection error, with the draft intact. Test model-loading/503, missing-model, invalid-JSON and empty-output responses with mocks if needed (automated tests cover these).
11. Set a one-second timeout and retry; verify timeout UI and unchanged draft, then restore 60 seconds. Test oversized input.
12. During a request, stop the extension worker through Chrome's worker tooling or reload the extension. Expect a channel error or the 65-second UI watchdog; refresh ChatGPT after extension reload and Retry. Never automatically replay a request.
13. Check regular typing, paste, keyboard shortcuts, attachments, Send and manual submission still work. Test Apply with multiline drafts specifically; if verification fails, use Copy.
14. Check the ChatGPT console and extension error page for new errors.

## Limitations

- ChatGPT provides no public editor integration API. This MVP uses native `execCommand('insertText')`, rather than direct DOM assignment or private ProseMirror internals. The command is deprecated and could stop working in a future browser. Verification checks visible text after 100 and 300 ms; it cannot prove private editor state or prevent a later site regression. Failed verification leaves the observed draft alone and exposes Copy/recovery instead of risking an automatic rollback over newer typing.
- The button uses its own row inside the composer, not ChatGPT's Send control. Future DOM/layout changes may require selector or placement updates.
- This is a plain-text enhancer; it does not send attachments or serialize rich editor metadata. Review technical details in every rewrite.
- The 60-second AbortController timeout is an upper bound, not a guarantee that Chrome will keep the worker alive. Chrome can terminate a worker when a fetch response takes over 30 seconds. Lost messaging channels and the 65-second content watchdog show errors and permit Retry. Requests are not resumed or silently replayed. See [Chrome's service-worker lifecycle documentation](https://developer.chrome.com/docs/extensions/develop/concepts/service-workers/lifecycle).
- Cancel aborts fetch and ignores late results; the server may continue inference until it notices disconnection.
- The first valid discovered model is selected. Authenticated endpoints, alternate origins, streaming and multi-model selection are outside this MVP. A 20,000-character input may still exceed a particular model/server context limit; server errors are surfaced.
- Recovery is in-memory plain text and is replaced by a new Improve/Retry request. It is not a persistent backup. Failed clipboard access leaves selectable text for manual Ctrl+C.
