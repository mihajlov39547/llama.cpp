'use strict';
importScripts('settings.js', 'prompt-template.js', 'llama-api.js');
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
function popupSender(sender) {
  return sender.id === chrome.runtime.id &&
    sender.url === chrome.runtime.getURL('src/popup.html');
}
chrome.runtime.onMessage.addListener((message, sender, respond) => {
  if (!message || !['PE_IMPROVE', 'PE_REFINE', 'PE_CANCEL', 'PE_TEST', 'PE_STATUS'].includes(message.type)) return false;
  const isStatus = message.type === 'PE_STATUS';
  const isTest = message.type === 'PE_TEST' || isStatus;
  if (isStatus ? !popupSender(sender) : message.type === 'PE_TEST' ? !optionsSender(sender) : !chatSender(sender)) {
    respond({ ok: false, error: { code: 'SENDER', message: 'Untrusted request source.' } });
    return false;
  }
  if (typeof message.requestId !== 'string' || !/^[a-zA-Z0-9-]{1,80}$/.test(message.requestId)) {
    respond({ ok: false, error: { code: 'INPUT', message: 'Invalid request ID.' } });
    return false;
  }
  const key = isStatus ? 'popup' : isTest ? 'options' : sender.tab.id;
  if (message.type === 'PE_CANCEL') {
    const request = active.get(key);
    if (request?.id === message.requestId) {
      // Release synchronously: an immediate Retry must not wait for fetch's
      // rejection/finally microtask. Old finally blocks use identity checks.
      active.delete(key);
      request.controller.abort();
    }
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
      request.controller.signal.throwIfAborted();
      const refining = message.type === 'PE_REFINE';
      const result = await API.run(refining ? message.originalPrompt : message.prompt, settings, {
        signal: request.controller.signal, testOnly: isTest,
        mode: refining ? 'refine' : 'improve',
        previousImprovement: refining ? message.previousImprovement : undefined,
        conversationContext: isTest ? undefined : message.conversationContext
      });
      request.controller.signal.throwIfAborted();
      respond({ ok: true, ...result, ...(isTest ? { endpoint: API.settings(settings).baseUrl } : {}) });
    } catch (error) {
      respond({ ok: false, error: request.controller.signal.aborted ?
        { code: 'CANCELLED', message: 'Request cancelled.' } :
        { code: error.code || 'INTERNAL', message: error.message || 'Local request failed.' } });
    } finally {
      if (active.get(key) === request) active.delete(key);
    }
  })();
  return true;
});
chrome.tabs.onRemoved.addListener(tabId => {
  const request = active.get(tabId);
  active.delete(tabId);
  request?.controller.abort();
});
