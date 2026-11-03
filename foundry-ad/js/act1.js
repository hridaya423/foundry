// I (0 – strike): a portable tube set powers on in the dark, a silhouette at the furnace, a flash, the pour,
// then the dive into the pour's white-hot stream lands on the strike.
window.ACT1 = function (tl) {
  const { clamp, lerp, prog, hash, frame, ease, PLAN } = window.L;
  const S = window.FD.screen;
  const $ = (s) => document.querySelector(s);
  const STRIKE = PLAN.strike;

  const tube = $("#tube");
  Object.assign(tube.style, { left: S.x + "px", top: S.y + "px", width: S.w + "px", height: S.h + "px", borderRadius: S.radius + "px" });

  // the stream's core in the pour shot (frame-measured, tube-relative 0..1)
  const DIVE = { u: 0.815, v: 0.47 };
  const ox = S.x + S.w * DIVE.u, oy = S.y + S.h * DIVE.v;

  const PWR = 0.25, POUR = 0.8333, D0 = 1.43;
  tl.set("#a1", { visibility: "visible" }, 0);
  tl.set("#a1", { visibility: "hidden" }, STRIKE);
  tl.set("#cam1", { transformOrigin: `${ox}px ${oy}px`, scale: 1 }, 0);
  tl.set("#tvoff", { opacity: 0 }, 0);
  tl.set("#tubeon", { scaleX: 0.015, scaleY: 0.012, opacity: 0 }, 0);

  // power on: the chassis catches the glow of the pilot dot, the raster opens as a line then a field
  tl.to("#tvoff", { opacity: 1, duration: PWR, ease: "power2.in" }, 0);
  tl.set("#tubeon", { opacity: 1 }, PWR);
  tl.to("#tubeon", { scaleX: 1, duration: 0.05, ease: "expo.out" }, PWR);
  tl.to("#tubeon", { scaleY: 1, duration: 0.13, ease: "expo.out" }, PWR + 0.05);

  // slow push while the shots play, then the dive: expo-in to x11 into the stream, exposure blowing out
  tl.to("#cam1", { scale: 1.09, duration: D0 - 0.3, ease: "sine.inOut" }, 0.3);
  tl.to("#cam1", { scale: 11, duration: STRIKE - D0, ease: "expo.in" }, D0);

  tl.set("#whiteout", { opacity: 1 }, STRIKE);
  tl.set("#whiteout", { opacity: 0 }, STRIKE + 2 / 60);

  // per-frame: pilot flicker, raster brightness, lit-set exposure riding each shot, dive blowout
  const pilot = $("#pilot"), tubeon = $("#tubeon"), lit = $("#tvlit"), cam = $("#cam1");
  const shotLevel = (t) => (t < POUR ? 0.62 : 1.0);
  window.L.on((t) => {
    if (t >= STRIKE) return;
    const f = frame(t);
    const flick = 0.93 + 0.07 * hash(f * 7 + 3);

    const pOn = prog(t, 0.03, 0.12);
    const pLine = prog(t, PWR, PWR + 0.05);
    pilot.style.opacity = (pOn * (0.8 + 0.2 * hash(f)) * (1 - prog(t, PWR + 0.04, PWR + 0.1))).toFixed(3);
    pilot.style.transform = `scale(${lerp(1, 46, ease.outExpo(pLine))}, ${lerp(1, 0.5, pLine)})`;

    const warm = 1 + 3.5 * (1 - ease.outCubic(prog(t, PWR + 0.04, PWR + 0.3)));
    const dive = ease.inExpo(prog(t, D0, STRIKE));
    tubeon.style.filter = `brightness(${(warm * flick * (1 + dive * 2.6)).toFixed(3)})`;

    lit.style.opacity = (clamp(prog(t, PWR + 0.03, PWR + 0.2)) * shotLevel(t) * flick).toFixed(3);
    cam.style.filter = dive > 0.002 ? `blur(${(dive * 5).toFixed(2)}px) brightness(${(1 + dive * 1.8).toFixed(3)})` : "none";
  });
};
