(() => {
  const { normalize } = globalThis.BetterFacebook;
  const enabled = document.getElementById("enabled");
  const focus = document.getElementById("focus");
  const textSize = document.getElementById("textSize");
  const preferences = document.getElementById("preferences");
  const status = document.getElementById("status");
  let saved = normalize();

  function render(settings) {
    enabled.checked = settings.enabled;
    focus.checked = settings.focus;
    textSize.value = settings.textSize;
    enabled.disabled = false;
    preferences.disabled = !settings.enabled;
  }

  chrome.storage.local.get("betterFacebook").then((result) => {
    saved = normalize(result.betterFacebook);
    render(saved);
    status.textContent = "Ready. Changes apply to open Facebook tabs.";
  }).catch(() => {
    status.textContent = "Could not load settings. Reopen this popup to retry.";
  });

  for (const control of [enabled, focus, textSize]) {
    control.addEventListener("change", async () => {
      const next = normalize({ enabled: enabled.checked, focus: focus.checked, textSize: textSize.value });
      enabled.disabled = true;
      preferences.disabled = true;
      try {
        await chrome.storage.local.set({ betterFacebook: next });
        saved = next;
        status.textContent = next.enabled ? "Saved. Your feed is ready." : "Disabled. Facebook’s original styling is restored.";
      } catch {
        status.textContent = "Could not save. Please try again.";
      }
      render(saved);
    });
  }
})();
