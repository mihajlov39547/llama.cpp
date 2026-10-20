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
5. Type a draft and click **Improve Prompt** in the added row immediately above the composer form.

No build step or npm installation is needed. `icons/` remains available for future branding; the manifest does not reference missing icon files.

## Usage and configuration

The preview renders model output as text with line breaks, indentation and trailing blank lines. Apply attempts one native text replacement and verifies the result twice. It rechecks the editor after focus, does not refocus after the asynchronous checks, and restores the prior caret selection if the command is rejected without changing text. Copy provides a clipboard alternative. Retry reads the **current draft**, including your latest changes. Cancel aborts the client request and hides the panel without replacing the draft. Click Improve Prompt to start again immediately after Cancel.

If the draft, editor instance, or chat changes after a request starts, Apply is disabled. Use Retry to improve the new draft, or Copy to merge the suggestion yourself.

After Apply successfully inserts and verifies the rewrite, the Improved Prompt panel closes automatically. If replacement fails, the panel stays open with the error and Copy fallback.

Before applying, expand **Original prompt (recovery copy)** to select or copy the captured original. It remains in page memory after Apply, until the next request or page unload, but the panel is closed. Native editing also allows Ctrl+Z. Copy the original before applying or refreshing if you need durable recovery; prompts are not persisted to extension storage.

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
- `src/settings.js`: shared defaults, numeric bounds, settings/input validators and response watchdog duration. Loaded by content scripts, options and worker; saved settings retain the original schema.
- `src/content.js`: Shadow DOM controls, MutationObserver reattachment, navigation detection, changed-draft protection, request watchdog, recovery copy and cleanup.
- `src/styles.css`: isolated light/dark composer UI. Uses ChatGPT's root theme class when available, otherwise the system scheme.
- `src/background.js`: classic service worker using `importScripts`; validates message type, extension ID, top-level ChatGPT sender URL/tab, prompt and request ID. Options connectivity messages are restricted to the extension options page. Tracks one request per tab, handles cancellation and tab closure, and returns structured success/error objects.
- `src/llama-api.js`: uses the shared settings validator, discovers models, handles timeout/cancellation and HTTP/JSON errors, and parses non-streaming completions.
- `src/prompt-template.js`: complete system instruction included on **every** rewrite request.
- `src/options.html`, `src/options.css`, `src/options.js`: saved settings and connectivity test.
- `tests/adapter.test.cjs`: dependency-free adapter, manifest, sender and editor-guard tests.
- `tests/hardening.test.cjs`, `tests/helpers.cjs`: regression coverage and DOM/Chrome test doubles with the supplied ChatGPT ProseMirror hierarchy, including nested lists and code.
- `tests/live-smoke.cjs`: optional real-server test using a synthetic prompt.

Data flow: `content.js → chrome.runtime.sendMessage → background.js → /v1/models → /v1/chat/completions → preview`.

Each rewrite uses two messages only: the full system instruction and the captured user prompt. It sends `stream: false`, temperature and token limit, without tools or conversation history. It expects `choices[0].message.content`; the streaming `delta` chunks in the sample API trace are intentionally not used.

The content script never fetches the local server. Requests omit credentials, reject redirects, and use only the fixed local base URL. Permissions are `storage`, `clipboardWrite`, and the local host entry; there is no `<all_urls>`, `scripting`, or broad `tabs` permission. The stylesheet alone is web-accessible to ChatGPT.

## Automated checks

Requires Node.js only for tests, not for using the extension:

```powershell
cd C:\llama.cpp\prompt-enhancer
node --test tests/*.test.cjs
node tests/live-smoke.cjs
```

Verification performed on 2026-10-20:

- All 45 tests passed: the original 20 plus 25 regression tests. Coverage includes manifest/dependency checks, JS syntax, adapter request/errors, text serialization, focus/selection guards, request races, mutation bursts, composer recreation, shared settings, worker/channel errors and timeout recovery.
- The initial implementation's real adapter request passed against `google_gemma-4-E2B-it-Q4_K_M.gguf`. The hardening review does not rerun that optional live request.
- **Not verified in Chrome:** unpacked loading, live ChatGPT layout, navigation, clipboard, native ProseMirror Apply/undo and ordinary composer behavior. No live browser tests were executed during this hardening review. DOM/Chrome doubles test control flow and serialization, not actual browser layout, undo or private ProseMirror state.

## Hardening corrections

- Nested lists previously lost markers, numbering and indentation. Lists now serialize as Markdown-style text (including ordered-list start/item values); paragraph blank lines remain explicit. Literal code and fenced text are retained without added fences. A sole BR in CODE/PRE is no longer mistaken for an empty paragraph placeholder.
- The API no longer trims leading indentation or trailing blank lines from valid output. CRLF is normalized to LF consistently with extraction.
- Focus could recreate the editor after the original safety check. Apply now rechecks connectivity/identity and actual focus before selecting text. Rejected native edits no longer leave the entire unchanged draft selected. Input after the native command invalidates verification, even if text later matches again.
- Cancel previously left a busy worker entry until fetch settled, rejecting an immediate Retry. Cancellation now releases that entry synchronously; request identity guards prevent old completion/cleanup from affecting a newer request. Cancellation before storage returns never starts inference.
- Content validation previously hardcoded 20,000 characters, ignoring a lower saved limit. Content, options and adapter now use one source of settings bounds; each request checks current saved settings before dispatch. Worker validation remains authoritative if settings change concurrently.
- Controls now occupy a normal-flow sibling row before the composer form (or before the composer body/input when no form exists), rather than joining its internal grid/flex footer. The editor and Send remain in their existing parents. Mutation tests confirm one host and proper reinjection cleanup; they cannot verify pixel-level layout.
- Leaving via back/forward cache now clears loading and explains cancellation instead of retaining a misleading “Improving” message. Lost channels and timeouts remain explicit errors, with no automatic replay.

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

