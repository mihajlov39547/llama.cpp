# Local Prompt Enhancer — Privacy Policy

Version 0.4.0 · Last updated 30 October 2026

Publisher/contact: **[PUBLISHER NAME AND PRIVACY CONTACT — complete before publication]**

## Purpose and data access

Local Prompt Enhancer edits prompts in the ChatGPT composer using a separately running llama.cpp server chosen and operated by the user. It does not provide a developer-hosted AI service.

The content script runs only on `https://chatgpt.com/*`. It locates the composer and observes DOM changes to attach its controls. It inspects the current ChatGPT page URL locally to detect navigation; it does not transmit that URL to the model. Before an Improve Prompt or Export chat click, it does not extract draft or conversation text. Clicking Improve Prompt reads the draft and the latest rendered user question and following assistant answer, validates them and sends them for improvement. Context is limited to 6,000 characters per message; longer text is marked as truncated. If no pair is found, only the draft is sent. Once a preview session exists, the extension compares the draft with the captured original to prevent overwriting edits. Changing chats invalidates the preview.

Refine Further sends the captured original, the latest successful rewrite and the same captured question-and-answer pair, not a growing conversation history. Prompt improvement does not intentionally capture older conversation turns, attachments, account information, passwords or cookies. Markdown export separately reads the saved conversation and image assets when explicitly requested. A prompt can itself contain personal or sensitive information; the extension does not filter such information out before sending it to your server.

## Transmission and processing

The extension's API client sends requests only to `http://127.0.0.1:8080`: model discovery uses `GET /v1/models`; improvement/refinement uses `POST /v1/chat/completions`. Redirects are rejected and requests omit credentials. No draft text is sent to developer-operated servers. There is no analytics, advertising, telemetry, remote executable code or prompt-training collection by the extension.

Opening the toolbar popup automatically checks model availability. Refresh status and the Settings connection test can repeat that check. These checks send no ChatGPT draft, only an HTTP model-discovery request; the returned model name is displayed locally.

You control the local server, model, logs, accessibility, security and any forwarding. HTTP here is loopback transport, not encrypted transport. Bind the server to loopback on the same computer. If you use a proxy, tunnel, modified server, remote backend or plugins, data may leave the device. The extension cannot inspect or guarantee the server's data practices or delete its logs.

## Markdown export

Export chat reads the saved conversation title, source URL and selected message branch only after a trusted click. It requests the current session from ChatGPT, uses its access token in memory to fetch conversation pages and image download locations from ChatGPT's own API, and downloads image bytes from approved ChatGPT image hosts without sending them a bearer token. The token is not persisted or logged. Your browser supplies existing session credentials to same-origin requests. The export is assembled locally as Markdown or a ZIP with an `export-files` image folder, without contacting the AI server or developer services. Failed images are identified in a local report. The download may contain sensitive conversation text and images; it remains in your download location and backups until deleted. No export is saved in extension storage.

## Temporary data and storage

Original prompts, captured question-and-answer context, latest suggestions and pending request data are held in page/service-worker memory for the user-facing editing flow, not written to `chrome.storage`, files or a developer database. Starting a new Improve Prompt sequence replaces the old original and preview. Apply closes the panel; Cancel hides it. Neither is a secure erase: the captured original and preview data can remain in the page's memory until a new sequence, content-script cleanup or page unload. Server-side work/logs may outlive cancellation.

Configuration (fixed API origin, temperature, token limit, timeout and input limit) is saved in `chrome.storage.local`, not Chrome's sync storage. Change it in Settings. Uninstalling the extension removes its extension storage; you must manage server logs and operating-system clipboard data separately. The extension makes no guarantee of secure erasure from browser/OS memory, crash dumps or backups.

## Apply, clipboard and third-party services

Apply edits the ChatGPT draft only after an explicit click and attempts to verify the change; it never clicks Send or automatically submits to ChatGPT. The website can observe text in its editor, including the original draft and applied rewrite, according to its own practices. The extension cannot promise that ChatGPT waits for submission before handling draft text.

Copy writes the chosen text to the system clipboard only when clicked. The extension never reads clipboard contents. Other applications and clipboard history/synchronization services may access or retain copied text.

Setup-guide links open external sites only when followed. GitHub, ChatGPT, Chrome/Chrome Web Store and the user's server/OS have their own privacy practices, outside this extension's control. No third-party scripts, fonts or tracking pixels are embedded in extension pages.

## Limited Use disclosure

Local Prompt Enhancer's use of information received from Chrome APIs adheres to the Chrome Web Store User Data Policy, including the Limited Use requirements. Data accessed by the extension is used only to provide its prominently described prompt-editing, preview, application, copying, Markdown export and local-connection features. The extension does not sell data, use it for advertising or creditworthiness/lending decisions, transfer it to data brokers, or provide developer human access to prompt content.

This statement describes the extension's behavior and commitments; it is not a statement of approval or certification by Google. The user's independently operated server and other software are not controlled by this extension.

## Choices and contact

Do not click Improve Prompt or Refine Further if you do not want that text sent to your server. You may cancel requests, close the tab, disable/uninstall the extension, and manage server logging yourself. Review every model-generated suggestion before applying it.

Before publication, the publisher must replace the contact placeholder above and host this policy at a publicly accessible HTTPS URL, linked from the store listing and project homepage. Privacy questions can then be directed to that contact.
