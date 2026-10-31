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
  if (['PE_REPORT_FRAME_RESULT', 'PE_REPORT_FRAMES'].includes(message?.type)) return handleReportMessage(message, sender, respond);
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


// Reports live in cross-origin frames. Packaged content scripts read them in
// their own isolated worlds; only the current tab's explicit export receives data.
const reportRequests = new Map();
function reportFrameSender(sender) {
  try {
    const url = new URL(sender.url);
    return sender.id === chrome.runtime.id && Number.isInteger(sender.tab?.id) && sender.frameId > 0 &&
      new URL(sender.tab.url).origin === 'https://chatgpt.com' && url.protocol === 'https:' &&
      ((url.hostname === 'cdn.platform.openai.com' && url.pathname.startsWith('/deployments/dil/')) ||
       url.hostname.endsWith('.web-sandbox.oaiusercontent.com'));
  } catch { return false; }
}
function handleReportMessage(message, sender, respond) {
  if (message?.type === 'PE_REPORT_FRAME_RESULT') {
    const pending = reportRequests.get(sender.tab?.id);
    if (!reportFrameSender(sender) || !pending || pending.id !== message.requestId) return false;
    const reports = Array.isArray(message.reports) ? message.reports : [];
    if (reports.length > 30 || reports.some(r => typeof r?.title !== 'string' || typeof r.markdown !== 'string' ||
        typeof r.html !== 'string' || r.markdown.length + r.html.length > 8000000)) return false;
    pending.results.set(sender.frameId, { reports, frameId: sender.frameId });
    return false;
  }
  if (message?.type !== 'PE_REPORT_FRAMES') return false;
  if (!chatSender(sender) || typeof message.requestId !== 'string' || !/^[a-zA-Z0-9-]{1,80}$/.test(message.requestId)) {
    respond({ ok: false, error: 'Invalid report export request.' }); return false;
  }
  if (reportRequests.has(sender.tab.id)) {
    respond({ ok: false, error: 'Report collection already running.' }); return false;
  }
  const pending = { id: message.requestId, results: new Map() };
  reportRequests.set(sender.tab.id, pending);
  // Broadcast reaches the packaged listeners in permitted frames. Frames reply
  // separately, so one empty frame cannot hide another frame's report.
  chrome.tabs.sendMessage(sender.tab.id, { type: 'PE_REPORT_FRAME_COLLECT', requestId: pending.id }).catch(() => {});
  setTimeout(() => {
    if (reportRequests.get(sender.tab.id) !== pending) return;
    reportRequests.delete(sender.tab.id);
    respond({ ok: true, frames: [...pending.results.values()] });
  }, 1500);
  return true;
}
