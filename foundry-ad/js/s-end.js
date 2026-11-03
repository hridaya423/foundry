// End: the last dot is the tittle of "find". It pops off, the i drains back into the mould, n and d make room and
// o, u are cast up into "found"; r, y follow and the tittle lands as the period: "foundry." Then ⌥ Space.
// Letters are the Foundry wordmark's own glyphs (tile polygons); the i is a stem of the same weight.
window.SC = window.SC || {};
window.SC.end = (function () {
  const { prog, ease, PLAN, lerp, clamp, cut } = window.L;
  const { el, node } = window.UI;
  const E0 = PLAN.end, BT = PLAN.beat;
  const POP = cut(E0 + 1.5 * BT), RY = cut(E0 + 2.5 * BT), LAND = cut(E0 + 3 * BT), KEYS = cut(E0 + 5 * BT), PRESS = cut(E0 + 6 * BT);
  const S = 0.718;                                                     // wordmark units -> px
  const GY = 500 - 252 * S;
  const STEM = { x0: 246, x1: 318, y0: 183, y1: 411 };
  const TIT = { x: 282, y: 128, r: 36 };
  const PER = { x: 1608, y: 375 };
  const SHIFT = 728.2 - 347;                                          // n, d: from "find" to their wordmark place
  const centre = { find: (61.2 + 1189.8 - SHIFT) / 2, found: (61.2 + 1189.8) / 2, final: (61.2 + PER.x + TIT.r) / 2 };
  const gx = (c) => 960 - c * S;
  const groupX = (t) => {
    const a = ease.inOutCubic(prog(t, POP + 0.04, POP + 0.34));
    const b = ease.inOutCubic(prog(t, RY - 0.06, LAND + 0.04));
    return gx(lerp(lerp(centre.find, centre.found, a), centre.final, b));
  };
  const tittle = { x: gx(centre.find) + TIT.x * S, y: GY + TIT.y * S, r: TIT.r * S };

  // heat 1 (molten) .. 0 (bone): bone -> molten -> peach as heat rises
  const BONE = [244, 244, 242], MOLT = [255, 90, 31], PEACH = [255, 217, 174];
  const heatRGB = (h) => {
    const c = h < 0.6 ? BONE.map((v, i) => lerp(v, MOLT[i], h / 0.6)) : MOLT.map((v, i) => lerp(v, PEACH[i], (h - 0.6) / 0.4));
    return `rgb(${c.map((v) => Math.round(v)).join(",")})`;
  };
  const cool = (t, t0, k = 0.24) => (t >= t0 ? Math.exp(-(t - t0) / k) : 0);

  function letterPath(l) {
    let d = "";
    const b = { x0: 1e9, y0: 1e9, x1: -1e9, y1: -1e9 };
    for (const tile of window.FD.wordmark.tiles) {
      if (tile.l !== l) continue;
      for (const poly of tile.p) {
        d += "M" + poly.map(([x, y]) => `${x} ${y}`).join("L") + "Z";
        for (const [x, y] of poly) { b.x0 = Math.min(b.x0, x); b.y0 = Math.min(b.y0, y); b.x1 = Math.max(b.x1, x); b.y1 = Math.max(b.y1, y); }
      }
    }
    return { d, b };
  }

  function build(tl) {
    const root = document.getElementById("s-end");
    tl.set(root, { visibility: "visible" }, E0);
    const s = document.createElementNS(window.UI.NS, "svg");
    s.setAttribute("viewBox", "0 0 1920 1080");
    Object.assign(s.style, { position: "absolute", left: 0, top: 0, width: "1920px", height: "1080px", overflow: "visible" });
    root.appendChild(s);
    const defs = node("defs", {}, s);
    const grad = node("radialGradient", { id: "molt" }, defs);
    for (const [o, c] of [[0, "#fff6ea"], [0.26, "#ffd9ae"], [0.52, "#ff7a3d"], [0.7, "#ff5a1f"], [1, "#ff5a1f"]]) node("stop", { offset: o, "stop-color": c }, grad);
    const push = node("g", {}, s);
    const g = node("g", {}, push);

    // cast letters: each rises out of its own mould (clip at the glyph's foot)
    const L = {};
    const mk = (id, l, rise) => {
      const { d, b } = letterPath(l);
      const cp = node("clipPath", { id: "m-" + id }, defs);
      node("rect", { x: b.x0 - 20, y: -2000, width: b.x1 - b.x0 + 40, height: 2000 + b.y1 + 0.5 }, cp);
      const wrap = node("g", { "clip-path": `url(#m-${id})` }, g);
      const p = node("path", { d, "stroke-width": 0.9, "stroke-linejoin": "round" }, wrap);
      L[id] = { wrap, cp, p, b, rise, h: b.y1 - b.y0 + 10 };
    };
    mk("f", "f", E0);
    mk("n", "n", E0 + 0.07);
    mk("d", "d", E0 + 0.105);
    mk("o", "o", POP + 0.18);
    mk("u", "u", POP + 0.3);
    mk("r", "r", RY);
    mk("y", "y", RY + 0.07);
    const iw = node("g", {}, g);
    const stem = node("rect", { x: STEM.x0, y: STEM.y0, width: STEM.x1 - STEM.x0, height: STEM.y1 - STEM.y0 }, iw);
    const tit = node("circle", { cx: TIT.x, cy: TIT.y, r: TIT.r, fill: "url(#molt)" }, g);
    tit.style.filter = "drop-shadow(0 0 10px rgba(255,90,31,0.6)) drop-shadow(0 0 32px rgba(255,90,31,0.28))";

    // ⌥ Space
    const keys = el("div", "keys", root);
    keys.style.top = "742px";
    const k1 = el("div", "kc5", keys, window.UI.optSVG(46, "#f4f4f2", 2.2));
    const k2 = el("div", "kc5 wide", keys, "space");
    const kc = [k1, k2];

    const WAVE = (id) => LAND + clamp((PER.x - (L[id].b.x0 + L[id].b.x1) / 2) / 1560) * 0.3;
    const RISE = 0.13;
    window.L.on((t) => {
      const X = groupX(t);
      g.setAttribute("transform", `translate(${X.toFixed(3)} ${GY.toFixed(3)}) scale(${S})`);
      const z = 1 + 0.035 * prog(t, E0, 15) + 0.012 * ease.outCubic(prog(t, LAND, LAND + 0.5));
      push.setAttribute("transform", `translate(960 540) scale(${z.toFixed(5)}) translate(-960 -540)`);

      for (const id in L) {
        const o = L[id];
        const r = ease.outCubic(prog(t, o.rise, o.rise + RISE));
        const dx = id === "n" || id === "d" ? -SHIFT * (1 - ease.inOutCubic(prog(t, POP + 0.04, POP + 0.32))) : 0;
        o.wrap.setAttribute("transform", `translate(${dx.toFixed(3)} 0)`);
        o.p.setAttribute("transform", `translate(0 ${((1 - r) * o.h).toFixed(3)})`);
        o.wrap.style.visibility = t >= o.rise ? "visible" : "hidden";
        const h = Math.max(cool(t, o.rise), 0.85 * cool(t, WAVE(id), 0.3));
        const c = heatRGB(h);
        o.p.setAttribute("fill", c);
        o.p.setAttribute("stroke", c);
        o.p.style.filter = h > 0.02 ? `drop-shadow(0 0 ${(18 * h).toFixed(1)}px rgba(255,90,31,${(0.75 * h).toFixed(3)}))` : "none";
      }

      // the i: cast with f, n, d; drains back into the mould once the tittle leaves
      const iu = ease.outCubic(prog(t, E0 + 0.035, E0 + 0.035 + RISE));
      const dr = ease.inCubic(prog(t, POP + 0.02, POP + 0.15));
      const top = STEM.y0 + (STEM.y1 - STEM.y0) * Math.max(1 - iu, dr);
      stem.setAttribute("y", top.toFixed(3));
      stem.setAttribute("height", Math.max(0, STEM.y1 - top).toFixed(3));
      const hi = Math.max(cool(t, E0 + 0.035), dr > 0 ? 0.8 : 0);
      stem.setAttribute("fill", heatRGB(hi));
      iw.style.visibility = t >= E0 && dr < 1 ? "visible" : "hidden";

      // the tittle: thrown from the i, lands as the period on the beat with a squash
      const u = prog(t, POP, LAND);
      const ux = ease.inOutCubic(u);
      const cx = lerp(TIT.x, PER.x, ux);
      const cy = lerp(TIT.y, PER.y, u) - 330 * 4 * u * (1 - u);
      const sq = t >= LAND ? Math.exp(-(t - LAND) * 16) * Math.cos((t - LAND) * 34) : 0;
      const pre = t >= POP && t < LAND ? 0.08 * Math.sin(Math.PI * u) : 0;
      const foot = cy + TIT.r;
      tit.setAttribute("cx", cx.toFixed(3));
      tit.setAttribute("cy", cy.toFixed(3));
      tit.setAttribute("transform", `translate(${cx.toFixed(3)} ${foot.toFixed(3)}) scale(${(1 + sq * 0.3 - pre).toFixed(4)} ${(1 - sq * 0.3 + pre).toFixed(4)}) translate(${(-cx).toFixed(3)} ${(-foot).toFixed(3)})`);

      // keys: rise in on the beat, then ⌥ Space is pressed
      kc.forEach((k, i) => {
        const a = ease.outBack(prog(t, KEYS + i * 0.06, KEYS + i * 0.06 + 0.32));
        const pr = Math.sin(Math.PI * prog(t, PRESS + i * 0.03, PRESS + i * 0.03 + 0.14));
        k.style.opacity = clamp(prog(t, KEYS + i * 0.06, KEYS + i * 0.06 + 0.1)).toFixed(3);
        k.style.transform = `translateY(${((1 - a) * 46 + pr * 6).toFixed(2)}px)`;
        k.style.boxShadow = `0 ${(7 - pr * 5).toFixed(1)}px 0 #000, 0 16px 34px rgba(0,0,0,0.7), inset 0 1.5px 0 rgba(255,255,255,0.2), inset 0 0 0 2px rgba(255,255,255,${(0.22 + pr * 0.5).toFixed(3)})`;
      });
    }, { continuous: true });
  }
  return { build, root: "#s-end", tittle, E0 };
})();
