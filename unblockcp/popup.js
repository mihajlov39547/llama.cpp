"use strict";
const enabled = document.querySelector("#enabled");
const css = document.querySelector("#css");
const state = document.querySelector("#state");
const status = document.querySelector("#status");
let saved = { mode: "strong", css: true };
document.querySelector("#version").textContent = "Version " + chrome.runtime.getManifest().version;
function render() {
  enabled.checked = saved.mode !== "off";
  enabled.disabled = false;
  css.checked = saved.css;
  css.disabled = !enabled.checked;
  document.body.dataset.enabled = String(enabled.checked);
  state.textContent = enabled.checked ? "Enabled on all sites" : "Paused";
}
function error(message) { status.textContent = message; status.hidden = false; }
chrome.storage.local.get("settings").then(({ settings = {} }) => {
  saved = { ...settings, mode: ["strong", "selective", "off"].includes(settings.mode) ? settings.mode : "strong", css: settings.css !== false };
  render();
}).catch(() => { state.textContent = "Unavailable"; error("Unable to load settings. Please reopen the popup."); });
async function save(event) {
  const next = { ...saved, css: css.checked };
  if (event.currentTarget === enabled) next.mode = enabled.checked ? "strong" : "off";
  enabled.disabled = true;
  css.disabled = true;
  status.hidden = true;
  try { await chrome.storage.local.set({ settings: next }); saved = next; }
  catch { error("Unable to save. Please try again."); }
  render();
}
enabled.addEventListener("change", save);
css.addEventListener("change", save);
