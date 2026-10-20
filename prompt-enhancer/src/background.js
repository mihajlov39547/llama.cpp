'use strict';
importScripts('prompt-template.js', 'llama-api.js');
const active = new Map();
const API = globalThis.PromptEnhancerAPI;
chrome.runtime.onInstalled.addListener(async () => {
  const { settings } = await chrome.storage.local.get('settings');
  if (!settings) await chrome.storage.local.set({ settings: API.defaults });
});

function chatSender(sender) {
  try {
    return sender.id === chrome.runtime.id && Number.isInteger(sender.tab?.id) &&
      sender.frameId === 0 && new URL(sender.url).origin === 'https://chatgpt.com' &&
      new URL(sender.tab.url).origin === 'https://chatgpt.com';
  } catch { return false; }
}
function optionsSender(sender) {
  return sender.id === chrome.runtime.id &&
    sender.url === chrome.runtime.getURL('src/options.html');
}
chrome.runtime.onMessage.addListener((message, sender, respond) => {
  if (!message || !['PE_IMPROVE', 'PE_CANCEL', 'PE_TEST'].includes(message.type)) return false;
  const isTest = message.type === 'PE_TEST';
  if (isTest ? !optionsSender(sender) : !chatSender(sender)) {
    respond({ ok: false, error: { code: 'SENDER', message: 'Untrusted request source.' } });
    return false;
  }
  if (typeof message.requestId !== 'string' || !/^[a-zA-Z0-9-]{1,80}$/.test(message.requestId)) {
    respond({ ok: false, error: { code: 'INPUT', message: 'Invalid request ID.' } });
    return false;
  }
  const key = isTest ? 'options' : sender.tab.id;
  if (message.type === 'PE_CANCEL') {
    const request = active.get(key);
    if (request?.id === message.requestId) request.controller.abort();
    respond({ ok: true });
    return false;
  }
  if (active.has(key)) {
    respond({ ok: false, error: { code: 'BUSY', message: 'A local request is still running. Try again shortly.' } });
    return false;
  }
  const request = { id: message.requestId, controller: new AbortController() };
  active.set(key, request);
  (async () => {
    try {
      const { settings } = await chrome.storage.local.get('settings');
      const result = await API.run(message.prompt, settings, {
        signal: request.controller.signal, testOnly: isTest
      });
      respond({ ok: true, ...result });
    } catch (error) {
      respond({ ok: false, error: { code: error.code || 'INTERNAL', message: error.message || 'Local request failed.' } });
    } finally {
      if (active.get(key) === request) active.delete(key);
    }
  })();
  return true;
});
chrome.tabs.onRemoved.addListener(tabId => {
  active.get(tabId)?.controller.abort();
});
