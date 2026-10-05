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
  const MELT0 = TM.meltCmd + 0.05;               // ignition, after 3 frames of nothing
  const camZoom = (t) => {
    if (t < WALL0) return lerp(2.2, 2.3, ease.inOutCubic(prog(t, 0, WALL0)));
    if (t < WALL1) return Math.exp(lerp(Math.log(2.3), Math.log(0.15), ease.inOutCubic(prog(t, WALL0, WALL1))));
    return seg(t, [[WALL1, 0.15], [RIV0, 0.138], [RIV1, 0.5, ease.inCubic]]);
  };
  const camY = (t) => seg(t, [[RIV0, 0.5], [RIV1, 3.1, ease.inCubic]]);
  const camAt = (t) => ({ cx: 0.5, cy: camY(t), zoom: camZoom(t) });
  const toOut = (c, x, y) => ({ x: ((x - c.cx) * c.zoom + 0.5) * W, y: ((y - c.cy) * c.zoom + 0.5) * H });

  function tubeText(ctx, str, x, y, size, align = "left", alpha = 1, weight = 600) {
    if (!str) return;
    ctx.save(); ctx.font = `${weight} ${size}px ${MONO}`; ctx.textAlign = align; ctx.textBaseline = "alphabetic";
    ctx.globalAlpha = alpha; ctx.shadowColor = "rgba(0,0,0,0.85)"; ctx.shadowBlur = size * 0.3; ctx.fillStyle = "#fff"; ctx.fillText(str, x, y); ctx.restore();
  }

  // ------------------------------------------------------------------ Act I: struck by a typewriter, a machine per word
  const LINES1 = [["A", "machine"], ["for", "every"], ["job."]];
  function act1(ctx, t) {
    const W1 = TM.words1;
    let k = 0; for (let i = 0; i < W1.length; i++) if (t >= W1[i][1]) k = i;
    const [, t0, clip] = W1[k], u = t - t0;
    M.drawCover(ctx, M.frameAt(clip, u, 0, "hold"), PIC, 1.06 + u * 0.12, 0.5, 0.5);
    ctx.fillStyle = "rgba(0,0,0,0.42)"; ctx.fillRect(PIC.x, 0, PIC.w, PIC.h);
    // the words: each strikes whole; every letter sits a little off, the way type bars land
    const size = 196;
    ctx.save(); ctx.font = `600 ${size}px ${MONO}`; const cw = ctx.measureText("M").width; ctx.restore();
    let wi = 0;
    LINES1.forEach((line, li) => {
      let col = 0;
      line.forEach((word) => {
        const [w, wt] = W1[wi++];
        if (t >= wt) {
          const p = clamp((t - wt) * 30);
          [...w].forEach((ch, ci) => {
            const r = hash(wi * 31 + ci * 7);
            const x = PIC.x + 110 + (col + ci) * cw, y = PIC.h * [0.33, 0.56, 0.79][li] + (r - 0.5) * 8 - (1 - p) * 12;
            tubeText(ctx, ch, x, y, size, "left", (0.82 + 0.18 * hash(ci * 13 + wi)) * Math.min(1, p * 2));
          });
        }
        col += w.length + 1;
      });
    });
  }
  // the tube jolts a few pixels on each strike
  const strikeJolt = (t) => TM.words1.reduce((a, [, wt]) => a + (t >= wt ? Math.exp(-(t - wt) / 0.035) : 0), 0);

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
    ctx.fillStyle = "#f4f4f4"; ctx.font = `500 ${Math.round(bar * 0.42)}px ${MONO}`; ctx.textAlign = "center"; ctx.textBaseline = "middle";
    ctx.fillText(M.ellipsize(ctx, a.title, r.w - bar * 3.0), r.x + r.w / 2 + bar * 0.45, r.y + bar / 2 + 1);
    ctx.restore(); ctx.restore();
  }
  const APPS = TM.apps.map(([title, clip], i) => {
    const r = rng(900 + i * 17);
    const hero = i < 3;
    const w = hero ? 1180 : 420 + r() * 300, h = hero ? 660 : 280 + r() * 200;
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
      drawWindow(ctx, a, { x: a.x + a.w * (1 - sc) / 2, y: a.y + a.h * (1 - sc) / 2, w: a.w * sc, h: a.h * sc }, t, clamp(p * 1.4), a.w > 900 ? 72 : undefined);
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
      const dl = h21(i + 1.7, j + 1.7) * 0.5 + Math.hypot(i, j) * 0.025;
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
  const S1 = (W * 1.03) / heroP.w, PZ = 1.09, gallopOff = (k) => k * 3.25;
  const KG = TM.kills[0], KR = TM.kills[1];
  function plateCam(t) {
    const e = ease.inOutCubic(prog(t, KG.enter + 0.18, KG.enter + 0.6));
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
    const xs = lerp(-60, W + 60, ease.inOutCubic(prog(v, 0, 0.3)));
    const boltF = (x) => 2300 * ease.inExpo(prog(x, 0.42, 0.72));
    ctx.save(); ctx.beginPath(); ctx.rect(0, 0, Math.max(0, xs), H); ctx.clip();
    ctx.fillStyle = "#f1efea"; ctx.fillRect(0, 0, W, H); ctx.fillStyle = "#cdc8bf";
    for (let y = 0; y < H; y += 40) for (let x = (y / 40) % 2 ? 40 : 0; x < W; x += 80) ctx.fillRect(x, y, 40, 40);
    if (!horseBuf) horseBuf = M.canvas();
    const hb = horseBuf.getContext("2d");
    hb.setTransform(1, 0, 0, 1, 0, 0); hb.clearRect(0, 0, W, H); hb.setTransform(...camT(cam, boltF(v)));
    M.drawCover(hb, M.frameAt("gallop", gu, gallopOff(HERO), "wrap"), heroP, PZ);
    hb.globalCompositeOperation = "destination-in"; M.drawCover(hb, M.frameAt("horse", gu, gallopOff(HERO), "wrap"), heroP, PZ);
    hb.globalCompositeOperation = "source-over"; ctx.drawImage(horseBuf, 0, 0); ctx.restore();
    g.blurX = Math.min(500, vel(boltF, v));
    if (xs < W + 50) { mctx.lineWidth = 16; mctx.beginPath(); mctx.moveTo(xs, -30); mctx.lineTo(xs, H + 30); mctx.stroke(); }
  }

  // ------------------------------------------------------------------ the logo: back through tiles that hold the whole film
  const WM = window.WORDMARK;
  let minX = 1e9, maxX = -1e9, minY = 1e9, maxY = -1e9;
  for (const c of WM) for (const poly of c.p) for (const [x, y] of poly) { minX = Math.min(minX, x); maxX = Math.max(maxX, x); minY = Math.min(minY, y); maxY = Math.max(maxY, y); }
  const LS = 1460 / (maxX - minX), LCX = (minX + maxX) / 2, LCY = (minY + maxY) / 2;
  const CELLS = WM.map((c, i) => {
    let cx = 0, cy = 0, x0 = 1e9, x1 = -1e9, y0 = 1e9, y1 = -1e9;
    for (const [a, b] of c.p[0]) { cx += a; cy += b; x0 = Math.min(x0, a); x1 = Math.max(x1, a); y0 = Math.min(y0, b); y1 = Math.max(y1, b); }
    return { ...c, cx: cx / c.p[0].length, cy: cy / c.p[0].length, x0, x1, y0, y1, r: hash(i * 7 + 3) };
  });
  const FILM_CLIPS = ["typists", "operator", "telegraph", "console", "ignition", "ascent", "gallop", "aldrin", "arrival", "reels", "ticker",
    "drawers", "teleprinter", "moonface", "crowd", "flag", "smith", "cards", "capsule", "card"];
  const focus = (() => { let best = CELLS[0], bd = 1e9; for (const c of CELLS) { const d = Math.abs(c.cx - (LCX + 60)) + Math.abs(c.cy - LCY) * 2; if (d < bd && c.p[0].length <= 5) { bd = d; best = c; } } return best; })();
  const cellPath = (ctx, cell) => { for (const poly of cell.p) { poly.forEach(([a, b], j) => (j ? ctx.lineTo(a, b) : ctx.moveTo(a, b))); ctx.closePath(); } };
  function logo(ctx, t) {
    const u = t - TM.logo;
    const e = ease.inOutCubic(prog(u, 0.0, 0.82));
    const z = Math.exp(lerp(Math.log(46), 0, e));
    const fx = lerp(focus.cx, LCX, e), fy = lerp(focus.cy, LCY, e), s = LS * z;
    const TX = (x) => (x - fx) * s + W / 2, TY = (y) => (y - fy) * s + H / 2;
    for (const c of CELLS) {
      const bx0 = TX(c.x0), bx1 = TX(c.x1), by0 = TY(c.y0), by1 = TY(c.y1);
      if (bx1 < 0 || bx0 > W || by1 < 0 || by0 > H) continue;
      ctx.save();
      ctx.setTransform(s, 0, 0, s, W / 2 - fx * s, H / 2 - fy * s);
      ctx.beginPath(); cellPath(ctx, c); ctx.clip();
      ctx.setTransform(1, 0, 0, 1, 0, 0);
      // every tile is the train that just came at you; then one wave cools them to bone, left to right
      M.drawCover(ctx, M.frameAt("arrival", 2.9, 0, "hold"), full, 1.02);
      const fx_ = (c.cx - minX) / (maxX - minX);
      const k = ease.inOutCubic(prog(u, 0.62 + fx_ * 0.42, 0.86 + fx_ * 0.42));
      if (k > 0) { ctx.fillStyle = `rgba(241,239,234,${k.toFixed(3)})`; ctx.fillRect(bx0 - 1, by0 - 1, bx1 - bx0 + 2, by1 - by0 + 2); }
      ctx.restore();
    }
  }

  // ------------------------------------------------------------------ build
  async function build() {
    await Promise.all(["500 100px 'Plex Mono'", "600 100px 'Plex Mono'", "600 100px 'Noto JP'"]
      .map((f) => document.fonts.load(f, f.includes("JP") ? "人間にとっては小さな一歩だが" : "Aa0")));
    const clips = new Set(["pour", "aldrin", "flag", "arrival", "gallop", ...TM.words1.map((w) => w[2]), ...TM.apps.map((a) => a[1]), ...FILM_CLIPS]);
    await Promise.all([
      M.load([...clips].filter((n) => window.SEQ[n])), M.load(["horse"], "png"),
      M.still("plate", "assets/img/plate.jpg"), M.still("tvoff", "assets/img/tv/tv-off.jpg"), M.still("tvlit", "assets/img/tv/tv-lit.jpg"),
    ]);
    const plates = { off: M.stills.tvoff, lit: M.stills.tvlit };
    const barTex = barCanvas();
    const KW = { x: 340, y: 150, w: 1240, h: 640 };          // where a killed app reappears
    // a killed app burns outward from its close button
    const killEdge = (() => {
      const c = M.canvas(W / 4, H / 4), x = c.getContext("2d"), img = x.createImageData(c.width, c.height);
      const ox = KW.x + 40, oy = KW.y + 40, reach = Math.hypot(KW.w, KW.h) * 0.75;
      for (let py = 0; py < c.height; py++) for (let px_ = 0; px_ < c.width; px_++) {
        const X = (px_ + 0.5) * 4, Y = (py + 0.5) * 4, o = (py * c.width + px_) * 4;
        const inside = X >= KW.x && X < KW.x + KW.w && Y >= KW.y && Y < KW.y + KW.h;
        img.data[o] = Math.round(255 * clamp(1 - Math.hypot(X - ox, Y - oy) / reach)); img.data[o + 2] = inside ? 255 : 0; img.data[o + 3] = 255;
      }
      x.putImageData(img, 0, 0); return c;
    })();
    const sc = M.canvas(), ctx = sc.getContext("2d");
    const atlas = M.canvas(), actx = atlas.getContext("2d");
    const mc = M.metalCanvas();
    const els = { capA: document.getElementById("capA"), capB: document.getElementById("capB"), bar: document.getElementById("bar"), calc: document.getElementById("calc"), small: document.getElementById("calcsmall") };
    const tileTree = M.splitTree([0, 1, 1, 2, 3, 5].map((k, i) => ({ t: TM.kills[4].enter + i * 0.07, k: Math.max(1, k) })), 61);
    const TILE_CLIPS = ["typists", "operator", "telegraph", "console", "gallop", "aldrin", "arrival", "reels", "ticker", "drawers", "moonface", "crowd", "flag", "capsule"];
    const barT = { glass: TM.glass, bardown: TM.settle, logo: TM.logo, line3: TM.line3 };

    window.L.on((t) => {
      const f = frame(t);
      const kill = TM.kills.find((k) => t >= k.flash && t < k.end);
      T.command(t, t >= TM.cmd0.t0 - 0.12 && t <= TM.cmd0.out + 0.14 ? TM.cmd0 : null);
      T.bar(els.bar, t, kill && t >= kill.t0 - 0.1 ? kill : null, barT);
      const ktr = TM.kills[2];
      if (t >= ktr.enter && t < ktr.end + 0.05) {
        T.caption(els.capA, t, { words: TM.wordsA, at: TM.translateA, dur: 0.28, to: "人間にとっては小さな一歩だが、", toFont: "'Noto JP'", pool: "人間一歩小さな偉大飛躍だがとはにっ" });
        els.capA.style.opacity = String(1 - ease.inCubic(prog(t, ktr.end - 0.08, ktr.end + 0.05)));
      } else els.capA.style.visibility = "hidden";
      els.capB.style.visibility = "hidden";
      const kc = TM.kills[3];
      T.reels(els.calc, t >= kc.enter && t < kc.end ? t : -1, { from: "00.00", to: TM.rate, unitFrom: "eur", unitTo: "eur", t0: kc.enter, delay: 0.02, dur: 0.3 });
      els.small.style.visibility = t >= kc.enter && t < kc.end ? "visible" : "hidden";

      ctx.setTransform(1, 0, 0, 1, 0, 0); ctx.fillStyle = "#050505"; ctx.fillRect(0, 0, W, H);
      const mctx = M.metalBegin();
      const g = { scene: sc, t, frame: f, seed: 3.7, heat: 0, flow: 0, pinch: 0, tilt: 0, zoom: 1, plates, amber: 1 };
      const cam = camAt(t);
      const jolt = t < TM.act2 ? strikeJolt(t) : 0;
      let tv = { cx: cam.cx, cy: cam.cy - jolt * 0.0025, zoom: cam.zoom, scr, rad: RAD, barrel: 0.045, on: [0, 1, 1], amber: 0,
        overheat: ease.inCubic(prog(t, TM.heat0, WALL0 + 0.3)) * (1 - prog(t, WALL1, TM.meltCmd)) };

      if (t < TM.act2) act1(ctx, t);
      else if (t < TM.cast) {
        ctx.save(); ctx.beginPath(); ctx.rect(PIC.x, 0, PIC.w, PIC.h); ctx.clip(); act2(ctx, t); ctx.restore();
        if (t >= WALL0 - 0.05) { tv.box = BOX; drawAtlas(actx, t); g.atlas = atlas; }
        if (t >= TM.meltCmd && t < MELT0) { g.fade = 0.0; }                    // three frames of nothing
        if (t >= MELT0) { tv.meltT = t - MELT0; wallDrips(mctx, t, cam); g.flowSpd2 = 9; }
        g.blurY = Math.min(420, vel(camY, t) * cam.zoom * H);
      } else if (t < TM.settle + 0.06 && !kill) {
        // the casting: one river into Foundry's bar
        tv = null; g.amber = 0;
        const c = t - TM.cast, impY = (BAR.y + BAR.h / 2) / H, C = TM.cool;
        const tail = ease.inQuad(prog(c, 0.42, 0.62)) * impY;
        // the core of heat retreats from the middle of the bar to where the cursor lives, and shrinks to a caret
        const ce = ease.inOutCubic(prog(c, C.core0, C.core1));
        const CARET = { x: BAR.x + 82, y: BAR.y + BAR.h / 2 };
        const cool = [lerp(960, CARET.x, ce), CARET.y, Math.exp(lerp(Math.log(780), Math.log(7), ce)), Math.exp(lerp(Math.log(140), Math.log(30), ce))];
        const coolB = [ease.inOutCubic(prog(c, C.gap0, C.gap1)), lerp(0.08, 0.95, ease.inOutCubic(prog(c, C.sweep0, C.sweep1))),
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
        const K = TM.kills;
        // results
        if (t < K[2].flash) plateScene(ctx, mctx, t, g);
        else if (t < K[3].flash) {
          const u2 = t - K[2].flash;
          if (u2 < 1.25) M.drawCover(ctx, M.frameAt("aldrin", u2, 0, "hold"), full, lerp(1.12, 1.05, prog(u2, 0, 1.25)), 0.5, 0.45);
          else M.drawCover(ctx, M.frameAt("flag", (u2 - 1.25) * 0.95, 0, "hold"), full, lerp(1.1, 1.02, prog(u2, 1.25, K[3].flash - K[2].flash)), 0.5, 0.5);
          g.contrast = 1.15; g.sat = 0.35;
        } else if (t < K[4].flash) {
          ctx.fillStyle = "#0b0b0b"; ctx.fillRect(0, 0, W, H);
        } else if (t < K[5].flash) {
          const lay = M.layout(tileTree, t, 10);
          for (const r of lay) { ctx.save(); ctx.beginPath(); ctx.rect(r.x, r.y, r.w, r.h); ctx.clip(); M.drawCover(ctx, M.frameAt(TILE_CLIPS[r.id % TILE_CLIPS.length], t, r.id * 7), r, 1.04); ctx.restore(); }
        } else {
          const kd = K[5], u = t - kd.enter;
          ctx.fillStyle = "#070707"; ctx.fillRect(0, 0, W, H);
          if (u >= 0) {
            // the download opens out of the bar, plays, and the train comes through
            const a = ease.outExpo(prog(u, 0, 0.24));
            const flyF = (x) => 1 + 4.6 * ease.inExpo(prog(x, kd.end - 0.36, kd.end));
            const fly = flyF(t);
            const w0 = 1180, h0 = 124, w1 = 1020, h1 = 580;
            const w = lerp(w0, w1, a) * fly, h = lerp(h0, h1, a) * fly;
            const cy = lerp(930, 470, a) + (540 - 470) * ease.inCubic(prog(t, kd.end - 0.36, kd.end));
            const r = { x: W / 2 - w / 2, y: cy - h / 2, w, h };
            ctx.save(); ctx.shadowColor = "rgba(0,0,0,0.7)"; ctx.shadowBlur = 60; ctx.shadowOffsetY = 24;
            ctx.fillStyle = "#000"; M.roundRect(ctx, r.x, r.y, r.w, r.h, lerp(62, 18, a) * fly); ctx.fill(); ctx.shadowColor = "transparent";
            M.roundRect(ctx, r.x, r.y, r.w, r.h, lerp(62, 18, a) * fly); ctx.clip();
            M.drawCover(ctx, M.frameAt("arrival", Math.max(0, u) * 1.6 + 0.3, 0, "hold"), r, 1.02);
            ctx.restore();
            ctx.save(); ctx.strokeStyle = "rgba(255,255,255,0.16)"; ctx.lineWidth = 1.5; M.roundRect(ctx, r.x + 0.75, r.y + 0.75, r.w - 1.5, r.h - 1.5, lerp(62, 18, a) * fly); ctx.stroke(); ctx.restore();
            g.blurY = Math.min(300, vel(flyF, t) * 100); g.blurX = g.blurY * 0.7;
          }
        }
        // the killed app: it comes back for a moment, then burns as its command runs
        if (kill && t < kill.enter) {
          const p = ease.outExpo(prog(t, kill.flash, kill.flash + 0.1));
          const a = TM.apps.find((x) => x[0] === kill.app);
          ctx.fillStyle = `rgba(0,0,0,${(0.45 * p).toFixed(3)})`; ctx.fillRect(0, 0, W, H);
          const sc_ = 0.94 + 0.06 * p;
          drawWindow(ctx, { title: kill.app, clip: a[1], t: kill.flash, off: 11 },
            { x: KW.x + KW.w * (1 - sc_) / 2, y: KW.y + KW.h * (1 - sc_) / 2, w: KW.w * sc_, h: KW.h * sc_ }, t, clamp(p * 1.5), 80);
          const burn = prog(t, kill.enter - 0.24, kill.enter);
          if (burn > 0) Object.assign(g, { heat: ease.inQuad(burn), edge: killEdge, ember: 1, heatMask: 1 });
        }
      } else {
        tv = null; g.amber = 0;
        logo(ctx, t);
      }

      g.tv = tv;
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
