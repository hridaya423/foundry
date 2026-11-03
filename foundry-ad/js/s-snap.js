// 5 snap: a tiling window manager on sixteenth notes. Every split slides a new pane in from the edge and snaps it
// into place with a molten seam; the furnace pane folds itself into the next dot.
window.SC = window.SC || {};
window.SC.snap = (function () {
  const { prog, ease, PLAN, lerp } = window.L;
  const { el } = window.UI;
  const [A, B] = PLAN.snap;
  const ZOOM = 0.34;
  const S = PLAN.beat / 4;
  const GAP = 14, M = 36;
  const SLIDE = 0.1;
  // [parent, new pane, axis, ratio]: the new pane takes the far side of the parent
  const SPLITS = [
    [0, 1, "x", 0.5],
    [1, 2, "y", 0.5],
    [0, 3, "y", 0.6],
    [2, 4, "x", 0.5],
    [3, 5, "x", 0.42],
    [1, 6, "x", 0.5],
  ].map((s, i) => ({ parent: s[0], child: s[1], axis: s[2], ratio: s[3], t: A + i * S }));
  const FOLD = 4;                                                       // the crucible pane becomes the dot
  const exit = { x: 0, y: 0, r: 16, t0: B - ZOOM, t1: B };
  const F0 = exit.t0 - 0.11;

  function layout(t, out) {
    out[0] = { x0: M, y0: M, x1: 1920 - M, y1: 1080 - M };
    const seams = [];
    for (const s of SPLITS) {
      if (t < s.t) break;
      const R = out[s.parent];
      const g = ease.outExpo(prog(t, s.t, s.t + SLIDE));
      const lo = s.axis === "x" ? R.x0 : R.y0, hi = s.axis === "x" ? R.x1 : R.y1;
      const c = lerp(hi, lo + (hi - lo) * s.ratio, g);
      const half = (GAP / 2) * g;
      const a = { ...R }, b = { ...R };
      if (s.axis === "x") { a.x1 = c - half; b.x0 = c + half; } else { a.y1 = c - half; b.y0 = c + half; }
      out[s.parent] = a;
      out[s.child] = b;
      seams.push({ axis: s.axis, c, R, a: Math.exp(-Math.max(0, t - s.t - 0.04) * 26) });
    }
    return seams;
  }

  function build(tl) {
    const root = document.getElementById("s-snap");
    const vids = [...root.querySelectorAll(".pane")];
    const word = el("div", "pane", root);
    const w = el("div", "verb", word, "snap");
    Object.assign(w.style, { fontSize: "300px", left: "50%", top: "50%", transform: "translate(-50%, -54%)", color: "#f4f4f2" });
    const panes = [word, ...vids];                                        // pane 0 = the word; 1..6 = footage
    root.insertBefore(word, root.firstChild);
    const seamEls = SPLITS.map(() => el("div", "seam", root));
    const fold = el("div", "dot", root);

    const fin = {};
    layout(F0, fin);
    const R4 = fin[FOLD];
    exit.x = (R4.x0 + R4.x1) / 2;
    exit.y = (R4.y0 + R4.y1) / 2;
    Object.assign(fold.style, { left: exit.x - exit.r + "px", top: exit.y - exit.r + "px", width: exit.r * 2 + "px", height: exit.r * 2 + "px", opacity: 0 });

    const rects = {};
    window.L.on((t) => {
      const seams = layout(t, rects);
      panes.forEach((p, i) => {
        let r = rects[i];
        if (!r) { p.style.visibility = "hidden"; return; }
        p.style.visibility = "inherit";
        let rad = 10, op = 1;
        if (i === FOLD && t >= F0) {
          // fold: the pane shrinks into its centre and rounds off into the molten dot
          const f = ease.inCubic(prog(t, F0, exit.t0));
          const hw = lerp((r.x1 - r.x0) / 2, exit.r, f), hh = lerp((r.y1 - r.y0) / 2, exit.r, f);
          r = { x0: exit.x - hw, x1: exit.x + hw, y0: exit.y - hh, y1: exit.y + hh };
          rad = lerp(10, exit.r, f);
          op = 1 - prog(f, 0.55, 1);
        }
        Object.assign(p.style, { left: r.x0.toFixed(2) + "px", top: r.y0.toFixed(2) + "px", width: (r.x1 - r.x0).toFixed(2) + "px",
          height: (r.y1 - r.y0).toFixed(2) + "px", borderRadius: rad.toFixed(2) + "px", opacity: op.toFixed(3) });
      });
      fold.style.opacity = prog(t, F0 + 0.04, exit.t0).toFixed(3);
      seamEls.forEach((s, i) => {
        const z = seams[i];
        if (!z || z.a < 0.01) { s.style.visibility = "hidden"; return; }
        s.style.visibility = "inherit";
        s.style.opacity = z.a.toFixed(3);
        if (z.axis === "x") Object.assign(s.style, { left: z.c - 3 + "px", top: z.R.y0 + "px", width: "6px", height: z.R.y1 - z.R.y0 + "px" });
        else Object.assign(s.style, { left: z.R.x0 + "px", top: z.c - 3 + "px", width: z.R.x1 - z.R.x0 + "px", height: "6px" });
      });
    }, { continuous: true });
  }
  return { build, exit, root: "#s-snap" };
})();
