// Zoom through a dot. Scene A falls into one of its own molten dots; scene B is already waiting inside it.
// A point a of A maps to C + z (a - dot); a point b of B maps to C + (z / K)(b - centre), with K = 540 / r,
// so when z reaches K, B fills the frame at scale 1. z = K^e grows exponentially (constant felt speed).
window.ZOOM = (function () {
  const { clamp, lerp, prog, smooth } = window.L;
  const { el } = window.UI;
  const links = [];
  const scenes = new Set();

  const inOut = (p) => (p < 0.5 ? 4 * p * p * p : 1 - Math.pow(-2 * p + 2, 3) / 2);

  function ensureDisk(B) {
    let disk = B.querySelector(":scope > .zdisk");
    if (!disk) {
      disk = el("div", "zdisk", B);
      el("div", "zring", B);
    }
    return { disk, ring: B.querySelector(":scope > .zring") };
  }

  // from/to: scene elements; dot: {x, y, r} in A's frame; the fall runs over [t0, t1]
  function link(tl, { from, to, dot, t0, t1 }) {
    const A = typeof from === "string" ? document.querySelector(from) : from;
    const B = typeof to === "string" ? document.querySelector(to) : to;
    const { disk, ring } = ensureDisk(B);
    scenes.add(A);
    scenes.add(B);
    tl.set(B, { visibility: "visible" }, t0);
    tl.set(A, { visibility: "hidden" }, t1);
    links.push({ A, B, disk, ring, dot, t0, t1, K: 540 / dot.r });
  }

  window.L.on((t) => {
    const st = new Map();
    for (const s of scenes) st.set(s, { tf: "none", clip: "none" });
    for (const k of links) {
      k.disk.style.opacity = 0;
      k.ring.style.opacity = 0;
      if (t < k.t0 || t >= k.t1) continue;
      const e = inOut(prog(t, k.t0, k.t1));
      const z = Math.pow(k.K, e);
      const c = smooth(e);
      const cx = lerp(k.dot.x, 960, c), cy = lerp(k.dot.y, 540, c);
      st.get(k.A).tf = `translate(${(cx - z * k.dot.x).toFixed(3)}px, ${(cy - z * k.dot.y).toFixed(3)}px) scale(${z.toFixed(5)})`;
      const s = z / k.K;
      const open = 1 + 1.15 * smooth(prog(e, 0.42, 1));
      st.get(k.B).tf = `translate(${(cx - s * 960).toFixed(3)}px, ${(cy - s * 540).toFixed(3)}px) scale(${s.toFixed(5)})`;
      st.get(k.B).clip = `circle(${(540 * open).toFixed(2)}px at 960px 540px)`;
      k.disk.style.opacity = (1 - smooth(prog(e, 0.26, 0.6))).toFixed(4);
      k.ring.style.opacity = (Math.sin(Math.PI * prog(e, 0.3, 0.95)) * 0.9).toFixed(4);
      k.ring.style.transform = `scale(${open.toFixed(4)})`;
    }
    for (const [s, v] of st) {
      s.style.transform = v.tf;
      s.style.clipPath = v.clip;
    }
  }, { continuous: true });

  return { link };
})();
