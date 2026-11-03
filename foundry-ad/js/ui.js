// DOM + SVG helpers shared by the acts: element builders, brush paint, hand-drawn loops, keycap glyphs.
window.UI = (function () {
  const NS = "http://www.w3.org/2000/svg";
  const { rng } = window.L;

  function el(tag, cls, parent, html) {
    const e = document.createElement(tag);
    if (cls) e.className = cls;
    if (html != null) e.innerHTML = html;
    if (parent) parent.appendChild(e);
    return e;
  }

  function box(e, x, y, w, h) {
    Object.assign(e.style, { left: x + "px", top: y + "px", width: w + "px", height: h + "px" });
    return e;
  }

  function img(src, cls, parent) {
    const i = el("img", cls, parent);
    i.src = src;
    i.alt = "";
    i.decoding = "sync";
    return i;
  }

  function svg(parent, cls) {
    const s = document.createElementNS(NS, "svg");
    s.setAttribute("viewBox", "0 0 1920 1080");
    s.setAttribute("width", "1920");
    s.setAttribute("height", "1080");
    s.setAttribute("class", "paint" + (cls ? " " + cls : ""));
    parent.appendChild(s);
    return s;
  }

  function node(tag, attrs, parent) {
    const n = document.createElementNS(NS, tag);
    for (const k in attrs) n.setAttribute(k, attrs[k]);
    if (parent) parent.appendChild(n);
    return n;
  }

  function stroke(g, d, w, color, opacity, transform) {
    const p = node("path", { d, pathLength: 1, fill: "none", stroke: color, "stroke-width": w, "stroke-linecap": "round",
      "stroke-linejoin": "round", "stroke-dasharray": "1 1", "stroke-dashoffset": 1, opacity }, g);
    if (transform) p.setAttribute("transform", transform);
    return p;
  }

  // A molten brush stroke: a fat core plus a dry-brush echo, both edge-roughened by the #brush turbulence filter.
  function paint(s, d, { w = 15, color = "#FF5A1F" } = {}) {
    const g = node("g", { filter: "url(#brush)", opacity: 0 }, s);
    const core = stroke(g, d, w, color, 1);
    const dry = stroke(g, d, Math.max(2, w * 0.32), color, 0.6, `translate(${(w * 0.3).toFixed(1)} ${(-w * 0.36).toFixed(1)})`);
    return {
      g,
      draw(tl, t, dur, ease = "power2.out") {
        tl.set(g, { opacity: 1 }, t);
        tl.to(core, { attr: { "stroke-dashoffset": 0 }, duration: dur, ease }, t);
        tl.to(dry, { attr: { "stroke-dashoffset": 0 }, duration: dur * 1.08, ease }, t + dur * 0.06);
        return this;
      },
      erase(tl, t, dur, ease = "power2.in") {
        tl.to([core, dry], { attr: { "stroke-dashoffset": -1 }, duration: dur, ease }, t);
        tl.set(g, { opacity: 0 }, t + dur);
        return this;
      },
    };
  }

  // Catmull-Rom through points -> cubic bezier path
  function smoothPath(pts, closed = false) {
    const n = pts.length;
    const P = (i) => (closed ? pts[(i + n) % n] : pts[Math.max(0, Math.min(n - 1, i))]);
    let d = `M${pts[0][0].toFixed(1)} ${pts[0][1].toFixed(1)}`;
    const last = closed ? n : n - 1;
    for (let i = 0; i < last; i++) {
      const p0 = P(i - 1), p1 = P(i), p2 = P(i + 1), p3 = P(i + 2);
      const c1 = [p1[0] + (p2[0] - p0[0]) / 6, p1[1] + (p2[1] - p0[1]) / 6];
      const c2 = [p2[0] - (p3[0] - p1[0]) / 6, p2[1] - (p3[1] - p1[1]) / 6];
      d += ` C${c1[0].toFixed(1)} ${c1[1].toFixed(1)} ${c2[0].toFixed(1)} ${c2[1].toFixed(1)} ${p2[0].toFixed(1)} ${p2[1].toFixed(1)}`;
    }
    return d;
  }

  // Hand-drawn loop: an ellipse that wobbles and overshoots its start, like a marker circling something.
  function loop(cx, cy, rx, ry, { start = -2.2, turns = 1.12, wobble = 0.035, rot = 0, seed = 1, n = 48, drift = 0.06, from = 0, to = 1 } = {}) {
    const R = rng(seed);
    const ph = [R() * 6.28, R() * 6.28];
    const pts = [];
    const cr = Math.cos(rot), sr = Math.sin(rot);
    for (let i = 0; i <= n; i++) {
      const u = from + (to - from) * (i / n);
      const a = start + u * turns * Math.PI * 2;
      const k = 1 + wobble * Math.sin(a * 2 + ph[0]) + wobble * 0.6 * Math.sin(a * 3 + ph[1]) + drift * (u - 0.5);
      const x = Math.cos(a) * rx * k, y = Math.sin(a) * ry * k;
      pts.push([cx + x * cr - y * sr, cy + x * sr + y * cr]);
    }
    return smoothPath(pts);
  }

  // ⌘ and ⌥ as inline SVG (the type families have no glyphs for them)
  function cmdSVG(size, color = "currentColor", sw = 2) {
    const a = 4.4, r = 3.6, c = 12;
    let d = `M${c - a} ${c - a - r}V${c + a + r}M${c + a} ${c - a - r}V${c + a + r}M${c - a - r} ${c - a}H${c + a + r}M${c - a - r} ${c + a}H${c + a + r}`;
    for (const sx of [-1, 1]) for (const sy of [-1, 1]) {
      const ox = c + sx * (a + r), oy = c + sy * (a + r);
      const phi = Math.atan2(-sy, -sx);
      const a0 = phi + Math.PI / 4, a1 = phi + (Math.PI * 7) / 4;
      d += `M${(ox + r * Math.cos(a0)).toFixed(2)} ${(oy + r * Math.sin(a0)).toFixed(2)}A${r} ${r} 0 1 1 ${(ox + r * Math.cos(a1)).toFixed(2)} ${(oy + r * Math.sin(a1)).toFixed(2)}`;
    }
    return `<svg width="${size}" height="${size}" viewBox="0 0 24 24" fill="none" stroke="${color}" stroke-width="${sw}"><path d="${d}"/></svg>`;
  }

  function optSVG(size, color = "currentColor", sw = 2) {
    return `<svg width="${size}" height="${size}" viewBox="0 0 24 24" fill="none" stroke="${color}" stroke-width="${sw}" stroke-linejoin="miter"><path d="M3 7h6l6 10h6M14 7h7"/></svg>`;
  }

  return { NS, el, box, img, svg, node, paint, loop, smoothPath, cmdSVG, optSVG };
})();
