// 6 ask: the dot blooms into a network around "ask"; molten pulses run inward along its edges; then everything
// collapses into one point, which is where the tittle of "find" sits in the next frame.
window.SC = window.SC || {};
window.SC.ask = (function () {
  const { prog, ease, PLAN, lerp, rng, clamp } = window.L;
  const { el, svg, node } = window.UI;
  const [A, B] = PLAN.ask;
  const BLOOM = 0.3, C0 = B - 0.3;

  // nodes: rejection-sampled inside an ellipse, nearest-neighbour edges
  const R = rng(4242);
  const nodes = [];
  for (let k = 0; nodes.length < 56 && k < 6000; k++) {
    const a = R() * Math.PI * 2, rr = Math.sqrt(R());
    const x = 960 + Math.cos(a) * rr * 900, y = 540 + Math.sin(a) * rr * 470;
    if (Math.hypot((x - 960) / 1.6, y - 540) < 150) continue;
    if (nodes.every((n) => Math.hypot(n.x - x, n.y - y) > 100)) nodes.push({ x, y, r: 4.2 + R() * 5, d: Math.hypot((x - 960) / 1.9, y - 540) });
  }
  const edges = [];
  nodes.forEach((n, i) => {
    const near = nodes.map((m, j) => [j, Math.hypot(m.x - n.x, m.y - n.y)]).filter(([j]) => j !== i).sort((a, b) => a[1] - b[1]).slice(0, 2);
    for (const [j] of near) if (!edges.some(([a, b]) => (a === j && b === i))) edges.push([i, j]);
  });
  // pulses: from an outer node, hop to the neighbour nearest the centre, three times
  const pulses = [];
  const outer = nodes.map((n, i) => [i, n.d]).sort((a, b) => b[1] - a[1]).slice(0, 5).map(([i]) => i);
  outer.forEach((s, k) => {
    const path = [s];
    for (let h = 0; h < 3; h++) {
      const cur = path[path.length - 1];
      const nb = edges.filter(([a, b]) => a === cur || b === cur).map(([a, b]) => (a === cur ? b : a)).filter((j) => !path.includes(j));
      if (!nb.length) break;
      path.push(nb.sort((a, b) => nodes[a].d - nodes[b].d)[0]);
    }
    pulses.push({ path, t0: A + BLOOM - 0.06 + k * 0.035, hop: 0.075 });
  });

  function build(tl) {
    const root = document.getElementById("s-ask");
    const T = window.SC.end.tittle;
    const s = svg(root);
    const lines = edges.map(() => node("line", { stroke: "#f4f4f2", "stroke-width": 1.6, "stroke-linecap": "round" }, s));
    const dots = nodes.map((n) => node("circle", { r: n.r, fill: "#f4f4f2" }, s));
    const sparks = pulses.map(() => node("circle", { r: 7, fill: "#ff5a1f" }, s));
    for (const p of sparks) p.style.filter = "drop-shadow(0 0 8px rgba(255,90,31,0.9))";
    const word = el("div", "verb", root, "ask");
    word.style.fontSize = "420px";
    const w = word.getBoundingClientRect().width;
    Object.assign(word.style, { left: 960 - w / 2 + "px", top: 540 - 0.6 * 420 + "px", color: "#f4f4f2", transformOrigin: "50% 60%" });
    const dot = el("div", "dot", root);
    Object.assign(dot.style, { left: T.x - T.r + "px", top: T.y - T.r + "px", width: T.r * 2 + "px", height: T.r * 2 + "px" });
    tl.set(root, { visibility: "hidden" }, B);

    const P = nodes.map(() => ({ x: 0, y: 0 }));
    window.L.on((t) => {
      const col = ease.inExpo(prog(t, C0, B));
      nodes.forEach((n, i) => {
        const b = ease.outExpo(prog(t, A - 0.12 + n.d / 900 * 0.12, A + BLOOM + n.d / 900 * 0.1));
        P[i].x = lerp(lerp(960, n.x, b), T.x, col);
        P[i].y = lerp(lerp(540, n.y, b), T.y, col);
        dots[i].setAttribute("cx", P[i].x.toFixed(2));
        dots[i].setAttribute("cy", P[i].y.toFixed(2));
        dots[i].setAttribute("opacity", (clamp(b * 3) * (1 - prog(col, 0.85, 1))).toFixed(3));
      });
      edges.forEach(([a, b], k) => {
        const l = lines[k];
        l.setAttribute("x1", P[a].x.toFixed(2)); l.setAttribute("y1", P[a].y.toFixed(2));
        l.setAttribute("x2", P[b].x.toFixed(2)); l.setAttribute("y2", P[b].y.toFixed(2));
        const on = prog(t, A + 0.05 + k * 0.002, A + BLOOM + 0.05);
        l.setAttribute("opacity", (0.48 * on * (1 - prog(col, 0.6, 1))).toFixed(3));
      });
      pulses.forEach((p, k) => {
        const hops = p.path.length - 1;
        const u = (t - p.t0) / p.hop;
        if (u < 0 || u >= hops || t >= C0) { sparks[k].setAttribute("opacity", 0); return; }
        const h = Math.floor(u), f = ease.inOutCubic(u - h);
        const a = P[p.path[h]], b = P[p.path[h + 1]];
        sparks[k].setAttribute("cx", lerp(a.x, b.x, f).toFixed(2));
        sparks[k].setAttribute("cy", lerp(a.y, b.y, f).toFixed(2));
        sparks[k].setAttribute("opacity", 1);
      });
      const wa = ease.outExpo(prog(t, A - 0.1, A + 0.16));
      const ws = lerp(0.82, 1, wa) * lerp(1, 0.02, col);
      const wx = lerp(0, T.x - 960, col), wy = lerp(0, T.y - 540, col);
      word.style.transform = ws > 0.9999 && col === 0 ? "none" : `translate(${wx.toFixed(2)}px, ${wy.toFixed(2)}px) scale(${ws.toFixed(4)})`;
      word.style.opacity = (1 - prog(col, 0.7, 1)).toFixed(3);
      dot.style.transform = `scale(${ease.outBack(prog(t, C0 + 0.12, B)).toFixed(4)})`;
    }, { continuous: true });
  }
  return { build, root: "#s-ask" };
})();
