// 4 speak: on white, a giant "speak" stands behind the Earth; greetings in a dozen languages orbit the globe in
// perspective, passing behind it and in front of it; a molten satellite rides the ring and parks as the next dot.
window.SC = window.SC || {};
window.SC.speak = (function () {
  const { prog, ease, PLAN, lerp } = window.L;
  const { el, img } = window.UI;
  const [A, B] = PLAN.speak;
  const ZOOM = 0.42;
  const FS = 560;
  const E = { x: 960, y: 820, d: 520 };                               // the globe
  const RING = { rx: 880, ry: 210, tilt: -0.05 };
  const WORDS = ["hello", "hola", "こんにちは", "bonjour", "привет", "olá"];
  const SAT0 = -0.2, SAT1 = 1.55;                                    // parks at the near bottom, clear of the wings
  const pos = (th, out) => {
    const x = Math.cos(th) * RING.rx, y = Math.sin(th) * RING.ry;
    out.x = E.x + x * Math.cos(RING.tilt) - y * Math.sin(RING.tilt);
    out.y = E.y + x * Math.sin(RING.tilt) + y * Math.cos(RING.tilt);
    out.depth = (Math.sin(th) + 1) / 2;                              // 0 far .. 1 near
    return out;
  };
  const sat = (t) => lerp(SAT0, SAT1, ease.inOutCubic(prog(t, A - 0.3, B - ZOOM - 0.02)));
  const exit = { x: 0, y: 0, r: 20, t0: B - ZOOM, t1: B };
  { const p = pos(SAT1, {}); exit.x = p.x; exit.y = p.y; }

  function build(tl) {
    const root = document.getElementById("s-speak");
    const word = el("div", "verb", root, "speak");
    word.style.fontSize = FS + "px";
    const m = document.createElement("canvas").getContext("2d");
    m.font = `800 ${FS}px Archivo`;
    m.fontStretch = "condensed";
    const mt = m.measureText("p");
    const xh = m.measureText("x").actualBoundingBoxAscent;
    const base = 470 + xh / 2;
    const top = base - (FS - (mt.fontBoundingBoxAscent + mt.fontBoundingBoxDescent)) / 2 - mt.fontBoundingBoxAscent;
    const w = word.getBoundingClientRect().width;
    Object.assign(word.style, { left: 960 - w / 2 + "px", top: top + "px", zIndex: 0, color: "#060505" });

    const earth = img("assets/img/earth.png", "earth", root);
    Object.assign(earth.style, { left: E.x - E.d / 2 + "px", top: E.y - E.d / 2 + "px", width: E.d + "px", height: E.d + "px", zIndex: 2 });

    const words = WORDS.map((s, i) => {
      const d = el("div", "ringw", root, s);
      return { d, th0: (i / WORDS.length) * Math.PI * 2, w: d.getBoundingClientRect().width };
    });
    const dot = el("div", "dot", root);
    Object.assign(dot.style, { left: -exit.r + "px", top: -exit.r + "px", width: exit.r * 2 + "px", height: exit.r * 2 + "px" });

    const p = {};
    window.L.on((t) => {
      // ring angle: the integral of omega (outCubic integrates to p + ((1 - p)^4 - 1) / 4)
      const t0 = A - 0.42, Lw = B - t0, q = prog(t, t0, B);
      const th = 0.2 * Math.max(0, t - t0) + 1.15 * (Lw * (q + (Math.pow(1 - q, 4) - 1) / 4) + Math.max(0, t - B));
      const grow = ease.outExpo(prog(t, A - 0.3, A + 0.25));
      for (const k of words) {
        const ang = k.th0 + th;
        let a = ((ang % (Math.PI * 2)) + Math.PI * 3) % (Math.PI * 2) - Math.PI;
        const right = Math.exp(-(a * a) / 0.10);
        const left = Math.exp(-((Math.abs(a) - Math.PI) ** 2) / 0.10);
        const gate = Math.max(left, right);
        const side = left > right ? -1 : 1;
        const x = 960 + side * 700;
        const y = 800 + 16 * Math.sin(ang);
        k.d.style.transform = `translate(${(x - k.w / 2).toFixed(2)}px, ${(y - 58).toFixed(2)}px)`;
        k.d.style.zIndex = 3;
        k.d.style.opacity = (gate * grow).toFixed(3);
      }
      pos(sat(t), p);
      const ds = lerp(0.6, 1, p.depth);
      dot.style.transform = `translate(${p.x.toFixed(2)}px, ${p.y.toFixed(2)}px) scale(${ds.toFixed(4)})`;
      dot.style.zIndex = p.depth > 0.5 ? 4 : 1;
      dot.style.visibility = t >= A - 0.3 ? "inherit" : "hidden";
      earth.style.transform = `rotate(${(-6 * prog(t, A - 0.42, B)).toFixed(3)}deg) scale(${(1 + 0.04 * ease.outCubic(prog(t, A - 0.42, B))).toFixed(4)})`;
      word.style.transform = `translateX(${(-30 * prog(t, A - 0.42, B)).toFixed(2)}px)`;
    }, { continuous: true });
  }
  return { build, exit, root: "#s-speak" };
})();
