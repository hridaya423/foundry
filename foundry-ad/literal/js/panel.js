import { prog, clamp, hash, outCubic } from "./ease.js";

const TM = window.TM;

const ICONS = {
  wand: '<path d="M4 20 15 9" /><path d="m14 6 1-3 1 3 3 1-3 1-1 3-1-3-3-1z" /><path d="M19 13v2M18 14h2M8 4v2M7 5h2" />',
  equals: '<rect x="4" y="3" width="16" height="18" rx="2.5" /><path d="M8 7h8M8 12h2M14 12h2M8 16h2M14 16h2" />',
  translate: '<path d="M4 5h9M8.5 3v2M6 5c.6 3 2.6 5.6 5.5 7" /><path d="M11 5c-.8 3.6-3.2 6.6-7 8.4" /><path d="m12 21 4.5-10 4.5 10M13.6 17.5h5.8" />',
  qr: '<rect x="3.5" y="3.5" width="6.5" height="6.5" rx="1" /><rect x="14" y="3.5" width="6.5" height="6.5" rx="1" /><rect x="3.5" y="14" width="6.5" height="6.5" rx="1" /><path d="M14 14h2.5v2.5H14zM18 18h2.5v2.5H18zM14 18.5h1.5M18.5 14h2" />',
  scan: '<path d="M4 8V5.5A1.5 1.5 0 0 1 5.5 4H8M16 4h2.5A1.5 1.5 0 0 1 20 5.5V8M20 16v2.5a1.5 1.5 0 0 1-1.5 1.5H16M8 20H5.5A1.5 1.5 0 0 1 4 18.5V16" /><path d="M8 12h8" />',
  party: '<path d="m4 20 4.5-12 7.5 7.5z" /><path d="M14 4c.5 1.5 0 3-1.5 4M20 10c-1.5-.5-3 0-4 1.5M16 3.5v.01M20.5 6v.01M20 14.5v.01" />',
  search: '<circle cx="11" cy="11" r="6.5" /><path d="m16 16 4.5 4.5" />',
};

const ROWS = {
  remove: [{ icon: "wand", title: "Remove Background", sub: "File Shelf", acc: "Command" }],
  calc: [{ icon: "equals", title: "432", sub: "24 × 18", acc: "Calculator" }],
  translate: [{ icon: "translate", title: "こんにちは", sub: "Apple Translation • Translate to Japanese", acc: "Translate", jp: true }],
  qr: [
    { icon: "qr", title: "Generate QR Code", sub: "Encode the clipboard text as a QR code image", acc: "Command" },
    { icon: "scan", title: "Read QR Code", sub: "Decode a QR code or barcode from an image", acc: "Command" },
  ],
  confetti: [{ icon: "party", title: "Make Confetti", sub: "Celebrate something", acc: "Command" }],
};

const NAMES = ["remove", "calc", "translate", "qr", "confetti"];

export function typingPlan(cmd, salt) {
  const start = cmd.summon + 0.2;
  const finish = cmd.enter - (cmd === TM.confetti ? 0.62 : 0.32);
  const n = cmd.query.length;
  const weights = [];
  for (let k = 0; k < n; k++) {
    const ch = cmd.query[k];
    weights.push((ch === " " ? 1.35 : 1) * (0.75 + 0.5 * hash(k + salt * 31, 70)));
  }
  const total = weights.reduce((a, b) => a + b, 0);
  const times = [];
  let acc = 0;
  for (let k = 0; k < n; k++) {
    times.push(start + (acc / total) * (finish - start));
    acc += weights[k];
  }
  return times;
}

export const PLANS = TM.commands.map((c, i) => typingPlan(c, i));

const svg = (name, cls = "") => `<svg class="${cls}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round">${ICONS[name]}</svg>`;

export function createPanel(root) {
  const el = document.createElement("div");
  el.id = "panel";
  el.innerHTML = `
    <div class="search">${svg("search", "glass")}<span class="query"></span><i class="caret"></i><span class="placeholder">Search for apps and commands…</span></div>
    <div class="rule"></div>
    <div class="rows"></div>`;
  root.appendChild(el);
  const query = el.querySelector(".query");
  const caret = el.querySelector(".caret");
  const placeholder = el.querySelector(".placeholder");
  const rowsEl = el.querySelector(".rows");
  let shown = "";

  function rowsFor(name, text, full) {
    if (name === "calc") {
      const m = text.match(/^(\d+)\*(\d+)$/);
      return m ? [{ ...ROWS.calc[0], title: String(m[1] * m[2]), sub: `${m[1]} × ${m[2]}` }] : null;
    }
    if (name === "translate") return full ? ROWS.translate : null;
    return ROWS[name];
  }

  function setRows(name, rows, pressed) {
    const key = name + rows[0].title + (pressed ? ":p" : "");
    if (shown === key) return;
    shown = key;
    rowsEl.innerHTML = rows
      .map((r, i) => `<div class="row${i === 0 ? " sel" : ""}${i === 0 && pressed ? " pressed" : ""}">
        <span class="icon">${svg(r.icon)}</span>
        <span class="title${r.jp ? " jp" : ""}">${r.title}</span>
        <span class="sub">${r.sub}</span>
        <span class="acc">${r.acc}</span>
        ${i === 0 ? '<span class="kbd">↵</span>' : ""}
      </div>`)
      .join("");
  }

  return function update(t) {
    let active = -1;
    TM.commands.forEach((c, i) => {
      if (t >= c.summon && t < c.enter + 0.12) active = i;
    });
    if (active < 0) {
      el.style.opacity = "0";
      el.style.visibility = "hidden";
      return;
    }
    const c = TM.commands[active];
    const name = NAMES[active];
    const fadeIn = clamp((t - c.summon) / 0.18);
    const fadeOut = 1 - clamp((t - c.enter - 0.04) / 0.08);
    el.style.visibility = "visible";
    el.style.opacity = String(outCubic(fadeIn) * fadeOut);
    const plan = PLANS[active];
    const typed = plan.filter((x) => t >= x).length;
    const text = c.query.slice(0, typed);
    query.textContent = text;
    placeholder.style.display = typed ? "none" : "block";
    const lastKey = typed ? plan[typed - 1] : c.summon;
    const blinkOn = t - lastKey < 0.5 || Math.floor((t - lastKey - 0.5) / 0.5) % 2 === 1;
    caret.style.opacity = blinkOn ? "1" : "0";
    const rows = rowsFor(name, text, typed === c.query.length);
    const showRows = !!rows && typed >= Math.min(c.query.length, Math.max(2, Math.ceil(c.query.length * 0.45)));
    rowsEl.style.opacity = showRows ? "1" : "0";
    el.classList.toggle("open", showRows);
    if (rows) setRows(name, rows, t >= c.enter - 0.07);
  };
}

export function createLine(root) {
  const el = document.createElement("div");
  el.id = "line";
  el.innerHTML = '<span class="a">⌘ Space,</span> <span class="b">then anything<span class="dot">.</span></span>';
  root.appendChild(el);
  const a = el.querySelector(".a"), b = el.querySelector(".b");
  return function update(t) {
    const show = t >= TM.line && t < TM.loop[0] + 0.35;
    el.style.visibility = show ? "visible" : "hidden";
    if (!show) return;
    const out = 1 - clamp((t - TM.loop[0]) / 0.3);
    a.style.opacity = String(clamp((t - TM.line) / 0.12) * out);
    b.style.opacity = String(clamp((t - TM.line - TM.B) / 0.12) * out);
  };
}
