(() => {
  const { normalize } = globalThis.BetterFacebook;
  const enabled = document.getElementById("enabled");
  const state = document.getElementById("state");
  const status = document.getElementById("status");
  let saved = normalize();
  document.getElementById("version").textContent = "Version " + chrome.runtime.getManifest().version;
  function render() {
    enabled.checked = saved.enabled;
    enabled.disabled = false;
    document.body.dataset.enabled = String(saved.enabled);
    state.textContent = saved.enabled ? "Enabled" : "Paused";
  }
  function showError(message) { status.textContent = message; status.hidden = false; }
  chrome.storage.local.get("betterFacebook").then(result => {
    saved = normalize(result.betterFacebook);
    render();
  }).catch(() => {
    state.textContent = "Unavailable";
    showError("Unable to load settings. Please reopen the popup.");
  });
  enabled.addEventListener("change", async () => {
    const next = { ...saved, enabled: enabled.checked };
    enabled.disabled = true;
    status.hidden = true;
    try {
      await chrome.storage.local.set({ betterFacebook: next });
      saved = next;
    } catch { showError("Unable to save. Please try again."); }
    render();
  });
})();
