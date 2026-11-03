import { createScene } from "./scene.js";
import { createPanel, createLine } from "./panel.js";

const TM = window.TM;
const root = document.getElementById("root");
const canvas = document.getElementById("gl");

window.__hf = window.__hf || {};
window.__hf.buildReady = window.__hf.buildReady || {};

const ready = (async () => {
  await document.fonts.ready;
  await Promise.all([...document.fonts].map((f) => f.load().catch(() => null)));
  const scene = await createScene(canvas);
  const panel = createPanel(root);
  const line = createLine(root);
  let last = -1;
  const renderAt = (t) => {
    const time = Math.min(Math.max(t, 0), TM.end - 1e-4);
    if (time === last) return;
    last = time;
    scene.render(time);
    panel(time);
    line(time);
  };
  window.__renderAt = renderAt;
  window.addEventListener("hf-seek", (e) => renderAt(e.detail.time));
  if (window.__hfForceTimelineRebind) window.__hfForceTimelineRebind();
  renderAt(0);
  window.__ready = true;
})();
window.__hf.buildReady.scene = ready;
