"use strict";

// USER-origin CSS takes priority over author/inline !important and can be removed
// without rewriting any site's styles. Serialize updates per live document.
const queues = new Map();
chrome.runtime.onMessage.addListener((message, sender, respond) => {
  if (message?.type !== "unblockcp:css" || !sender.tab || !sender.documentId) return;
  const key = sender.documentId;
  const previous = queues.get(key) || Promise.resolve();
  const task = previous.catch(() => {}).then(async () => {
    const { settings = {} } = await chrome.storage.local.get("settings");
    const enabled = settings.mode !== "off" && settings.css !== false;
    const injection = {
      target: { tabId: sender.tab.id, documentIds: [sender.documentId] },
      files: ["content.css"], origin: "USER"
    };
    await chrome.scripting.removeCSS(injection);
    if (enabled) await chrome.scripting.insertCSS(injection);
    return { ok: true, enabled };
  });
  queues.set(key, task);
  task.then(respond, error => respond({ ok: false, error: error.message })).finally(() => {
    if (queues.get(key) === task) queues.delete(key);
  });
  return true;
});
