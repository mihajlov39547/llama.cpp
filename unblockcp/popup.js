"use strict";
const mode = document.querySelector("#mode");
const css = document.querySelector("#css");
const status = document.querySelector("#status");
const list = document.querySelector("#listeners");
let tabId;

async function inspect(action = "report", args = [], frameId) {
  if (tabId === undefined) throw new Error("Nema aktivne stranice.");
  return chrome.scripting.executeScript({
    target: frameId === undefined ? { tabId, allFrames: true } : { tabId, frameIds: [frameId] },
    world: "MAIN",
    func: (method, values) => {
      const api = window.__unblockcpInspector;
      if (!api || !["report", "setDisabled", "restore"].includes(method)) return null;
      return api[method](...values);
    }, args: [action, args]
  });
}

async function refresh() {
  list.replaceChildren();
  const reports = await inspect();
  let count = 0;
  let available = false;
  for (const { frameId, result } of reports) {
    if (!result || !Array.isArray(result.listeners)) continue;
    available = true;
    for (const listener of result.listeners.slice(0, 200)) {
      count++;
      const row = document.createElement("div");
      row.className = "listener";
      const label = document.createElement("p");
      label.textContent = `${listener.type} · ${listener.name} · ${listener.target} · frame ${frameId} · capture: ${Boolean(listener.capture)} · otkazivanja: ${listener.cancelled}`;
      label.title = String(listener.source || "");
      const button = document.createElement("button");
      button.textContent = listener.disabled ? "Vrati listener" : "Isključi za ovu akciju";
      button.addEventListener("click", () => run(async () => {
        const result = await inspect("setDisabled", [listener.id, !listener.disabled], frameId);
        if (!result.some(item => item.result === true)) throw new Error("Listener više nije dostupan. Osveži listu.");
        await refresh();
      }, button));
      row.append(label, button);
      list.append(row);
    }
  }
  if (!available) throw new Error("Osveži stranicu da se učita nova verzija ekstenzije.");
  status.textContent = count ? `Pronađeno listenera: ${count}.` : "Nema zabeleženih otkazivanja. Ponovi akciju u selektivnom režimu.";
}

async function run(action, button) {
  if (button) button.disabled = true;
  try { await action(); }
  catch (error) { status.textContent = `Nije dostupno: ${error.message}`; }
  finally { if (button) button.disabled = false; }
}

async function save() {
  await chrome.storage.local.set({ settings: { mode: mode.value, css: css.checked } });
  status.textContent = "Podešavanja su sačuvana za sve stranice.";
}
mode.addEventListener("change", () => run(save));
css.addEventListener("change", () => run(save));
document.querySelector("#refresh").addEventListener("click", event => run(refresh, event.currentTarget));
document.querySelector("#restore").addEventListener("click", event => run(async () => {
  await inspect("restore");
  await refresh();
}, event.currentTarget));

run(async () => {
  const [{ settings = {} }, tabs] = await Promise.all([
    chrome.storage.local.get("settings"), chrome.tabs.query({ active: true, currentWindow: true })
  ]);
  mode.value = settings.mode || "strong";
  css.checked = settings.css !== false;
  tabId = tabs[0]?.id;
  await refresh();
});
