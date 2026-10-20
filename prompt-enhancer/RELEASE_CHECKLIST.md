# Release checklist — 0.2.0

Prepared locally; **not submitted to the Chrome Web Store**.

## Automated/package checks

- [ ] Run `node --test tests/*.test.cjs`; record the exact passing count and zero failures.
- [ ] Run `node scripts/build-release.cjs`, then `node scripts/build-release.cjs --check`.
- [ ] Confirm ZIP: `release/local-prompt-enhancer-0.2.0.zip`, manifest at archive root, all runtime references resolve.
- [ ] Confirm version 0.2.0, four PNG icon sizes, popup, setup, worker and ChatGPT content scripts.
- [ ] Confirm allowlist excludes tests, documentation, source artwork/export tools, logs, secrets, models and prior archives.

## Real Chrome acceptance — not completed by automated DOM tests

- [ ] Extract ZIP to a clean test folder; Load unpacked at `chrome://extensions`. Confirm no manifest or worker errors.
- [ ] Open toolbar popup: verify name/icon/version, Checking → Connected with a real loaded model, model name and endpoint. Stop the server: Refresh must show Disconnected. Confirm the popup never reads or sends draft text (network shows model discovery only).
- [ ] Open Settings and Setup Guide from popup; follow the guide on supported platforms. Verify links and readability.
- [ ] On ChatGPT, before any Improve click, verify no draft serialization/API request. Click Improve on empty input: show an error, no API request. The button is intentionally not disabled based on pre-click text inspection.
- [ ] Improve a multiline synthetic prompt; verify local disclosure, original recovery and response preview.
- [ ] Refine twice: fixed original/latest-only context, temperature increment, no saved-setting mutation. Test failed refinement preserves preview.
- [ ] Apply, native undo, Copy, Copy original, Cancel, changed-draft protection, chat navigation and interrupted-worker recovery. Confirm no automatic send or request replay.
- [ ] Verify normal composer keyboard/Send/attachment behavior, light/dark mode, narrow and wide viewports, no control overlap.
- [ ] Perform the `clipboardWrite` removal comparison in docs/PERMISSIONS.md; retain only if needed for supported behavior. Rebuild/retest after any change.
- [ ] See README.md for the longer existing editor/refinement checklist.

## Privacy, account and listing

- [ ] Review docs/POLICY_REVIEW.md and current official policies; source review is not Google approval.
- [ ] Fill publisher/contact and URL placeholders. Host the final privacy policy at a public HTTPS URL, link it from the project homepage and supply it in the dashboard.
- [ ] Complete accurate privacy-practices disclosures: locally handled website/prompt content still counts as data handling. Match dashboard declarations, privacy policy, UI and listing.
- [ ] Include the Limited Use disclosure; confirm no ads, analytics, sales, remote executable code or developer prompt collection.
- [ ] Register/verify the publisher account, pay applicable registration fee, complete required contact verification and enable 2-Step Verification. [Developer registration](https://developer.chrome.com/docs/webstore/register).
- [ ] Finalize store/LISTING.md; disclose local server/model requirement and ChatGPT-only scope. Provide usable support and privacy URLs.
- [ ] Capture actual 1280×800 screenshots per store/SCREENSHOTS.md; prepare the required promo tile and icon. No fabricated screenshots.
- [ ] Provide reviewer setup instructions with the exact model/server/platform actually tested; no bundled model or extension account.

## Submission and approval — publisher action required

- [ ] Review ZIP hash and contents, licensing/branding and all outstanding browser checks.
- [ ] Manually upload the validated ZIP in the developer dashboard. Complete listing, privacy, distribution and test-instructions fields.
- [ ] Publisher explicitly reviews and submits for Google review; choose publication timing deliberately.
- [ ] Address review feedback, await approval and verify the published version after release. Do not claim approval before it is granted.

Official workflow: [Publish in the Chrome Web Store](https://developer.chrome.com/docs/webstore/publish). No upload, registration, payment or submission was performed by this preparation.
