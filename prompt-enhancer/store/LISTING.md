# Store listing draft — Local Prompt Enhancer

## Product name

Local Prompt Enhancer

## Short description

Improve your prompts with local AI.

## Full description

Improve and refine ChatGPT drafts with a llama.cpp model running on your computer.

Local Prompt Enhancer adds an Improve Prompt control near ChatGPT's composer. Click it to send your draft to your independently running local server and review a proposed rewrite before changing your draft.

Features:

- Improve clarity, grammar and organization with your chosen compatible local model.
- Refine Further uses the original prompt and only the latest successful rewrite, without accumulating a conversation history.
- Review suggestions, copy them, or apply a verified replacement to the current draft.
- Preserve the original text in a temporary recovery view and protect drafts that change while a request runs.
- Check model availability from the toolbar popup and open the included setup guide.
- Configure temperature, output limit, timeout and input length.

Apply never automatically submits the prompt to ChatGPT. Model output can be wrong; review each suggestion. If editor replacement cannot be verified, use Copy and paste manually.

Requirements: a current desktop Chrome installation, access to https://chatgpt.com/, a separately installed llama.cpp server and a compatible GGUF model supported by your hardware. The server must listen on http://127.0.0.1:8080 and support /v1/models and /v1/chat/completions. Models are not included or automatically downloaded. This release targets ChatGPT's supported composer, not every website, model or editor.

Setup: obtain llama.cpp and a compatible model; start llama-server bound to 127.0.0.1 on port 8080; use Refresh status in the popup; open or refresh ChatGPT; type a draft and click Improve Prompt. Use Refine Further for another pass, or Apply/Copy after review. Detailed Windows, macOS and Linux examples are in Open Setup Guide.

Privacy: prompt text is extracted after your Improve Prompt action and sent only to the loopback server. Refine Further also sends the latest rewrite. The popup checks models without reading drafts. The extension sends no prompts to developer-operated servers, includes no advertising/analytics trackers and does not persist prompts in extension storage. Settings are saved locally; preview/recovery data remains temporarily in memory. Copy writes to your system clipboard.

You control the server's logging, security and any forwarding. ChatGPT and clipboard services can handle text according to their own policies; this is not a guarantee that all data stays on your device. See the privacy policy for details.

This is an independent extension, not affiliated with or endorsed by ChatGPT, OpenAI, Google or the llama.cpp project.

## Single-purpose justification

Help users improve and refine the text of their ChatGPT drafts through a user-operated local llama.cpp server, with user-controlled preview, application and copying. Status, configuration and setup are supporting features of that single purpose.

## Dashboard permission explanations

- **storage:** save local extension configuration; never persist prompts or rewrites.
- **clipboardWrite:** write a suggestion or recovery original only on Copy; provide the fallback when native editor replacement fails. No clipboard reading. Complete the comparison test in docs/PERMISSIONS.md before submission.
- **Localhost host access:** discover the locally loaded model and send explicitly requested improvement/refinement calls to the fixed loopback endpoint.
- **ChatGPT site access:** display composer controls, read the draft after user action, detect conflicting edits and apply an explicitly selected rewrite.
- **Remote code:** no remote executable code. The local model returns data rendered as text.

## URLs and publisher fields — replace before submission

- Support URL: **[HTTPS_SUPPORT_URL]**
- Privacy policy URL: **[HTTPS_PUBLIC_PRIVACY_POLICY_URL]**
- Project homepage: **[HTTPS_PROJECT_HOMEPAGE]**
- Publisher display name/contact: **[PUBLISHER_DETAILS]**

Do not publish with these placeholders. Host PRIVACY_POLICY.md as a readable public page, linked from the project homepage.

## Reviewer instructions

Use the included setup guide. A separately installed local llama.cpp server with a loaded, compatible GGUF is required; there is no bundled cloud fallback. Start it on 127.0.0.1:8080. The popup's Connected state confirms model discovery only. On ChatGPT, use a harmless synthetic prompt; test Improve Prompt, Refine Further, Apply without submission, Copy and Cancel. No extension account is required; ChatGPT may require sign-in. Include the actual model/build and platform used for the publisher's acceptance test when filling the reviewer instructions field; none are fabricated here.
