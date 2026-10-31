(() => {
  'use strict';
  // No DOM reads until the extension worker requests an explicit export.
  if (window === window.top) return;
  chrome.runtime.onMessage.addListener((message, sender) => {
    if (sender.id !== chrome.runtime.id || message?.type !== 'PE_REPORT_FRAME_COLLECT' ||
        typeof message.requestId !== 'string') return false;
    const diagnostics = {};
    const reports = globalThis.PromptEnhancerExport.reports(document, diagnostics);
    chrome.runtime.sendMessage({ type: 'PE_REPORT_FRAME_RESULT', requestId: message.requestId,
      reports, diagnostics }).catch(() => {});
    return false;
  });
})();
