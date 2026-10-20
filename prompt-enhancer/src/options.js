'use strict';
const statusNode = document.getElementById('status');
const fields = ['baseUrl', 'temperature', 'maxTokens', 'maxInputLength'];
const Settings = globalThis.PromptEnhancerSettings;
for (const [key, limit] of Object.entries(Settings.limits)) {
  const field = document.getElementById(key === 'timeoutMs' ? 'timeout' : key);
  const scale = key === 'timeoutMs' ? 1000 : 1;
  field.min = limit.min / scale;
  field.max = limit.max / scale;
  field.step = limit.step || 1;
}
async function load() {
  try {
    const { settings } = await chrome.storage.local.get('settings');
    const config = Settings.settings(settings);
    for (const field of fields) document.getElementById(field).value = config[field];
    document.getElementById('timeout').value = config.timeoutMs / 1000;
  } catch (error) { statusNode.textContent = error.message; }
}
document.getElementById('settings').addEventListener('submit', async event => {
  event.preventDefault();
  try {
    const config = { baseUrl: document.getElementById('baseUrl').value };
    for (const field of fields.slice(1)) config[field] = Number(document.getElementById(field).value);
    config.timeoutMs = Number(document.getElementById('timeout').value) * 1000;
    await chrome.storage.local.set({ settings: Settings.settings(config) });
    statusNode.textContent = 'Settings saved.';
  } catch (error) { statusNode.textContent = error.message; }
});
document.getElementById('test').addEventListener('click', async event => {
  const button = event.currentTarget;
  button.disabled = true;
  statusNode.textContent = 'Checking model availability…';
  let timer;
  try {
    const response = await Promise.race([
      chrome.runtime.sendMessage({ type: 'PE_TEST', requestId: crypto.randomUUID() }),
      new Promise((_, reject) => { timer = setTimeout(() => reject(new Error('Background request timed out. Retry.')), Settings.responseTimeoutMs); })
    ]);
    if (!response?.ok) throw new Error(response?.error?.message || 'Background worker stopped. Retry.');
    statusNode.textContent = `Connected. Model: ${response.model}`;
  } catch (error) { statusNode.textContent = error.message; }
  finally { clearTimeout(timer); button.disabled = false; }
});
load();
