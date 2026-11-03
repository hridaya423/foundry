// 1 open: the ember lands as a caret and types "open"; the liftoff plays inside the letters; the camera dives
// through the p's stem into the footage; a painted ring finds the engines and the next dot sits in the flame.
window.SC = window.SC || {};
window.SC.open = (function () {
  const { prog, ease, PLAN } = window.L;
  const { el, svg, paint, loop } = window.UI;
  const [A, B] = PLAN.open;
  const ZOOM = 0.42;
  const exit = { x: 890, y: 520, r: 14, t0: B - ZOOM, t1: B };
  const WORD = "open", FS = 660;
  const STEP = PLAN.beat / 4;
  const types = [...WORD].map((_, i) => A + i * STEP);
  const DV0 = A + WORD.length * STEP + 0.02, DV1 = DV0 + 0.34;

  function setFont(x) {
    x.font = `800 ${FS}px Archivo`;
    x.fontStretch = "condensed";
    x.letterSpacing = `${(-0.03 * FS).toFixed(1)}px`;
    x.textBaseline = "alphabetic";
  }

  function canvas() {
    const c = document.createElement("canvas");
    c.width = 1920;
    c.height = 1080;
    const x = c.getContext("2d");
    setFont(x);
    return { c, x };
  }

  function build(tl) {
    const root = document.getElementById("s-open");
    const feet = root.querySelector(".feet");
    const vid = feet.querySelector("video");

    // layout: every prefix centred on x = 960, x-height centred on y = 540
    const m = canvas().x;
    const ls = -0.03 * FS;
    const xh = m.measureText("x").actualBoundingBoxAscent;
    const base = 540 + xh / 2;
    const width = (s) => m.measureText(s).width - ls;
    const offs = [...WORD].map((_, i) => m.measureText(WORD.slice(0, i)).width);
    const states = [];
    for (let k = 1; k <= WORD.length; k++) {
      const s = WORD.slice(0, k);
      const left = 960 - width(s) / 2;
      const mk = canvas();
      mk.x.fillStyle = "#000";
      mk.x.fillText(s, left, base);
      const fl = canvas();
      fl.x.fillStyle = "#f4f4f2";
      fl.x.fillText(WORD[k - 1], left + offs[k - 1], base);
      fl.c.className = "fill";
      fl.c.style.visibility = "hidden";
      root.appendChild(fl.c);
      states.push({ url: `url(${mk.c.toDataURL("image/png")})`, right: left + width(s), flash: fl.c, mask: mk });
    }
    for (const s of states) {
      const warm = el("img", null, root);
      warm.src = s.url.slice(4, -1);
      Object.assign(warm.style, { position: "absolute", width: "1px", height: "1px", opacity: 0 });
    }

    // the dive aims at the middle of the p's stem: the first ink run inside the p on the x-height midline
    const row = states[WORD.length - 1].mask.x.getImageData(0, 540, 1920, 1).data;
    const pl = 960 - width(WORD) / 2 + offs[1], pr = 960 - width(WORD) / 2 + offs[2];
    let best = null;
    for (let i = Math.floor(pl), run = -1; i <= pr && !best; i++) {
      const on = row[i * 4 + 3] > 200;
      if (on && run < 0) run = i;
      if (!on && run >= 0) best = { a: run, b: i };
    }
    const P = { x: (best.a + best.b) / 2, y: 540 };

    const caret = el("div", "caret", root);
    const CH = FS * 0.74;
    Object.assign(caret.style, { height: CH + "px", top: 540 - CH / 2 + "px" });

    const ring = paint(svg(root), loop(890, 470, 250, 150, { seed: 4, rot: -0.08, turns: 1.1 }), { w: 16 });
    ring.draw(tl, exit.t0 - 0.17, 0.15, "power3.out");
    const dot = el("div", "dot", root);
    Object.assign(dot.style, { left: exit.x - exit.r + "px", top: exit.y - exit.r + "px", width: exit.r * 2 + "px", height: exit.r * 2 + "px", visibility: "hidden" });
    tl.set(dot, { visibility: "inherit", scale: 0 }, exit.t0 - 0.1);
    tl.to(dot, { scale: 1, duration: 0.1, ease: "back.out(3)" }, exit.t0 - 0.1);

    // keystrokes, on the frame grid
    let shown = -1;
    window.L.on((t) => {
      let k = 0;
      while (k < WORD.length && t >= types[k]) k++;
      if (t >= DV1) k = -1;
      if (k !== shown) {
        const url = k > 0 ? states[k - 1].url : "none";
        feet.style.webkitMaskImage = feet.style.maskImage = url;
        feet.style.opacity = k === 0 ? 0 : 1;
        shown = k;
      }
      const typed = Math.max(0, Math.min(WORD.length, k < 0 ? WORD.length : k));
      states.forEach((s, i) => { s.flash.style.visibility = i === typed - 1 && t < types[i] + 3 / 60 && t < DV0 ? "inherit" : "hidden"; });
      const cx = typed === 0 ? 960 - 13 : states[typed - 1].right + 26;
      caret.style.left = cx.toFixed(1) + "px";
      caret.style.visibility = t < DV0 ? "inherit" : "hidden";
    });

    // the dive and the push, continuous so they blur
    window.L.on((t) => {
      vid.style.transform = `scale(${(1.14 - 0.1 * ease.outCubic(prog(t, A, B))).toFixed(4)})`;
      let z = 1;
      if (t >= DV0 && t < DV1) z = Math.pow(90, ease.inCubic(prog(t, DV0, DV1)));
      Object.assign(feet.style, {
        webkitMaskSize: `${1920 * z}px ${1080 * z}px`, maskSize: `${1920 * z}px ${1080 * z}px`,
        webkitMaskPosition: `${P.x - z * P.x}px ${P.y - z * P.y}px`, maskPosition: `${P.x - z * P.x}px ${P.y - z * P.y}px`,
        webkitMaskRepeat: "no-repeat", maskRepeat: "no-repeat",
      });
    }, { continuous: true });
  }
  return { build, exit, root: "#s-open" };
})();
