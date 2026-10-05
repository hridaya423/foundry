// Media: image sequences + stills drawn into a 2D scene canvas (read by the GL pass), tiling layouts,
// heat fields and the liquid-metal paint layer.
(function () {
  const { rng, hash, clamp, lerp, prog, ease } = window.L;
  const W = 1920, H = 1080, SEQ_FPS = 30;

  const frames = {}, stills = {};
  // decode, retrying a dropped request a few times (dev servers can refuse bursts of ~2000 frames)
  const wait = async (im) => {
    for (let k = 0; k < 4; k++) {
      try { await im.decode(); return; } catch (e) {
        if (im.complete && im.naturalWidth) return;
        await new Promise((r) => setTimeout(r, 150 * (k + 1)));
        const src = im.src.split("?")[0]; im.src = `${src}?r=${k + 1}`;
      }
    }
  };
  function load(names, ext = "jpg") {
    const all = [];
    for (const name of names) {
      const m = window.SEQ[name] || { n: ext === "png" ? 39 : 0 };
      frames[name] = [];
      for (let i = 1; i <= m.n; i++) {
        const im = new Image();
        im.src = `assets/seq/${name}/${String(i).padStart(3, "0")}.${ext}`;
        frames[name].push(im); all.push(wait(im));
      }
    }
    return Promise.all(all);
  }
  function still(name, src) { const im = new Image(); im.src = src; stills[name] = im; return wait(im); }

  function canvas(w = W, h = H) { const c = document.createElement("canvas"); c.width = w; c.height = h; return c; }

  // cover-fit `im` into rect r, zoomed about focus (fx, fy) in source fractions
  function drawCover(ctx, im, r, zoom = 1, fx = 0.5, fy = 0.5) {
    const iw = im.naturalWidth || im.width, ih = im.naturalHeight || im.height;
    const s = Math.max(r.w / iw, r.h / ih) * zoom;
    const sw = Math.min(iw, r.w / s), sh = Math.min(ih, r.h / s);
    const sx = clamp(iw * fx - sw / 2, 0, iw - sw), sy = clamp(ih * fy - sh / 2, 0, ih - sh);
    ctx.drawImage(im, sx, sy, sw, sh, r.x, r.y, r.w, r.h);
  }

  function frameAt(name, t, off = 0, loop = "ping") {
    const f = frames[name], n = f.length;
    const i = Math.floor(t * SEQ_FPS + off + 1e-6);
    if (loop === "wrap") return f[((i % n) + n) % n];
    if (loop === "hold") return f[clamp(i, 0, n - 1)];
    const m = 2 * n - 2, k = ((i % m) + m) % m;
    return f[k < n ? k : m - k];
  }
  const media = (name, t, off, loop) => (stills[name] ? stills[name] : frameAt(name, t, off, loop));

  // ---------------------------------------------------------------- tiling: a window manager splitting on the beat
  // events: [{t, k}] = at time t, split the k largest windows. Returns a tree whose layout is a function of time.
  function splitTree(events, seed, box = { x: 0, y: 0, w: W, h: H }) {
    const r = rng(seed);
    const root = { id: 0, born: -1 };
    let leaves = [root], id = 1;
    const sizeOf = (nd) => nd._w * nd._h;
    root._w = box.w; root._h = box.h;
    for (const ev of events) {
      const pick = leaves.slice().sort((a, b) => sizeOf(b) * (0.8 + 0.4 * hash(b.id * 7 + seed)) - sizeOf(a) * (0.8 + 0.4 * hash(a.id * 7 + seed))).slice(0, ev.k);
      for (const nd of pick) {
        const vert = nd._w / nd._h > 1.15 || (nd._w / nd._h > 0.75 && r() < 0.5);
        const p = 0.38 + r() * 0.24;
        nd.split = { vert, p, t: ev.t + r() * 0.03 };
        nd.a = { id: id++, born: nd.born, _w: vert ? nd._w * p : nd._w, _h: vert ? nd._h : nd._h * p };
        nd.b = { id: id++, born: nd.split.t, _w: vert ? nd._w * (1 - p) : nd._w, _h: vert ? nd._h : nd._h * (1 - p) };
        nd.a.home = nd.home ?? nd.id; nd.b.home = nd.b.id;
        leaves = leaves.filter((l) => l !== nd).concat([nd.a, nd.b]);
      }
    }
    return { root, box, leaves };
  }
  // the new window slides in from the split edge; `dur` is the snap time
  function layout(tree, t, gap = 6, dur = 0.16) {
    const out = [];
    (function walk(nd, x, y, w, h) {
      if (!nd.split || t < nd.split.t) { out.push({ id: nd.home ?? nd.id, leaf: nd, x, y, w, h }); return; }
      const q = nd.split.p + (1 - nd.split.p) * (1 - ease.outExpo(prog(t, nd.split.t, nd.split.t + dur)));
      if (nd.split.vert) { walk(nd.a, x, y, w * q, h); walk(nd.b, x + w * q, y, w * (1 - q), h); }
      else { walk(nd.a, x, y, w, h * q); walk(nd.b, x, y + h * q, w, h * (1 - q)); }
    })(tree.root, tree.box.x, tree.box.y, tree.box.w, tree.box.h);
    const g = gap / 2;
    return out.map((o) => ({ ...o, x: o.x + g, y: o.y + g, w: Math.max(0, o.w - gap), h: Math.max(0, o.h - gap) }));
  }

  // ---------------------------------------------------------------- heat field for the burn
  // quarter res: R = 1 at a seam falling to 0 at `reach` px inside a tile, G = per-tile ignition delay
  function edgeField(tiles, reach = 220, seed = 1) {
    const s = 4, w = W / s, h = H / s;
    const c = canvas(w, h), x = c.getContext("2d"), img = x.createImageData(w, h);
    const delay = tiles.map((t, i) => hash(seed * 31 + i));
    for (let py = 0; py < h; py++) for (let px = 0; px < w; px++) {
      const X = (px + 0.5) * s, Y = (py + 0.5) * s;
      let d = 0, k = -1;
      for (let i = 0; i < tiles.length; i++) {
        const t = tiles[i];
        if (X >= t.x && X < t.x + t.w && Y >= t.y && Y < t.y + t.h) { d = Math.min(X - t.x, t.x + t.w - X, Y - t.y, t.y + t.h - Y); k = i; break; }
      }
      const o = (py * w + px) * 4;
      img.data[o] = Math.round(255 * clamp(1 - d / reach));
      img.data[o + 1] = k < 0 ? 0 : Math.round(255 * delay[k]);
      img.data[o + 2] = k < 0 ? 0 : 255;                    // B: inside a tile
      img.data[o + 3] = 255;
    }
    x.putImageData(img, 0, 0);
    return c;
  }

  // ---------------------------------------------------------------- liquid metal paint layer
  // half res, covering y in [0, 3] frame heights. Draw in frame px with metalBegin/metalEnd.
  function metalCanvas() { return canvas(W / 2, H * 1.5); }
  let scratch;
  function metalBegin() {
    if (!scratch) scratch = metalCanvas();
    const ctx = scratch.getContext("2d");
    ctx.setTransform(1, 0, 0, 1, 0, 0);
    ctx.fillStyle = "#000"; ctx.fillRect(0, 0, scratch.width, scratch.height);
    ctx.setTransform(0.5, 0, 0, 0.5, 0, 0);
    ctx.strokeStyle = "rgb(255,0,0)"; ctx.fillStyle = "rgb(255,0,0)"; ctx.lineCap = "round"; ctx.lineJoin = "round";
    return ctx;
  }
  function metalEnd(out, blur = 5) {
    const o = out.getContext("2d");
    o.filter = `blur(${blur}px)`; o.clearRect(0, 0, out.width, out.height); o.drawImage(scratch, 0, 0); o.filter = "none";
    return out;
  }
  function drips(tiles, seed) {
    const r = rng(seed), out = [];
    for (const t of tiles) {
      const n = Math.round(t.w / 170 + r() * 0.9);
      for (let i = 0; i < n; i++) out.push({ x: t.x + t.w * (0.1 + 0.8 * r()), y: t.y + t.h + 2, d: r() * 0.8, g: 0.45 + r() * 1.0, w: 2.2 + r() * 3.2 });
    }
    return out;
  }
  // drips leave the tiles under gravity; below the wall they bend into the streams (sx: target x, sw: width),
  // whose heads fall ahead of them, so the frame below the wall holds exactly the real pour's streams
  function seamsAndDrips(ctx, tiles, ds, seam, drip, streams) {
    if (seam > 0) { ctx.lineWidth = seam; for (const q of tiles) ctx.strokeRect(q.x - 3, q.y - 3, q.w + 6, q.h + 6); }
    const Y0 = H + 60, Y1 = H * 1.38;
    if (drip > 0) for (const d of ds) {
      const u = Math.max(0, drip - d.d);
      if (u <= 0) continue;
      const L = 900 * d.g * u * u + 40 * u, w = d.w * (1 + 0.6 * Math.min(1, u * 3));
      const end = d.y + L;
      ctx.lineWidth = w;
      ctx.beginPath(); ctx.moveTo(d.x, d.y);
      if (!streams || end < Y0) ctx.lineTo(d.x, end);
      else {
        const st = streams[d.x < streams.split ? 0 : 1];
        ctx.lineTo(d.x, Y0);
        const k = Math.min(1, (end - Y0) / (Y1 - Y0));
        ctx.bezierCurveTo(d.x, Y0 + (Y1 - Y0) * 0.5 * k, st.x, Y0 + (Y1 - Y0) * 0.5 * k, lerp(d.x, st.x, k), Y0 + (Y1 - Y0) * k);
        if (end > Y1) ctx.lineTo(st.x, end);
      }
      ctx.stroke();
      if (!streams || end < Y0) { ctx.beginPath(); ctx.arc(d.x, end, w * 0.95, 0, Math.PI * 2); ctx.fill(); }
    }
    if (streams) for (const st of streams) {
      if (st.head <= Y1) continue;
      ctx.lineWidth = st.w; ctx.beginPath(); ctx.moveTo(st.x, Y1 - 40); ctx.lineTo(st.x, st.head); ctx.stroke();
    }
  }

  // where a source pixel of `im` lands on screen when drawn with drawCover(r, zoom, fx, fy)
  function coverMap(iw, ih, r, zoom = 1, fx = 0.5, fy = 0.5) {
    const s = Math.max(r.w / iw, r.h / ih) * zoom;
    const sw = Math.min(iw, r.w / s), sh = Math.min(ih, r.h / s);
    const sx = clamp(iw * fx - sw / 2, 0, iw - sw), sy = clamp(ih * fy - sh / 2, 0, ih - sh);
    return (x, y) => ({ x: r.x + (x - sx) * s, y: r.y + (y - sy) * s });
  }

  function roundRect(ctx, x, y, w, h, r) {
    r = Math.min(r, w / 2, h / 2);
    ctx.beginPath(); ctx.moveTo(x + r, y); ctx.arcTo(x + w, y, x + w, y + h, r); ctx.arcTo(x + w, y + h, x, y + h, r);
    ctx.arcTo(x, y + h, x, y, r); ctx.arcTo(x, y, x + w, y, r); ctx.closePath();
  }
  function ellipsize(ctx, s, max) {
    if (ctx.measureText(s).width <= max) return s;
    while (s.length > 3 && ctx.measureText(s + "…").width > max) s = s.slice(0, -1);
    return s + "…";
  }

  window.MOSAIC = { roundRect, ellipsize, load, still, stills, frames, canvas, drawCover, frameAt, media, splitTree, layout, edgeField,
    metalCanvas, metalBegin, metalEnd, drips, seamsAndDrips, coverMap, W, H };
})();
