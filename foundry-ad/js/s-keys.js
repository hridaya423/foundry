// II (strike – first verb): the ⌥ strike is drawn by gl.js; this adds the 13.6 ms readout and the DOM dot that
// takes over from the hero ember once the camera has it at frame centre.
window.SC = window.SC || {};
window.SC.keys = (function () {
  const { prog, ease, PLAN } = window.L;
  const ZOOM = 0.42;
  const exit = { x: 960, y: 540, r: 11, t0: PLAN.first - ZOOM, t1: PLAN.first };

  function build(tl) {
    const root = document.getElementById("s-keys");
    const ms = root.querySelector("#ms"), n = ms.querySelector(".n");
    const dot = window.UI.el("div", "dot", root);
    Object.assign(dot.style, { left: exit.x - exit.r + "px", top: exit.y - exit.r + "px", width: exit.r * 2 + "px", height: exit.r * 2 + "px", opacity: 0 });

    tl.set(root, { visibility: "visible" }, PLAN.strike);
    const C0 = PLAN.strike + 0.17, C1 = C0 + 0.72;
    window.L.on((t) => {
      const v = 13.6 * ease.outExpo(prog(t, C0, C1));
      n.textContent = v.toFixed(1);
      ms.style.opacity = (prog(t, C0 - 0.02, C0 + 0.04) * (1 - prog(t, exit.t0 - 0.12, exit.t0 - 0.02))).toFixed(3);
      dot.style.opacity = prog(t, exit.t0 - 3 / 60, exit.t0).toFixed(3);
    });
  }
  return { build, exit, root: "#s-keys" };
})();
