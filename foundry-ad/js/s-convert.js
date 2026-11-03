// 2 convert: a slot reel of extensions spins under "convert" and lands on .png while the bust re-renders on
// every tick; a lasso takes the head, the backdrop drops away, the frame flips to white, the pupil is the dot.
window.SC = window.SC || {};
window.SC.convert = (function () {
  const { prog, ease, PLAN, clamp } = window.L;
  const { el, img, svg, paint, loop } = window.UI;
  const [A, B] = PLAN.convert;
  const ZOOM = 0.42;
  const PH = { x: 1010, y: 90, s: 0.75 };                           // photo box, 900x1200 renders at 0.75
  const at = (u, v) => ({ x: PH.x + u * PH.s, y: PH.y + v * PH.s });
  const pupil = at(352, 390);
  const exit = { x: pupil.x, y: pupil.y, r: 12, t0: B - ZOOM, t1: B };

  const PITCH = 280;
  const ITEMS = [".heic", ".webp", ".jpg", ".pdf", ".gif", ".tiff", ".avif", ".svg", ".png"];
  const LOOK = ["photo", "pixel", "halftone", "ascii", "dither", "photo", "pixel", "halftone", "photo"];
  const R0 = A + 0.06, R1 = A + 0.74;                               // the spin
  const LASSO = R1 + 0.05, DROP = LASSO + 0.1, FLIP = A + 2 * PLAN.beat;

  function reel(t) {
    const p = prog(t, R0, R1);
    let u = (ITEMS.length - 1) * (1 - Math.pow(1 - p, 3.4));
    const s = t - R1;
    if (s > 0) u += 0.16 * Math.exp(-s * 16) * Math.sin(s * 34);   // the reel lands past .png and settles back
    return u;
  }

  function build(tl) {
    const root = document.getElementById("s-convert");
    const word = el("div", "verb", root, "convert");
    Object.assign(word.style, { left: "150px", top: "240px", fontSize: "236px", lineHeight: "200px" });
    const win = el("div", "reel", root);
    Object.assign(win.style, { top: "460px", height: "320px",
      webkitMaskImage: "linear-gradient(transparent 0%, #000 9%, #000 91%, transparent 100%)",
      maskImage: "linear-gradient(transparent 0%, #000 9%, #000 91%, transparent 100%)" });
    const strip = el("div", "strip", win);
    strip.style.top = "20px";
    for (const s of ITEMS) {
      const it = el("div", "item", strip, s);
      if (s === ".png") it.style.color = "var(--molten)";
    }

    const photo = el("div", "photo", root);
    const looks = {};
    for (const k of new Set(LOOK)) looks[k] = img(`assets/img/format/${k}.png`, null, photo);
    const cut = img("assets/img/format/cut.png", null, photo);

    const lasso = paint(svg(root), loop(at(450, 420).x, at(450, 420).y, 190, 262, { seed: 9, rot: 0.06, turns: 1.08, start: -1.9 }), { w: 15 });
    lasso.draw(tl, LASSO, 0.12, "power3.out");
    lasso.erase(tl, FLIP, 0.08);

    const dot = el("div", "dot", root);
    Object.assign(dot.style, { left: exit.x - exit.r + "px", top: exit.y - exit.r + "px", width: exit.r * 2 + "px", height: exit.r * 2 + "px", visibility: "hidden" });
    tl.set(dot, { visibility: "inherit", scale: 0 }, exit.t0 - 0.09);
    tl.to(dot, { scale: 1, duration: 0.1, ease: "back.out(3)" }, exit.t0 - 0.09);

    // flip to white on the beat: ground, type, and the cutout alone
    tl.set(root, { backgroundColor: "#060505", boxShadow: "0 0 0 3000px #060505" }, 0);
    tl.set(root, { backgroundColor: "#f4f4f2", boxShadow: "0 0 0 3000px #f4f4f2" }, FLIP);

    // ticks and looks on the frame grid
    window.L.on((t) => {
      const i = clamp(Math.round(reel(t)), 0, ITEMS.length - 1);
      const flipped = t >= FLIP;
      const dropped = t >= DROP;
      for (const k in looks) looks[k].style.visibility = !dropped && LOOK[i] === k ? "inherit" : "hidden";
      cut.style.visibility = dropped ? "inherit" : "hidden";
      root.style.color = flipped ? "#060505" : "#f4f4f2";
    });
    // the reel and the drop, continuous so they blur
    const drop = el("img", null, photo);
    drop.src = "assets/img/format/photo.png";
    window.L.on((t) => {
      strip.style.transform = `translateY(${(-reel(t) * PITCH).toFixed(2)}px)`;
      const d = prog(t, DROP, FLIP);
      drop.style.visibility = t >= DROP && t < FLIP ? "inherit" : "hidden";
      drop.style.transform = `translateY(${(ease.inCubic(d) * 1300).toFixed(1)}px)`;
    }, { continuous: true });
    photo.insertBefore(drop, cut);
  }
  return { build, exit, root: "#s-convert" };
})();
