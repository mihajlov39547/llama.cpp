'use strict';
const popupStatus = document.getElementById('status');
const popupModel = document.getElementById('model');
const popupDetail = document.getElementById('detail');
const refreshButton = document.getElementById('refresh');
const popupSettings = globalThis.PromptEnhancerSettings;
document.getElementById('version').textContent = `Version ${chrome.runtime.getManifest().version}`;
document.getElementById('endpoint').textContent = popupSettings.defaults.baseUrl;
let checking = false;
async function refreshStatus() {
  if (checking) return;
  checking = true;
  refreshButton.disabled = true;
  popupStatus.textContent = 'Checking…';
  popupStatus.dataset.state = 'checking';
  popupModel.hidden = true;
  popupModel.textContent = '';
  popupDetail.textContent = 'Checking model availability; no prompt text is sent.';
  let timer;
  try {
    const result = await Promise.race([
      chrome.runtime.sendMessage({ type: 'PE_STATUS', requestId: crypto.randomUUID() }),
      new Promise((_, reject) => {
        timer = setTimeout(() => reject(new Error('Status check timed out. Click Refresh status to try again.')), popupSettings.responseTimeoutMs);
      })
    ]);
    if (!result?.ok || typeof result.model !== 'string' || !result.model.trim()) {
      throw new Error(result?.error?.message || 'No model is available.');
    }
    popupStatus.textContent = 'Connected';
    popupStatus.dataset.state = 'connected';
    popupModel.textContent = result.model;
    popupModel.hidden = false;
    popupDetail.textContent = 'The server reports a model. Inference has not been tested.';
    document.getElementById('endpoint').textContent = result.endpoint || popupSettings.defaults.baseUrl;
  } catch (error) {
    popupStatus.textContent = 'Disconnected';
    popupStatus.dataset.state = 'disconnected';
    popupDetail.textContent = error.message || 'Could not check the local server.';
  } finally {
    clearTimeout(timer);
    checking = false;
    refreshButton.disabled = false;
  }
}
refreshButton.addEventListener('click', refreshStatus);
document.getElementById('settings').addEventListener('click', async () => {
  try { await chrome.runtime.openOptionsPage(); }
  catch { popupDetail.textContent = 'Could not open Settings. Use the extension Details page in chrome://extensions.'; }
});
refreshStatus();
