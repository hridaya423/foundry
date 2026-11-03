// "Every job." (v2). Every frame is a pure function of composition time t. Timing: js/timing.js.
(function () {
  const { prog, ease, lerp, clamp, frame, hash, rng } = window.L;
  const M = window.MOSAIC, T = window.TYPE, TM = window.TM, W = 1920, H = 1080;
  const D = TM.end;
  const full = { x: 0, y: 0, w: W, h: H };
  const PIC = { x: 240, y: 0, w: 1440, h: 1080 };
  const SH = 0.5 / 60;
  const vel = (fn, t) => Math.abs(fn(t + SH / 2) - fn(t - SH / 2));
  const MONO = "'Plex Mono'";
  const seg = (t, keys) => {
    if (t <= keys[0][0]) return keys[0][1];
    for (let i = 1; i < keys.length; i++) if (t <= keys[i][0]) {
      const [t0, v0] = keys[i - 1], [t1, v1, e] = keys[i];
      return lerp(v0, v1, (e || ease.inOutCubic)(prog(t, t0, t1)));
    }
    return keys[keys.length - 1][1];
  };
  const typedStr = (o, t) => o.text.slice(0, Math.floor(clamp((t - o.t0) * o.cps, 0, o.text.length)));
  const fract = (x) => x - Math.floor(x);
  const h21 = (x, y) => { let px = fract(x * 123.34), py = fract(y * 456.21); const d = px * (px + 45.32) + py * (py + 45.32); px += d; py += d; return fract(px * py); };

  // ------------------------------------------------------------------ the set, and the wall of sets
  const SCR = window.SCREEN;
  const scr = [SCR.x / 3840, SCR.y / 2160, SCR.w / 3840, SCR.h / 2160];
  const RAD = SCR.radius / 2160;
  const BOX = [0.30, 0.17, 0.52, 0.70];          // one set's tile, plate fractions
  const [WALL0, WALL1] = TM.wall, [RIV0, RIV1] = TM.river;
  const MELT0 = TM.meltCmd;                      // ignition, on the enter's frame
  // Act I: every word is its own shot. The camera on the tube, the footage in it and its exposure all change on the cut,
  // so each strike reads as a cut (scene contrast was 0.10-0.15 with one framing and one vignette for all five)
  const SHOTS = [   // z: camera on the tube; f: footage zoom over the shot; at: footage focus; dim: black over the footage
    { z: 5.0, c: [0.441, 0.385], f: [1.0, 1.1], at: [0.5, 0.5], dim: 0.32 },   // A: tight on the struck letter, the glass fills the frame
    { z: 2.45, f: [1.5, 1.32], at: [0.42, 0.62], dim: 0.6 },    // machine: the switchboard, close and dark
    { z: 3.15, f: [1.05, 1.2], at: [0.56, 0.46], dim: 0.34 },   // for: the telegraph
    { z: 2.6, f: [1.32, 1.16], at: [0.5, 0.42], dim: 0.2 },     // every: the console, lit
    { z: 2.85, f: [1.0, 1.14], at: [0.5, 0.5], dim: 0.26 },     // job.: ignition
  ];
  const wordAt = (t) => TM.words1.reduce((k, w, i) => (t >= w[1] ? i : k), 0);
  const camZoom = (t) => {
    if (t < TM.act2) { const k = wordAt(t); return SHOTS[k].z * (1 + 0.03 * (t - TM.words1[k][1])); }
    if (t < WALL0) return lerp(2.45, 2.55, ease.inOutCubic(prog(t, TM.act2, WALL0)));
    if (t < WALL1) return Math.exp(lerp(Math.log(2.3), Math.log(0.15), ease.inOutCubic(prog(t, WALL0, WALL1))));
    return seg(t, [[WALL1, 0.15], [RIV0, 0.138], [RIV1, 0.5, ease.inCubic]]);
  };
  const camY = (t) => seg(t, [[RIV0, 0.5], [RIV1, 3.1, ease.inCubic]]);
  // a hand on the camera while it looks at one set (a few px of drift); locked once it pulls back
  const hand = (t) => t >= WALL0 ? [0, 0] : [0.0008 * (Math.sin(t * 1.7) + 0.6 * Math.sin(t * 4.3 + 1.3)), 0.0006 * (Math.sin(t * 1.3 + 0.7) + 0.5 * Math.sin(t * 3.7 + 2.1))];
  const camAt = (t) => {
    const [hx, hy] = hand(t), c = t < TM.act2 && SHOTS[wordAt(t)].c;
    return { cx: (c ? c[0] : 0.5) + hx, cy: (c ? c[1] : camY(t)) + hy, zoom: camZoom(t) };
  };
  // the wall tilts away as the camera pulls back, and flattens again as it falls with the river into the mould
  const perspAt = (t) => ease.inOutCubic(prog(t, WALL0 + 0.1, WALL1)) * (1 - ease.inOutCubic(prog(t, RIV0 + 0.5, RIV1 - 0.1)));
  // hot air: the overheating set shimmers a little, the burning wall a lot, the casting less as it cools
  const hazeAt = (t, overheat) => t < MELT0 ? 0.35 * overheat : t < TM.cast ? 0.4 + 0.6 * prog(t, MELT0, MELT0 + 0.6) : 0.45 * (1 - prog(t, TM.cast, TM.glass));
  const embersAt = (t) => ease.inOutCubic(prog(t, MELT0 + 0.15, MELT0 + 0.55)) * (1 - ease.inOutCubic(prog(t, TM.cast + 0.8, TM.cast + 1.3)));
  const toOut = (c, x, y) => ({ x: ((x - c.cx) * c.zoom + 0.5) * W, y: ((y - c.cy) * c.zoom + 0.5) * H });

  function tubeText(ctx, str, x, y, size, align = "left", alpha = 1, weight = 600) {
    if (!str) return;
    ctx.save(); ctx.font = `${weight} ${size}px ${MONO}`; ctx.textAlign = align; ctx.textBaseline = "alphabetic";
    ctx.globalAlpha = alpha; ctx.shadowColor = "rgba(0,0,0,0.85)"; ctx.shadowBlur = size * 0.3; ctx.fillStyle = "#fff"; ctx.fillText(str, x, y); ctx.restore();
  }

  // ------------------------------------------------------------------ Act I: struck by a typewriter, a machine per word
  const LINES1 = [["A", "machine"], ["for", "every"], ["job."]];
  const LINE1 = { size: 220, x: 250, y: [330, 614, 898] };   // output px: where the line sits from "machine" on
  function act1(ctx, t) {
    const W1 = TM.words1, k = wordAt(t), [, t0, clip] = W1[k], u = t - t0, S = SHOTS[k];
    const z = lerp(S.f[0], S.f[1], prog(u, 0, (W1[k + 1] ? W1[k + 1][1] : TM.act2) - t0));
    M.drawCover(ctx, M.frameAt(clip, u, 0, "hold"), PIC, z, S.at[0], S.at[1]);
    ctx.fillStyle = `rgba(0,0,0,${S.dim})`; ctx.fillRect(PIC.x, 0, PIC.w, PIC.h);
    // the words: each strikes whole, on its frame; every letter sits a little off, the way type bars land
    // from "machine" on, the line is set once on the screen: the camera's zoom and centre are undone here, so each cut
    // changes the shot behind the words and the line only grows (shot A alone is the close-up on the struck letter)
    const cam = camAt(t), fix = k > 0;
    const size = fix ? LINE1.size / (scr[3] * cam.zoom) : 196, js = size / 196;
    const at = (xo, yo) => [PIC.x + ((xo / W - 0.5) / cam.zoom + cam.cx - scr[0]) / scr[2] * PIC.w, ((yo / H - 0.5) / cam.zoom + cam.cy - scr[1]) / scr[3] * PIC.h];
    ctx.save(); ctx.font = `600 ${size}px ${MONO}`; const cw = ctx.measureText("M").width; ctx.restore();
    let wi = 0;
    LINES1.forEach((line, li) => {
      let col = 0;
      line.forEach((word) => {
        const [w, wt] = W1[wi++];
        if (t >= wt) {
          const p = clamp((t - wt) * 30 + 0.5);
          [...w].forEach((ch, ci) => {
            const r = hash(wi * 31 + ci * 7);
            const [x0, y0] = fix ? at(LINE1.x, LINE1.y[li]) : [PIC.x + 110, PIC.h * [0.33, 0.56, 0.79][li]];
            const x = x0 + (col + ci) * cw, y = y0 + ((r - 0.5) * 8 - (1 - p) * 12) * js;
            tubeText(ctx, ch, x, y, size, "left", (0.82 + 0.18 * hash(ci * 13 + wi)) * Math.min(1, p * 2));
          });
        }
        col += w.length + 1;
      });
    });
  }
  // the tube jolts a few pixels on each strike
  const strikeJolt = (t) => TM.words1.reduce((a, [, wt]) => a + (t >= wt ? Math.exp(-(t - wt) / 0.05) : 0), 0);

  // ------------------------------------------------------------------ Act II: an app for every job
  function drawWindow(ctx, a, r, t, alpha, barH) {
    const bar = barH || Math.min(64, r.h * 0.13);
    ctx.save(); ctx.globalAlpha = alpha;
    ctx.shadowColor = "rgba(0,0,0,0.6)"; ctx.shadowBlur = 34; ctx.shadowOffsetY = 12;
    ctx.fillStyle = "#1c1c1e"; M.roundRect(ctx, r.x, r.y, r.w, r.h, 12); ctx.fill(); ctx.shadowColor = "transparent";
    ctx.save(); M.roundRect(ctx, r.x, r.y, r.w, r.h, 12); ctx.clip();
    if (a.clip) M.drawCover(ctx, M.frameAt(a.clip, t - (a.t || 0), a.off || 0), { x: r.x, y: r.y + bar, w: r.w, h: r.h - bar }, 1.04, 0.5, 0.5);
    ctx.fillStyle = "#2b2b2e"; ctx.fillRect(r.x, r.y, r.w, bar);
    const dot = bar * 0.14;
    [0, 1, 2].forEach((k) => { ctx.fillStyle = ["#ff5f57", "#febc2e", "#28c840"][k]; ctx.beginPath(); ctx.arc(r.x + bar * 0.5 + k * dot * 3, r.y + bar / 2, dot, 0, Math.PI * 2); ctx.fill(); });
    ctx.fillStyle = "#f4f4f4"; ctx.textAlign = "center"; ctx.textBaseline = "middle";
    if (bar >= 100) {   // a hero: its title in the system's sans, as large as the bar allows, never cut short
      ctx.font = `600 100px Geist`;
      const fs = Math.min(bar * 0.5, 100 * (r.w - bar * 2.6) / ctx.measureText(a.title).width);
      ctx.font = `600 ${fs.toFixed(1)}px Geist`; ctx.fillText(a.title, r.x + r.w / 2 + bar * 0.5, r.y + bar / 2 + 2);
    } else {
      ctx.font = `500 ${Math.round(bar * 0.42)}px ${MONO}`;
      ctx.fillText(M.ellipsize(ctx, a.title, r.w - bar * 3.0), r.x + r.w / 2 + bar * 0.45, r.y + bar / 2 + 1);
    }
    ctx.restore(); ctx.restore();
  }
  const APPS = TM.apps.map(([title, clip], i) => {
    const r = rng(900 + i * 17);
    const hero = i < 3;
    const w = hero ? 1300 : 420 + r() * 300, h = hero ? 660 : 280 + r() * 200;
    const slots = [[0.0, 0.16], [0.9, 0.5], [0.3, 0.86]];
    const [sx, sy] = hero ? slots[i] : [r(), r()];
    return { title, clip, t: TM.appT[i], w, h, x: PIC.x + 10 + sx * (PIC.w - w - 20), y: 34 + sy * (PIC.h - h - 44), off: Math.floor(r() * 40) };
  });
  function act2(ctx, t) {
    const g = ctx.createLinearGradient(0, 0, 0, PIC.h); g.addColorStop(0, "#222"); g.addColorStop(1, "#0d0d0d");
    ctx.fillStyle = g; ctx.fillRect(PIC.x, 0, PIC.w, PIC.h);
    ctx.fillStyle = "#2c2c2c"; ctx.fillRect(PIC.x, 0, PIC.w, 26);
    // a note app, its I-beam typing the line
    const nr = { x: PIC.x + 70, y: 290, w: PIC.w - 140, h: 350 };
    drawWindow(ctx, { title: "Untitled" }, nr, t, 1, 56);
    ctx.fillStyle = "#f0f0f0"; ctx.fillRect(nr.x + 20, nr.y + 80, nr.w - 40, nr.h - 100);
    const s = typedStr(TM.line2, t);
    ctx.save(); ctx.font = `600 96px ${MONO}`; ctx.fillStyle = "#111"; ctx.textBaseline = "alphabetic";
    ctx.fillText(s, nr.x + 50, nr.y + 240);
    const bx = nr.x + 50 + ctx.measureText(s).width + 6;
    if (s.length < TM.line2.text.length || Math.floor((t - TM.line2.t0) * 4) % 2 === 0) { ctx.fillStyle = "#111"; ctx.fillRect(bx, nr.y + 160, 6, 100); }
    ctx.restore();
    APPS.forEach((a) => {
      if (t < a.t) return;
      const p = ease.outExpo(prog(t, a.t, a.t + 0.14)), sc = 0.9 + 0.1 * p;
      drawWindow(ctx, a, { x: a.x + a.w * (1 - sc) / 2, y: a.y + a.h * (1 - sc) / 2, w: a.w * sc, h: a.h * sc }, t, clamp(p * 1.4), a.w > 900 ? 118 : undefined);
    });
  }
  // the other sets on the wall: 48 small desktops, each with its own pile
  function drawAtlas(actx, t) {
    const cw = W / 8, ch = H / 6;
    actx.fillStyle = "#121212"; actx.fillRect(0, 0, W, H);
    for (let k = 0; k < 48; k++) {
      const x0 = (k % 8) * cw, y0 = Math.floor(k / 8) * ch;
      actx.save(); actx.beginPath(); actx.rect(x0, y0, cw, ch); actx.clip();
      actx.fillStyle = "#1d1d1d"; actx.fillRect(x0, y0, cw, ch);
      for (let j = 0; j < 4; j++) {
        const a = APPS[(k * 3 + j) % APPS.length], r = rng(k * 41 + j);
        const w = cw * (0.45 + r() * 0.35), h = ch * (0.4 + r() * 0.3);
        const rr = { x: x0 + r() * (cw - w), y: y0 + r() * (ch - h), w, h };
        actx.fillStyle = "#2b2b2e"; actx.fillRect(rr.x, rr.y, rr.w, rr.h);
        M.drawCover(actx, M.frameAt(a.clip, t + k * 0.3, a.off), { x: rr.x, y: rr.y + 8, w: rr.w, h: rr.h - 8 }, 1.04);
      }
      actx.restore();
    }
  }

  // ------------------------------------------------------------------ the river: every set's metal, braided into one
  function wallDrips(mctx, t, cam) {
    const u = t - MELT0;
    if (u <= 0) return;
    const hw = 0.5 / cam.zoom, hh = 0.5 / cam.zoom;
    const i0 = Math.floor((cam.cx - hw - BOX[0]) / BOX[2]) - 1, i1 = Math.ceil((cam.cx + hw - BOX[0]) / BOX[2]) + 1;
    const j0 = Math.floor((cam.cy - hh - BOX[1]) / BOX[3]) - 1, j1 = Math.ceil((cam.cy + hh - BOX[1]) / BOX[3]) + 1;
    const rx = cam.cx, yBot0 = scr[1] + scr[3];
    mctx.save(); mctx.strokeStyle = "rgb(0,0,255)"; mctx.lineCap = "round"; mctx.globalCompositeOperation = "lighter";
    const px = (v) => Math.max(2.5, v * cam.zoom * W);
    for (let j = Math.max(j0, -6); j <= Math.min(j1, 5); j++) for (let i = i0; i <= i1; i++) {
      const dl = h21(i + 1.7, j + 1.7) * 0.25 + Math.hypot(i, j) * 0.07;   // the ignition wave (same as gl.js)
      for (let d = 0; d < 2; d++) {
        const r = hash((i + 50) * 977 + (j + 50) * 131 + d);
        const v = u - dl - 0.3 - r * 0.25;
        if (v <= 0) continue;
        const x0 = scr[0] + scr[2] * (0.15 + 0.7 * r) + i * BOX[2], y0 = yBot0 + j * BOX[3];
        const len = 1.6 * v * v + 0.12 * v;
        const span = Math.abs(x0 - rx) * 1.1 + 0.6;
        const pts = [];
        for (let s = 0; s <= 24; s++) {
          const y = y0 + len * (s / 24);
          pts.push(toOut(cam, lerp(x0, rx, ease.inOutCubic(clamp((y - y0) / span))), y));
        }
        mctx.lineWidth = px(0.0045 + 0.004 * r);
        mctx.beginPath(); mctx.moveTo(pts[0].x, pts[0].y); for (const p of pts) mctx.lineTo(p.x, p.y); mctx.stroke();
      }
    }
    // the river itself, thickening as it is fed
    const thick = 0.012 + 0.065 * ease.inCubic(prog(u, 0.6, RIV1 - MELT0));
    const a = toOut(cam, rx, cam.cy - hh - 0.1), b = toOut(cam, rx, cam.cy + hh + 0.1);
    if (u > 0.6) { mctx.lineWidth = px(thick); mctx.beginPath(); mctx.moveTo(a.x, Math.max(a.y, toOut(cam, rx, yBot0 + 1.2).y)); mctx.lineTo(b.x, b.y); mctx.stroke(); }
    mctx.restore();
  }

  // ------------------------------------------------------------------ the mould: Foundry's bar
  const BAR = { x: 280, y: 456, w: 1360, h: 168, r: 84 };
  function barCanvas() {
    const c = M.canvas(W * 2, H * 2), x = c.getContext("2d");
    x.fillStyle = "#000"; x.fillRect(0, 0, c.width, c.height);
    x.fillStyle = "rgb(255,255,128)"; M.roundRect(x, BAR.x * 2, BAR.y * 2, BAR.w * 2, BAR.h * 2, BAR.r * 2); x.fill();
    return c;
  }

  // ------------------------------------------------------------------ results: the plate world (gif, then remove background)
  const PW = W, PH = W / (3600 / 2219);
  const COLS = [[0.0239, 0.2533], [0.2628, 0.4933], [0.5017, 0.7325], [0.7417, 0.9725]];
  const ROWS = [[0.041, 0.2808], [0.2938, 0.5349], [0.5475, 0.7891]];
  const PANELS = [];
  for (const r of ROWS) for (const c of COLS) PANELS.push({ x: c[0] * PW, y: r[0] * PH, w: (c[1] - c[0]) * PW, h: (r[1] - r[0]) * PH });
  const HERO = 5, heroP = PANELS[HERO], Pc = { x: heroP.x + heroP.w / 2, y: heroP.y + heroP.h / 2 };
  const C0 = { x: PW / 2, y: (ROWS[0][0] + ROWS[2][1]) / 2 * PH };
  const S1 = (W * 1.03) / heroP.w, PZ = 1.2, gallopOff = (k) => k * 3.25;
  const KG = TM.kills[0], KR = TM.kills[1];
  function plateCam(t) {
    const e = ease.inOutCubic(prog(t, KG.enter + 0.08, KG.enter + 0.5));
    const s0 = 0.97, s = s0 * Math.pow(S1 / s0, e);
    const sp0 = { x: (Pc.x - C0.x) * s0, y: (Pc.y - C0.y) * s0 };
    return { s, cx: Pc.x - (sp0.x * (1 - e)) / s, cy: Pc.y - (sp0.y * (1 - e)) / s };
  }
  const camT = (cam, dx = 0) => [cam.s, 0, 0, cam.s, W / 2 - cam.cx * cam.s + dx, H / 2 - cam.cy * cam.s];
  let horseBuf;
  function plateScene(ctx, mctx, t, g) {
    const cam = plateCam(t), gu = t - KG.enter;
    ctx.setTransform(...camT(cam));
    ctx.drawImage(M.stills.plate, 0, 0, PW, PH);
    if (gu >= 0) PANELS.forEach((p, k) => M.drawCover(ctx, M.frameAt("gallop", gu, gallopOff(k), "wrap"), p, PZ));
    ctx.setTransform(1, 0, 0, 1, 0, 0);
    if (t < KR.enter) return;
    const v = t - KR.enter;
    const xs = lerp(-60, W + 60, ease.outCubic(prog(v, 0, 0.2)));     // the background goes on the enter, in 0.2 s
    ctx.save(); ctx.beginPath(); ctx.rect(0, 0, Math.max(0, xs), H); ctx.clip();
    ctx.fillStyle = "#f1efea"; ctx.fillRect(0, 0, W, H); ctx.fillStyle = "#cdc8bf";
    for (let y = 0; y < H; y += 40) for (let x = (y / 40) % 2 ? 40 : 0; x < W; x += 80) ctx.fillRect(x, y, 40, 40);
    if (!horseBuf) horseBuf = M.canvas();
    const hb = horseBuf.getContext("2d");
    hb.setTransform(1, 0, 0, 1, 0, 0); hb.clearRect(0, 0, W, H); hb.setTransform(...camT(cam));
    hb.save(); hb.beginPath(); hb.rect(heroP.x - 40, heroP.y - 40, heroP.w + 40 - 16, heroP.h + 80); hb.clip();   // frames 37-39 of the matte are opaque at their right edge
    M.drawCover(hb, M.frameAt("gallop", gu, gallopOff(HERO), "wrap"), heroP, PZ);
    hb.globalCompositeOperation = "destination-in"; M.drawCover(hb, M.frameAt("horse", gu, gallopOff(HERO), "wrap"), heroP, PZ);
    hb.globalCompositeOperation = "source-over"; hb.restore(); ctx.drawImage(horseBuf, 0, 0); ctx.restore();
    if (xs < W + 50) { mctx.lineWidth = 16; mctx.beginPath(); mctx.moveTo(xs, -30); mctx.lineTo(xs, H + 30); mctx.stroke(); }
  }

  // ------------------------------------------------------------------ the moon, under Armstrong's whole line
  // the step (the live broadcast: he comes down the ladder), then the flag from the beat his line rises out of the bar;
  // both push in slowly, framed above the bar. On "mankind." the Earth comes up over the moon, in colour: everyone he
  // said it for, and the camera dives into it for the name
  // the broadcast's greys are lifted so the ladder and his boot read, but its whites stay under bone (they are clipped in
  // the broadcast, flat); the flag plate is a grey 480-line transfer whose gamma sinks the regolith toward ink so the
  // suits read as bone
  const STEP_GRADE = { contrast: 0.82, sat: 0.0, warm: 1, gamma: 0.72 }, STEP_EXPOSURE = 0.84;
  const FLAG_GRADE = { contrast: 1.2, sat: 0.0, warm: 1, gamma: 1.45 };
  // the Earth is the first colour, in the film's world (warm blacks, bone highlights, no clipped cyan)
  const COLOUR_GRADE = { contrast: 0.95, sat: 0.65, warm: 0.88, gamma: 1.12 };
  const TR = TM.kills.find((x) => x.kind === "translate"), EARTH_AT = TR.live.earth;
  const moonGrade = (t) => (t < TR.live.rise ? STEP_GRADE : t < EARTH_AT ? FLAG_GRADE : COLOUR_GRADE);
  // the plates are 30 fps film: at 60 fps each frame is blended with the next, so a refilled drop is not a jolt
  function plate(ctx, name, u, z, fx, fy, r = full) {
    M.drawCover(ctx, M.frameAt(name, u, 0, "hold"), r, z, fx, fy);
    const a = u * 30 - Math.floor(u * 30 + 1e-6);
    if (a > 0.01 && u > 0) { ctx.globalAlpha = a; M.drawCover(ctx, M.frameAt(name, u + 1 / 30, 0, "hold"), r, z, fx, fy); ctx.globalAlpha = 1; }
  }
  // a plate raised by `lift` px falls off to ink under it, over `fall` px
  function raised(ctx, name, u, z, fx, fy, lift, fall = 150) {
    ctx.fillStyle = "#000"; ctx.fillRect(0, 0, W, H);
    plate(ctx, name, u, z, fx, fy, { x: 0, y: -lift, w: W, h: H });
    const fg = ctx.createLinearGradient(0, H - lift - fall, 0, H - lift);
    fg.addColorStop(0, "rgba(0,0,0,0)"); fg.addColorStop(1, "rgba(0,0,0,1)");
    ctx.fillStyle = fg; ctx.fillRect(0, H - lift - fall, W, lift + fall);
  }
  // the step is framed high, so his boot comes down above the bar
  const stepPlate = (ctx, u, z) => raised(ctx, "step", u, z, 0.56, 0.9, 150);
  // Earthrise in two layers split at the lunar horizon, so the Earth can rise behind it. EARTH_LIT: the centre of its lit
  // disc (cx, cy, r), as fractions of the scan (measured on assets/img/earthrise.jpg)
  const EARTH = {}, EARTH_LIT = { cx: 0.567, cy: 0.535, r: 0.075 }, DIVE = { z: 2.4, x: -0.1, y: 0.3 };
  function earthLayers(im) {
    const n = im.naturalWidth, c = M.canvas(n, n), x = c.getContext("2d");
    x.drawImage(im, 0, 0);
    const d = x.getImageData(0, 0, n, n), px = d.data, hz = new Float32Array(n);
    for (let i = 0; i < n; i++) {
      let y = Math.floor(n * 0.66);
      while (y < n - 1 && px[(y * n + i) * 4 + 1] < 34) y++;
      hz[i] = y;
    }
    for (let i = 1; i < n - 1; i++) hz[i] = Math.min(hz[i - 1] + 2, hz[i], hz[i + 1] + 2);
    const sky = M.canvas(n, n), sx = sky.getContext("2d"), ground = M.canvas(n, n), gx = ground.getContext("2d");
    const sd = sx.createImageData(n, n), gd = gx.createImageData(n, n);
    for (let y = 0; y < n; y++) for (let i = 0; i < n; i++) {
      const k = (y * n + i) * 4, a = clamp((y - hz[i] + 3) / 6);
      for (let ch = 0; ch < 3; ch++) { sd.data[k + ch] = px[k + ch] * (1 - a); gd.data[k + ch] = px[k + ch]; }
      sd.data[k + 3] = 255; gd.data[k + 3] = Math.round(a * 255);
    }
    sx.putImageData(sd, 0, 0); gx.putImageData(gd, 0, 0);
    Object.assign(EARTH, { sky, ground });
  }
  function moon(ctx, t, g) {
    const rise = TR.live.rise;
    if (t < rise) { const u = t - TR.enter; stepPlate(ctx, u, lerp(1.0, 1.1, prog(u, 0, rise - TR.enter))); }
    else if (t < EARTH_AT) {   // the camera drifts with the one who steps back from the flag, and holds them both through the line
      const u = t - rise;
      plate(ctx, "flag", u, lerp(1.06, 1.1, prog(u, 0, TM.logo + 2.6 - rise)), lerp(0.49, 0.6, ease.inOutCubic(prog(u, 0.8, EARTH_AT - rise))), 0.52);
    } else {   // the Earth carries the frame, over the lunar horizon low under the bar. The camera pushes in through the shot
      // while the Earth rises a little behind the horizon; its centre sits above the line, as (EX, EY) px. From the
      // arrival the camera dives at it, gathering speed into the cut, and brings its lit side over the name (DIVE: where
      // its centre lands, in radii from the frame's centre); through the cut it keeps closing, inside the name
      const p = prog(t, EARTH_AT, TM.arrive), k = ease.inQuad(prog(t, TM.arrive, TM.logo)), v = ease.outCubic(prog(t, TM.logo, TM.ignite));
      const lift = 0.02 * p * (1 - k);
      const z = lerp(1.9, 2.3, p) * lerp(1, DIVE.z, k) * lerp(1, 1.12, v), r0 = EARTH_LIT.r * W * z;
      const EX = lerp(980, W / 2 + DIVE.x * r0, k), EY = lerp(lerp(400, 380, p), H / 2 + DIVE.y * r0, k);
      const fx = EARTH_LIT.cx - (EX - W / 2) / (W * z), fy = EARTH_LIT.cy - (EY - H / 2 + lift * H * z) / (W * z);
      ctx.fillStyle = "#000"; ctx.fillRect(0, 0, W, H);
      // the scan's limb is sharper than anything else in the shot: soften it to the plate's own focus, with a faint
      // atmosphere, so the Earth sits in the photograph instead of on it
      ctx.filter = "blur(0.6px)";
      M.drawCover(ctx, EARTH.sky, { x: 0, y: -lift * H * z, w: W, h: H }, z, fx, fy);
      ctx.filter = "none";
      const at = M.coverMap(EARTH.sky.width, EARTH.sky.height, { x: 0, y: -lift * H * z, w: W, h: H }, z, fx, fy)(EARTH_LIT.cx * EARTH.sky.width, EARTH_LIT.cy * EARTH.sky.height);
      const r = EARTH_LIT.r * EARTH.sky.width * Math.max(W, H) / EARTH.sky.width * z;
      const halo = ctx.createRadialGradient(at.x, at.y, r * 0.96, at.x, at.y, r * 1.12);
      halo.addColorStop(0, "rgba(120,160,220,0.16)"); halo.addColorStop(1, "rgba(120,160,220,0)");
      ctx.globalCompositeOperation = "screen"; ctx.fillStyle = halo; ctx.fillRect(0, 0, W, H); ctx.globalCompositeOperation = "source-over";
      M.drawCover(ctx, EARTH.ground, full, z, fx, fy);
    }
    if (g) Object.assign(g, moonGrade(t));
  }
  // under the bar and its translation every plate falls off to ink, so the lines read over any picture
  function scrim(ctx) {
    const sg = ctx.createLinearGradient(0, 540, 0, H);
    sg.addColorStop(0, "rgba(0,0,0,0)"); sg.addColorStop(0.32, "rgba(0,0,0,0.62)"); sg.addColorStop(0.55, "rgba(0,0,0,0.8)"); sg.addColorStop(1, "rgba(0,0,0,0.86)");
    ctx.fillStyle = sg; ctx.fillRect(0, 540, W, H - 540);
  }

  // ------------------------------------------------------------------ the logo: back through tiles that hold the whole film
  const WM = window.WORDMARK;
  let minX = 1e9, maxX = -1e9, minY = 1e9, maxY = -1e9;
  for (const c of WM) for (const poly of c.p) for (const [x, y] of poly) { minX = Math.min(minX, x); maxX = Math.max(maxX, x); minY = Math.min(minY, y); maxY = Math.max(maxY, y); }
  const LS = 1460 / (maxX - minX), LCX = (minX + maxX) / 2, LCY = (minY + maxY) / 2;
  const FILM_CLIPS = ["typists", "operator", "telegraph", "console", "ignition", "ascent", "gallop", "aldrin", "arrival", "reels", "ticker",
    "drawers", "teleprinter", "moonface", "crowd", "flag", "smith", "cards", "capsule", "card"];
  const LOGO_H = maxY - minY;
  // the name as one solid shape: the gaps between its tiles closed by a stroke, so no seam crosses it
  const namePath = (ctx) => {
    ctx.beginPath();
    for (const c of WM) for (const poly of c.p) { poly.forEach(([a, b], j) => (j ? ctx.lineTo(a, b) : ctx.moveTo(a, b))); ctx.closePath(); }
    ctx.fillStyle = ctx.strokeStyle = "#fff"; ctx.lineJoin = "round"; ctx.lineWidth = LOGO_H * 0.022; ctx.fill(); ctx.stroke();
  };
  // the caret lights as the line lands and waits, steady, until it goes out on the Quindar out-tone's frame.
  // Before that it is the bar's caret, which brought the name: lit from the cut until the ignition swallows it
  const caretAt = (t) => (t < TM.ignite ? 1 : t >= TM.press && t < TM.signOff ? 1 + 0.8 * Math.exp(-(t - TM.press) / 0.12) : 0);
  // where the name settles, so the line fits under it (type.js card)
  const SETTLE_S = 0.8, SETTLE_Y = 470;
  // the cut lands on the whole word, a little small; the ignition knocks it back and up to make room, and it slows as it
  // cools. Its caret sits after the name
  function logoAt(t) {
    const u = t - TM.logo, ig = TM.ignite - TM.logo, up = ease.outCubic(prog(u, ig, ig + 0.8));
    const z = lerp(0.9, 1, ease.outCubic(prog(u, 0, 0.9))) * lerp(1, SETTLE_S, up);
    const s = LS * z, cy = lerp(H / 2, SETTLE_Y, up), ch = LOGO_H * s * 0.95, cw = ch * 0.1;
    return { u, ig, z, s, cy, caret: [(maxX - LCX) * s + W / 2 + LOGO_H * s * 0.06 + cw / 2, ((minY + maxY) / 2 - LCY) * s + cy, cw, ch] };
  }
  // until it ignites, the name glows in the caret's molten orange (gl.js), then the heat takes it
  function logo(mk, t) {
    const L = logoAt(t);
    mk.setTransform(1, 0, 0, 1, 0, 0); mk.fillStyle = "#000"; mk.fillRect(0, 0, W, H);
    mk.setTransform(L.s, 0, 0, L.s, W / 2 - LCX * L.s, L.cy - LCY * L.s);
    namePath(mk);
    return { t: L.u - L.ig, caretOn: caretAt(t), caret: L.caret, xf: [W / 2 - LCX * L.s, L.cy - LCY * L.s, L.z] };
  }
  // the bar's caret leaves it, lit, and the bar and its line let go behind it: it flies up to where the name will be,
  // growing into the name's caret, and the name is cast beside it on the cut (gl.js draws it from then on). It flies
  // over the bar as its own element, so the bar's glass never dims it
  function handoff(el, t, r) {
    if (t < TR.live.letGo || t >= TM.logo) { el.style.visibility = "hidden"; return; }
    const p = ease.inOutCubic(prog(t, TR.live.letGo, TM.logo)), [x, y, w, h] = logoAt(TM.logo).caret;
    const cw = lerp(r.width, w, p), ch = lerp(r.height, h, p);
    Object.assign(el.style, { visibility: "visible", width: `${cw}px`, height: `${ch}px`,
      transform: `translate(${(lerp(r.x + r.width / 2, x, p) - cw / 2).toFixed(1)}px, ${(lerp(r.y + r.height / 2, y, p) - ch / 2).toFixed(1)}px)` });
  }

  // ------------------------------------------------------------------ build
  async function build() {
    const ANS = TM.kills.find((x) => x.kind === "translate").live.answers;
    await Promise.all([["500 100px 'Plex Mono'", "Aa0"], ["600 100px 'Plex Mono'", "Aa0"], ["600 100px Geist", "Aa0"], ["500 100px 'Plex JP'", "人間にとっては小さな一歩だが日本語"],
      ...ANS.map((l) => [`500 40px '${l.font}'`, l.text])].map(([f, txt]) => document.fonts.load(f, txt)));
    const clips = new Set(["pour", "aldrin", "flag", "step", "arrival", "gallop", ...ANS.map((a) => a.who), ...TM.words1.map((w) => w[2]), ...TM.apps.map((a) => a[1]), ...FILM_CLIPS]);
    await Promise.all([
      M.load([...clips].filter((n) => window.SEQ[n])), M.load(["horse"], "png"),
      M.still("plate", "assets/img/plate.jpg"), M.still("earthrise", "assets/img/earthrise.jpg"), M.still("tvoff", "assets/img/tv/tv-off.jpg"), M.still("tvlit", "assets/img/tv/tv-lit.jpg"),
    ]);
    const plates = { off: M.stills.tvoff, lit: M.stills.tvlit };
    earthLayers(M.stills.earthrise);
    const barTex = barCanvas();
    const sc = M.canvas(), ctx = sc.getContext("2d");
    const atlas = M.canvas(), actx = atlas.getContext("2d");
    const lmask = M.canvas(), lmk = lmask.getContext("2d");
    const mc = M.metalCanvas();
    const els = { answers: document.getElementById("answers"), bar: document.getElementById("bar"), calc: document.getElementById("calc"), small: document.getElementById("calcsmall") };
    els.caret = els.bar.querySelector(".caret"); els.fly = document.getElementById("fly");
    els.tag = document.getElementById("tag");
    const KK = Object.fromEntries(TM.kills.map((k) => [k.kind, k]));
    const tileTree = M.splitTree([1, 1, 2, 3, 4].map((k, i) => ({ t: KK.tile.enter + i * 0.04, k })), 61, { x: 14, y: 44, w: W - 28, h: H - 58 });   // splits on the enter, resolved in 0.35 s
    // a result holds until the next command's enter replaces it; the next command is typed over it
    const until = Object.fromEntries(TM.kills.map((k, i) => { const n = TM.kills[i + 1]; return [k.kind, n ? n.enter : TM.logo]; }));
    const TILE_TITLES = ["Notes", "Archive", "Mail", "Photos", "Preview", "Calendar", "Messages", "Music", "Finder", "Safari", "Maps", "Terminal", "Pages", "Keynote"];
    const TILE_CLIPS = ["typists", "operator", "telegraph", "console", "gallop", "aldrin", "arrival", "reels", "ticker", "drawers", "moonface", "crowd", "flag", "capsule"];
    const barT = { glass: TM.glass, bardown: TM.bardown, logo: TM.logo, letGo: KK.translate.live.letGo, gone: KK.translate.live.gone, line3: TM.line3, clear: KK.gif.flash, pulse: TM.pulse, arrive: TM.arrive, quindarIn: TM.quindarIn };

    window.L.on((t) => {
      const f = frame(t);
      const kill = TM.kills.find((k) => t >= k.flash && t < k.end);
      T.command(t, t >= TM.cmd0.show && t <= TM.cmd0.out + 0.14 ? TM.cmd0 : null);
      // Armstrong lives in the bar after the last enter (type.js live)
      // the live line stays in the bar while it leaves on the logo cut
      T.bar(els.bar, t, kill && t >= kill.t0 - 0.1 ? kill : t >= TM.logo ? KK.translate : null, barT);
      T.answers(els.answers, t, TM, KK.translate.live);
      handoff(els.fly, t, els.caret.getBoundingClientRect());
      T.card(els.tag, t, TM);
      const kc = KK.currency;
      const showCalc = t >= kc.enter && t < until.currency;
      T.reels(els.calc, showCalc ? t : -1, { from: "00.00", to: TM.rate, unitFrom: "eur", unitTo: "eur", t0: kc.enter, delay: 0, dur: 0.3 });
      els.small.style.visibility = showCalc ? "visible" : "hidden";

      ctx.setTransform(1, 0, 0, 1, 0, 0); ctx.fillStyle = "#050505"; ctx.fillRect(0, 0, W, H);
      const mctx = M.metalBegin();
      const g = { scene: sc, t, frame: f, seed: 3.7, heat: 0, flow: 0, pinch: 0, tilt: 0, zoom: 1, plates, amber: 1 };
      const cam = camAt(t);
      const jolt = t < TM.act2 ? strikeJolt(t) : 0;
      let tv = { cx: cam.cx, cy: cam.cy - jolt * 0.006, zoom: cam.zoom * (1 + 0.025 * jolt), scr, rad: RAD, barrel: 0.045, on: [0, 1, 1], amber: 0,
        overheat: ease.inCubic(prog(t, TM.heat0, WALL0 + 0.3)) * (1 - prog(t, WALL1, TM.meltCmd)) };
      tv.persp = perspAt(t);
      Object.assign(g, { archive: t < TM.act2 ? 1 : 0, haze: hazeAt(t, tv.overheat), embers: embersAt(t) });

      if (t < TM.act2) {
        act1(ctx, t);
        // each strike flares the tube; the Saturn V's ignition whites it out
        const k = wordAt(t), u = t - TM.words1[k][1];
        g.exposure = 1 + (k === 4 ? 0.9 * Math.exp(-u / 0.14) : 0.35 * Math.exp(-u / 0.05));
      }
      else if (t < TM.cast) {
        ctx.save(); ctx.beginPath(); ctx.rect(PIC.x, 0, PIC.w, PIC.h); ctx.clip(); act2(ctx, t); ctx.restore();
        if (t >= WALL0 - 0.05) { tv.box = BOX; drawAtlas(actx, t); g.atlas = atlas; }
        if (t < TM.meltCmd) g.exposure = lerp(1, 0.42, ease.inOutCubic(prog(t, TM.caretAlone - 0.1, TM.caretAlone + 0.25)));   // the world holds its breath under the verb
        else g.exposure = 1 + 1.4 * Math.exp(-(t - TM.meltCmd) / 0.1);    // the enter: every screen flares on its frame, and the fire spreads
        if (t >= MELT0) { tv.meltT = t - MELT0; wallDrips(mctx, t, cam); g.flowSpd2 = 9; }
        g.blurY = Math.min(140, vel(camY, t) * cam.zoom * H);   // a short shutter: longer, the burning screens smeared into streaks
      } else if (t < TM.settle + 0.06 && !kill) {
        // the casting: one river into Foundry's bar
        tv = null; g.amber = 0;
        const c = t - TM.cast, impY = (BAR.y + BAR.h / 2) / H, C = TM.cool;
        const tail = ease.inQuad(prog(c, 0.42, 0.62)) * impY;
        // the core of heat retreats from the middle of the bar to where the cursor lives, and shrinks to a caret
        const ce = ease.inOutCubic(prog(c, C.core0, C.core1));
        const CARET = { x: BAR.x + 82, y: BAR.y + BAR.h / 2 };
        const cool = [lerp(960, CARET.x, ce), CARET.y, Math.exp(lerp(Math.log(780), Math.log(7), ce)), Math.exp(lerp(Math.log(140), Math.log(30), ce))];
        const coolB = [ease.inOutCubic(prog(c, C.gap0, C.gap1)), 0,
          ease.inCubic(prog(c, C.knock0, C.knock1)), ease.inOutCubic(prog(c, C.flake0, C.flake1))];
        g.cast = { t: c, plate: ease.outCubic(prog(c, 0.0, 0.4)), iron: 1, tau: 0.5, cool, coolB,
          coreHeat: 1 - ease.inOutCubic(prog(t, TM.line3.t0 - 0.08, TM.line3.t0 + 0.02)),
          smoke: ease.inOutCubic(prog(c, 0.45, 0.9)) * (1 - ease.inOutCubic(prog(c, C.knock0, C.knock1 + 0.2))),
          fade: 1 - ease.inOutCubic(prog(t, TM.line3.t0, TM.line3.t0 + 0.2)),
          imp: [0.5, impY, 0.5, impY], stream: [tail, 1, 74, 0], impT: [0.0, 0.0] };
        Object.assign(g, { raw: 1, exposure: 1.04, logo: barTex, zoom: lerp(1.1, 1.0, ease.outCubic(prog(c, 0, 1.2))) });
        const vy = (x) => -0.6 * (1 - ease.outExpo(prog(x, TM.cast, TM.cast + 0.35)));
        g.blurY = Math.min(380, vel(vy, t) * H);
      } else if (t < TM.logo) {
        tv = null; g.amber = 0;
        // results, by whichever kill is running
        const cur = [...TM.kills].reverse().find((k) => t >= (k.kind === "translate" ? k.t0 : k.enter)) || KK.gif;
        if (cur.kind === "gif" || cur.kind === "rmbg") plateScene(ctx, mctx, t, g);
        else if (cur.kind === "translate") {
          moon(ctx, t, g); scrim(ctx);
          // the light answers the finished line: a flash on the frame it lands, then the picture keeps opening into the logo
          const v = t - TM.arrive;
          g.exposure = v >= 0 ? 1 + 0.22 * Math.exp(-v / 0.2) : t < TR.live.rise ? STEP_EXPOSURE : 1;
          // film grain over the 480-line plates: it hides their blocks; the soft plates get more, so it reads as texture.
          // The Earth and today's footage share one grain, so 1969 and 2026 sit in the same film
          g.grain = t < TR.live.rise ? 0.16 : 0.1;
        } else if (cur.kind === "currency") {
          ctx.fillStyle = "#0b0b0b"; ctx.fillRect(0, 0, W, H);
        } else if (cur.kind === "tile") {
          // a desktop: the wallpaper and the menu bar, and the windows snapping into a grid on it
          const dg = ctx.createLinearGradient(0, 0, W, H); dg.addColorStop(0, "#3a3430"); dg.addColorStop(1, "#141211");
          ctx.fillStyle = dg; ctx.fillRect(0, 0, W, H);
          ctx.fillStyle = "rgba(20,20,22,0.85)"; ctx.fillRect(0, 0, W, 34);
          ctx.fillStyle = "#f1efea"; ctx.font = `600 19px Geist`; ctx.textAlign = "left"; ctx.textBaseline = "middle"; ctx.fillText("Foundry", 52, 18);
          ctx.beginPath(); ctx.arc(28, 17, 8, 0, Math.PI * 2); ctx.fill();
          for (const r of M.layout(tileTree, t, 18)) drawWindow(ctx, { title: TILE_TITLES[r.id % TILE_TITLES.length], clip: TILE_CLIPS[r.id % TILE_CLIPS.length], off: r.id * 7 }, r, t, 1, 44);
        } else {
          const kd = KK.download, u = t - kd.enter, kEnd = until.download;
          ctx.fillStyle = "#070707"; ctx.fillRect(0, 0, W, H);
          if (u >= 0) {
            // the download opens out of the bar and plays
            const a = ease.outExpo(prog(u, 0, 0.24));
            const DB = T.DOCK, push = 1 + 0.04 * ease.inOutCubic(prog(u, 0.2, kEnd - kd.enter));
            const w = lerp(DB.w, 1320, a) * push, h = lerp(DB.h, 744, a) * push;
            const cy = lerp(DB.cy, 420, a);
            const r = { x: W / 2 - w / 2, y: cy - h / 2, w, h };
            ctx.save(); ctx.shadowColor = "rgba(0,0,0,0.7)"; ctx.shadowBlur = 60; ctx.shadowOffsetY = 24;
            ctx.fillStyle = "#000"; M.roundRect(ctx, r.x, r.y, r.w, r.h, lerp(62, 18, a)); ctx.fill(); ctx.shadowColor = "transparent";
            M.roundRect(ctx, r.x, r.y, r.w, r.h, lerp(62, 18, a)); ctx.clip();
            // the 30 fps film at 1.3 speed, each frame blended with the next; the print jumps between its frames 60 and 61,
            // which read as a cut with no sound: at this speed the moon comes first (frame 57)
            const fu = (Math.max(0, u) * 1.3 + 0.3) * 30, fa = fu - Math.floor(fu);
            M.drawCover(ctx, M.frameAt("arrival", Math.floor(fu) / 30, 0, "hold"), r, 1.02);
            if (fa > 0.01) { ctx.globalAlpha = fa; M.drawCover(ctx, M.frameAt("arrival", (Math.floor(fu) + 1) / 30, 0, "hold"), r, 1.02); ctx.globalAlpha = 1; }
            ctx.restore();
            ctx.save(); ctx.strokeStyle = "rgba(255,255,255,0.16)"; ctx.lineWidth = 1.5; M.roundRect(ctx, r.x + 0.75, r.y + 0.75, r.w - 1.5, r.h - 1.5, lerp(62, 18, a)); ctx.stroke(); ctx.restore();
          }
        }
        // while a command is typed the picture waits, dimmed; enter releases it
        if (kill && t < kill.enter) {
          const d = ease.outCubic(prog(t, kill.flash, kill.flash + (kill.kind === "gif" ? 0.12 : 0.034)));   // on the first key; released on the enter frame
          ctx.fillStyle = `rgba(0,0,0,${(0.34 * d).toFixed(3)})`; ctx.fillRect(0, 0, W, H);
        }
      } else {
        tv = null; g.amber = 0;
        // until it ignites, the name is a window onto the Earth, over a dim bone fill so its letters still read on the black
        // sky; the ignition takes it, and the colour drains into the film's own black and white as the iron cools
        g.logoCast = logo(lmk, t); g.logo = lmask; g.logoLive = true;
        ctx.fillStyle = "#000"; ctx.fillRect(0, 0, W, H);
        if (t < TM.ignite + 0.6) {
          moon(ctx, t);
          ctx.globalCompositeOperation = "lighten"; ctx.fillStyle = "#3a3631"; ctx.fillRect(0, 0, W, H);
          ctx.globalCompositeOperation = "multiply"; ctx.drawImage(lmask, 0, 0, W, H); ctx.globalCompositeOperation = "source-over";
        }
        const k = ease.inOutCubic(prog(t, TM.ignite, TM.ignite + 0.35));
        for (const key of ["contrast", "sat", "warm", "gamma"]) g[key] = lerp(COLOUR_GRADE[key], FLAG_GRADE[key], k);
        g.exposure = 1 + 0.3 * Math.exp(-(t - TM.logo) / 0.07);            // the cut lands with the hit

      }

      g.tv = tv;
      // the bar is glass over the results (gl.js frosts what is behind it); its caret is a light
      const bs = els.bar.style;
      if (!tv && t >= TM.settle && bs.visibility === "visible" && parseFloat(bs.opacity) > 0.5) {
        const cr = els.caret.getBoundingClientRect(), h = parseFloat(bs.height);
        g.bar = { x: parseFloat(bs.left), y: parseFloat(bs.top), w: parseFloat(bs.width), h, r: h / 2,
          cx: cr.x + cr.width / 2, cy: cr.y + cr.height / 2, con: parseFloat(els.caret.style.opacity || "0") };
      }
      g.metal = M.metalEnd(mc);
      window.GL.draw(g);
    });

    const tl = gsap.timeline({ paused: true });
    tl.to(window.L.clock, { t: D, duration: D, ease: "none" }, 0);
    tl.seek(0);
    return { tl };
  }
  window.FILM = build();
})();
