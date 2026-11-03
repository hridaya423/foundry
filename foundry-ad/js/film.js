// Build the single paused root timeline once fonts and the WebGL layer are ready, then register it.
window.FILM = (async function () {
  const D = window.FD.timing.duration;
  const faces = ["800 100px Archivo", "700 100px Archivo", "500 100px Archivo", "400 40px 'Plex Mono'", "500 40px 'Plex Mono'",
    "600 40px 'Plex Mono'", "700 100px 'Noto JP'", "700 100px 'Noto SC'", "700 100px 'Noto Cyr'"];
  window.__buildStage = "fonts";
  await Promise.all(faces.map((f) => document.fonts.load(f, f.includes("Noto JP") ? "こんにちは" : f.includes("Noto SC") ? "你好" : f.includes("Cyr") ? "привет" : "A")));
  await document.fonts.ready;
  window.__buildStage = "gl";
  await window.L.glReady;

  const grain = document.getElementById("grain");
  window.L.on((t) => {
    const f = window.L.frame(t);
    grain.style.transform = `translate(${Math.round(window.L.hash(f) * 64 - 32)}px, ${Math.round(window.L.hash(f + 7919) * 64 - 32)}px)`;
  });

  window.__buildStage = "timeline";
  const tl = gsap.timeline({ paused: true });
  window.ACT1(tl);
  // the stage: each scene builds itself, then falls into the next through its exit dot
  const order = ["keys", "open", "convert", "paste", "speak", "snap", "ask", "end"].filter((id) => window.SC[id]);
  for (const id of order) window.SC[id].build(tl);
  for (let i = 0; i + 1 < order.length; i++) {
    const a = window.SC[order[i]], b = window.SC[order[i + 1]];
    if (a.exit && a.exit.t1) window.ZOOM.link(tl, { from: a.root, to: b.root, dot: a.exit, t0: a.exit.t0, t1: a.exit.t1 });
  }

  window.__buildStage = "images";
  await Promise.all([...document.images].map((im) => im.decode().catch(() => 0)));

  // the clock goes last so per-frame renderers see this frame's tweened state
  tl.to(window.L.clock, { t: D, duration: D, ease: "none" }, 0);
  tl.seek(0);

  // offset pass: the registered timeline plays the film shifted by __TOFF (sub-frame interleaving in tools/final.sh)
  const off = window.__TOFF || 0;
  let main = tl;
  if (off) {
    main = gsap.timeline({ paused: true });
    main.fromTo(tl, { time: off }, { time: D, duration: D - off, ease: "none", immediateRender: true }, 0);
    main.seek(0);
  }

  window.__timelines = window.__timelines || {};
  window.__timelines["main"] = main;
  if (window.__hfForceTimelineRebind) window.__hfForceTimelineRebind();
  window.__buildStage = "ready";
  return { tl }; // a GSAP timeline is thenable; returning it bare would chain this promise to its completion
})();

// Dev preview only (plain browser, no HyperFrames runtime): emulate clip windows and media time, then seek.
window.__dev = {
  async seek(t) {
    const { tl } = await window.FILM;
    const waits = [];
    for (const v of document.querySelectorAll("video.clip")) {
      const s = +v.dataset.start, d = +v.dataset.duration, m = +(v.dataset.mediaStart || 0);
      const on = t >= s && t < s + d;
      v.style.visibility = on ? "visible" : "hidden";
      if (on) {
        const want = m + (t - s);
        if (Math.abs(v.currentTime - want) > 1e-3) {
          waits.push(new Promise((r) => { v.addEventListener("seeked", r, { once: true }); setTimeout(r, 1500); }));
          v.currentTime = want;
        }
      }
    }
    await Promise.all(waits);
    tl.seek(t, false);
    return t;
  },
};