### Exact Chrome hardening verification

1. Open `chrome://extensions`, click **Reload** on Local Llama Prompt Enhancer, then refresh the ChatGPT tab. In extension **Details → Extension options**, save default values and click **Test saved connection**. Confirm no extension errors.
2. Open ChatGPT DevTools, enable the device toolbar, and test viewport widths **360 px** and **1280 px**. Repeat with ChatGPT Settings → General → Theme set to Light and Dark. Confirm exactly one Improve Prompt row above the composer; expand the preview and Original prompt details, and confirm neither covers the editable area or Send.
3. Enter this text using Shift+Enter for line breaks, with two empty lines between the first and second sections:

   ````text
   Review these steps:


   3. Inspect C:\projects\demo\src\main.js
      - Keep https://example.com/a?x=1&y=2 unchanged.
        1. Preserve this nested step.

   ```js
     if (ready) {
       console.log("C:\\projects\\demo");
     }
   ```
   ````

   Click **Improve Prompt**, expand **Original prompt**, and compare paths, URL, blank lines, indentation and backslashes. If ChatGPT renders lists/code as rich nodes, inspect the editor in Elements and repeat with those rendered nodes; plain Markdown typing alone does not test rich list extraction.
4. Click **Apply**. Confirm the draft changes but no conversation message appears. Type a character, move focus elsewhere and back, and verify the rewrite persists. Use **Ctrl+Z** to inspect native undo behavior (the last typed character may be undone first). Verify **Copy** and **Copy original** by pasting into Notepad. Do not click Send during this check.
5. Start another request, click **Cancel**, then immediately click **Improve Prompt**. Confirm the second request starts without a BUSY error. Cancel again and wait longer than the original request's expected duration: the panel must stay closed. A late result must never replace a newer preview.
6. Start a request and edit the draft, then press Ctrl+Z to restore the original text. On response, **Apply must still be disabled**. Click **Retry** and confirm Original prompt reflects the current draft.
7. While a request is running, open another chat or start a new chat. Confirm one control row remains, the old request cannot apply, and the new draft is untouched. Navigate Back/Forward and confirm the UI is not stuck loading.
8. In extension options, save **Maximum input characters = 10**. In ChatGPT enter `12345678901` and click Improve Prompt. Expect the 10-character error without a completion request. Replace it with `1234567890`: it should be accepted. Restore **20,000** afterward.
9. Save **Timeout = 1 second** and request a sufficiently long rewrite. If inference exceeds that time, expect a timeout error with no draft change or automatic resend. Restore **60 seconds**. A faster model may finish before the timeout.
10. For a worker interruption, start a request, open `chrome://serviceworker-internals/`, find the registration whose scope is `chrome-extension://<the extension ID>/`, and click **Stop** if that control is available in your Chrome version. Return to ChatGPT: expect a channel error or the watchdog within 65 seconds. Only clicking Retry should initiate another request. If worker controls are unavailable, use extension **Reload** during processing to test invalidated messaging, then refresh ChatGPT to reconnect.
11. Test normal typing, paste, Shift+Enter, existing ChatGPT shortcuts and attachments. To test ordinary Send separately, manually send a harmless test draft; it should occur only on your explicit Send/Enter action. Confirm no new extension/ChatGPT console errors.

## Limitations

- ChatGPT provides no public editor integration API. This MVP uses native `execCommand('insertText')`, rather than direct DOM assignment or private ProseMirror internals. The command is deprecated and could stop working in a future browser. Verification checks visible text after 100 and 300 ms; it cannot prove private editor state or prevent a later site regression. Failed verification leaves the observed draft alone and exposes Copy/recovery instead of risking an automatic rollback over newer typing.
- The button uses its own row above the composer form, outside its internal editor/Send layout. Future DOM/layout changes may require selector or placement updates; no pixel-level non-overlap guarantee is inferred from mocked tests.
- This is a plain-text enhancer; it does not send attachments or serialize rich editor metadata. Review technical details in every rewrite.
- The 60-second AbortController timeout is an upper bound, not a guarantee that Chrome will keep the worker alive. Chrome can terminate a worker when a fetch response takes over 30 seconds. Lost messaging channels and the 65-second content watchdog show errors and permit Retry. Requests are not resumed or silently replayed. See [Chrome's service-worker lifecycle documentation](https://developer.chrome.com/docs/extensions/develop/concepts/service-workers/lifecycle).
- Cancel aborts fetch and ignores late results; the server may continue inference until it notices disconnection.
- The first valid discovered model is selected. Authenticated endpoints, alternate origins, streaming and multi-model selection are outside this MVP. A 20,000-character input may still exceed a particular model/server context limit; server errors are surfaced.
- Recovery is in-memory plain text and is replaced by a new Improve/Retry request. It is not a persistent backup. Failed clipboard access leaves selectable text for manual Ctrl+C.
