"use strict";
function blockCopy(event) { event.preventDefault(); }
function blockCut(event) { event.preventDefault(); }
function blockPaste(event) { event.preventDefault(); }
function blockContextMenu(event) { event.preventDefault(); }
function blockSelection(event) { event.preventDefault(); }
function blockDrag(event) { event.preventDefault(); }
document.addEventListener("copy", blockCopy);
document.addEventListener("cut", blockCut);
document.querySelector("#pasteTarget").addEventListener("paste", blockPaste);
document.addEventListener("contextmenu", blockContextMenu);
document.querySelector("#sample").addEventListener("selectstart", blockSelection);
document.querySelector("#sample").addEventListener("dragstart", blockDrag);
let otherKeys = 0;
function blockShortcuts(event) {
  if ((event.ctrlKey || event.metaKey) && ["c", "v", "x", "a"].includes(event.key.toLowerCase())) event.preventDefault();
  else if (event.type === "keydown") document.querySelector("#counter").textContent = `Ostali tasteri: ${++otherKeys}`;
}
document.querySelector("#keys").addEventListener("keydown", blockShortcuts);
document.querySelector("#keys").addEventListener("keyup", blockShortcuts);
document.querySelector("#remove").addEventListener("click", () => {
  document.removeEventListener("copy", blockCopy);
  document.querySelector("#removed").textContent = "blockCopy je uklonjen originalnom referencom.";
});
function addShadow(host) {
  const root = host.attachShadow({ mode: "open" });
  root.innerHTML = '<style>* { user-select: none !important; }</style><p>Shadow DOM tekst za selekciju.</p><input aria-label="Shadow input" value="Shadow input">';
}
addShadow(document.querySelector("#shadow"));
document.querySelector("#dynamic").addEventListener("click", () => {
  const host = document.createElement("div");
  document.body.append(host);
  addShadow(host);
});
