// Type layer (DOM over the GL canvas). Every call is a pure function of time: set state, never accumulate.
(function () {
  const { clamp, prog, ease, hash, lerp } = window.L;
  const $ = (id) => document.getElementById(id);
  const cmd = $("cmd"), txt = cmd.querySelector(".txt"), caret = cmd.querySelector(".caret");

  // c: { text, t0 (typing starts), cps, enter (execute time), out (wipe time), ink (dark text) }
  function command(t, c) {
    if (!c || t < (c.show ?? c.t0 - 0.12) || t > c.out + 0.14) { cmd.style.visibility = "hidden"; return; }
    cmd.style.visibility = "visible";
    cmd.classList.toggle("ink", !!c.ink);
    cmd.style.fontSize = `${c.size || 124}px`;
    const n = Math.floor(clamp((t - c.t0) * c.cps, 0, c.text.length));
    const pasted = c.paste && t >= c.pasteAt;
    if (txt.dataset.k !== `${n}:${pasted}`) {
      txt.dataset.k = `${n}:${pasted}`;
      txt.innerHTML = "";
      txt.append(c.text.slice(0, n));
      if (pasted) { const s = document.createElement("span"); s.className = "link"; s.textContent = c.paste; txt.append(s); }
    }
    const typing = t >= c.t0 && n < c.text.length;
    const blinkOn = Math.floor((t - c.t0) * 4) % 2 === 0;
    caret.style.opacity = t < c.t0 ? (Math.floor((c.t0 - t) * 8) % 2 ? 1 : 0.15) : typing || t >= c.enter ? 1 : blinkOn ? 1 : 0.15;
    // execute: the line flashes molten for two frames, then wipes out left to right
    const flash = t >= c.enter && t < c.enter + 2 / 60;
    cmd.classList.toggle("exec", flash);
    const w = ease.inOutCubic(prog(t, c.out, c.out + 0.14));
    cmd.style.clipPath = w > 0 ? `inset(-20% -2% -20% ${(w * 102).toFixed(2)}%)` : "none";
  }

  // big output word: snaps in with a short rise; `el` keeps one word
  // o: { font, size, x, y (centre), vertical, italic, weight }
  function word(el, text, t, t0, t1, o = {}) {
    if (t < t0 || t >= t1) { el.style.visibility = "hidden"; return; }
    el.style.visibility = "visible";
    if (el.textContent !== text) {
      el.textContent = text;
      el.style.fontFamily = o.font || "Geist";
      el.style.fontSize = `${o.size || 230}px`;
      el.style.fontStyle = o.italic ? "italic" : "normal";
      el.style.fontWeight = String(o.weight || 600);
      el.style.letterSpacing = o.italic ? "-0.02em" : "-0.045em";
      el.style.writingMode = o.vertical ? "vertical-rl" : "horizontal-tb";
      el.style.left = `${o.x ?? 960}px`; el.style.top = `${o.y ?? 560}px`;
    }
    const p = ease.outExpo(prog(t, t0, t0 + 0.12));
    const rise = (1 - p) * 26;
    el.style.transform = `translate3d(-50%, calc(-50% + ${(o.vertical ? 0 : rise).toFixed(2)}px), 0) scale(${(1.05 - 0.05 * p).toFixed(4)})`;
    el.style.opacity = String(clamp(p * 1.6));
  }

  // odometer: digits roll and land left to right
  function roll(el, target, t, t0, dur) {
    if (t < t0) { el.style.visibility = "hidden"; return; }
    el.style.visibility = "visible";
    const digits = [...target];
    let s = "", k = 0;
    const f = Math.floor(t * 60);
    for (let i = 0; i < digits.length; i++) {
      const ch = digits[i];
      if (!/[0-9]/.test(ch)) { s += ch; continue; }
      const land = t0 + dur * (0.35 + 0.65 * (k++ / 6));
      s += t >= land ? ch : String(Math.floor(hash(f * 13 + i * 7) * 10));
    }
    el.textContent = s;
    const p = ease.outExpo(prog(t, t0, t0 + 0.14));
    el.style.transform = `translate3d(0, ${((1 - p) * 30).toFixed(2)}px, 0)`;
    el.style.opacity = String(clamp(p * 1.6));
  }

  // ---------------------------------------------------------------- caption line that builds word by word,
  // then translates in place: glyphs of the target script churn and resolve left to right
  // o: { words: [[w, t]], to, toFont, at (translate time), dur }
  function caption(el, t, o) {
    if (!el._built) {
      el.innerHTML = "";
      el._spans = o.words.map(([w]) => { const s = document.createElement("span"); s.textContent = w + " "; el.appendChild(s); return s; });
      el._built = true; el._mode = "en";
    }
    const shown = o.words.filter(([, wt]) => t >= wt).length;
    if (!shown) { el.style.visibility = "hidden"; return; }
    el.style.visibility = "visible";
    if (t < o.at) {
      if (el._mode !== "en") { el._built = false; return caption(el, t, o); }
      el.style.fontFamily = o.enFont || "'Plex Mono'";
      o.words.forEach(([, wt], i) => {
        const s = el._spans[i];
        if (t < wt) { s.style.opacity = "0"; return; }
        const p = ease.outExpo(prog(t, wt, wt + 0.12));
        s.style.opacity = String(clamp(p * 1.5));
        s.style.display = "inline-block";
        s.style.transform = `translate3d(0, ${((1 - p) * 22).toFixed(2)}px, 0)`;
      });
      return;
    }
    el._mode = "to";
    const p = clamp((t - o.at) / o.dur);
    // scramble whole graphemes, so scripts with combining marks (Devanagari) never show broken fragments
    const seg = (str) => [...new Intl.Segmenter(undefined, { granularity: "grapheme" }).segment(str)].map((x) => x.segment);
    const target = seg(o.to), pool = seg(o.pool);
    const f = Math.floor(t * 60);
    let s = "";
    for (let i = 0; i < target.length; i++) {
      const res = (i + 1) / (target.length + 1);
      s += p >= res * 0.85 + 0.15 || target[i] === " " ? target[i] : pool[Math.floor(hash(f * 31 + i * 7) * pool.length)];
    }
    if (el.textContent !== s) el.textContent = s;
    el.style.fontFamily = o.toFont;
    el.style.opacity = "1";
  }

  // ---------------------------------------------------------------- slot reels: from -> to, digit columns roll down
  function reels(el, t, o) {
    if (!el._built) {
      el.innerHTML = "";
      const num = document.createElement("span"); num.className = "num"; el.appendChild(num);
      el._cols = [...o.to].map((ch, i) => {
        const cell = document.createElement("span"); cell.className = "cell";
        if (!/[0-9]/.test(ch)) { cell.textContent = ch; cell.classList.add("sep"); num.appendChild(cell); return null; }
        const strip = document.createElement("span"); strip.className = "strip";
        strip.textContent = Array.from({ length: 70 }, (_, k) => k % 10).join("\n");
        cell.appendChild(strip); num.appendChild(cell);
        return { strip, from: +o.from[i], to: +ch };
      });
      const unit = document.createElement("span"); unit.className = "unit";
      unit.innerHTML = `<span class="u">${o.unitFrom}</span><span class="u">${o.unitTo}</span>`;
      el.appendChild(unit); el._unit = unit.firstChild.parentNode;
      el._built = true;
    }
    if (t < o.t0) { el.style.visibility = "hidden"; return; }
    el.style.visibility = "visible";
    const n = el._cols.filter(Boolean).length;
    let k = 0;
    el._cols.forEach((c) => {
      if (!c) return;
      const j = k++;
      const start = o.t0 + o.delay + (n - 1 - j) * 0.035, dur = o.dur - (n - 1 - j) * 0.03;
      const p = ease.outExpo(prog(t, start, start + dur));
      const loops = 2 + (n - 1 - j) * 0.5 | 0;
      const travel = ((c.to - c.from + 10) % 10) + 10 * loops;
      const pos = c.from + travel * p;
      const v = Math.abs(travel * (ease.outExpo(prog(t + 1 / 120, start, start + dur)) - ease.outExpo(prog(t - 1 / 120, start, start + dur))) * 60);
      c.strip.style.transform = `translate3d(0, ${(-pos).toFixed(3)}em, 0)`;
      c.strip.style.filter = v > 0.5 ? `blur(${Math.min(5, v * 0.08).toFixed(2)}px)` : "none";
    });
    const up = ease.inOutCubic(prog(t, o.t0 + o.delay + o.dur * 0.35, o.t0 + o.delay + o.dur * 0.55));
    el._unit.style.setProperty("--u", up.toFixed(4));
    const a = ease.outExpo(prog(t, o.t0, o.t0 + 0.14));
    el.style.opacity = String(clamp(a * 1.5));
    el.style.transform = `translate3d(0, ${((1 - a) * 24).toFixed(2)}px, 0)`;
  }

  // "one command." typed crisp and centred, then executed into the first real command
  function oneCommand(el, t, c, enter) {
    if (t < c.t0 - 0.1 || t > enter + 0.16) { el.style.visibility = "hidden"; return; }
    el.style.visibility = "visible";
    const n = Math.floor(clamp((t - c.t0) * c.cps, 0, c.text.length));
    el.firstChild.textContent = c.text.slice(0, n);
    el.classList.toggle("exec", t >= enter && t < enter + 2 / 60);
    const w = ease.inOutCubic(prog(t, enter + 0.02, enter + 0.16));
    el.style.clipPath = w > 0 ? `inset(-20% -2% -20% ${(w * 102).toFixed(2)}%)` : "none";
    el.lastChild.style.opacity = n < c.text.length || Math.floor((t - c.t0) * 4) % 2 === 0 ? "1" : "0.15";
  }

  // ---------------------------------------------------------------- the bar: cast at centre, then the place every command goes
  function bar(el, t, c, TM) {
    if (t < TM.glass || t >= TM.logo + 0.3) { el.style.visibility = "hidden"; return; }
    el.style.visibility = "visible";
    const a = ease.inOutCubic(prog(t, TM.glass, TM.glass + 0.26));
    const d = ease.inOutCubic(prog(t, TM.bardown, TM.bardown + 0.34));
    const out = ease.inCubic(prog(t, TM.logo - 0.05, TM.logo + 0.25));
    const w = lerp(1360, 1180, d), h = lerp(168, 124, d), cy = lerp(540, 930, d) + out * 60;
    el.style.width = `${w}px`; el.style.height = `${h}px`; el.style.left = `${960 - w / 2}px`; el.style.top = `${cy - h / 2}px`;
    el.style.borderRadius = `${h / 2}px`; el.style.opacity = String(a * (1 - out));
    el.style.fontSize = `${lerp(62, 48, d)}px`; el.style.paddingLeft = `${lerp(76, 56, d)}px`;
    // still warm from the pour: a glow under the glass that cools away
    const warm = 1 - ease.outCubic(prog(t, TM.glass, TM.glass + 0.9));
    el.style.setProperty("--warm", warm.toFixed(3));
    const txt = el.querySelector(".txt"), caret = el.querySelector(".caret");
    let str = "", typing = false, t0 = TM.line3.t0, link = "";
    if (c) {
      const n = Math.floor(clamp((t - c.t0) * c.cps, 0, c.text.length));
      str = c.text.slice(0, n); typing = t >= c.t0 && n < c.text.length; t0 = c.t0;
      if (c.paste && t >= c.pasteAt) link = c.paste;
      el.classList.toggle("exec", t >= c.enter && t < c.enter + 2 / 60);
    } else if (t < TM.bardown + 0.1) {
      const o = TM.line3, n = Math.floor(clamp((t - o.t0) * o.cps, 0, o.text.length));
      str = o.text.slice(0, n); typing = t >= o.t0 && n < o.text.length;
      el.classList.remove("exec");
      const wipe = ease.inOutCubic(prog(t, TM.bardown - 0.06, TM.bardown + 0.06));
      if (wipe > 0) str = str.slice(0, Math.round(str.length * (1 - wipe)));
    }
    const key = `${str}|${link}`;
    if (txt.dataset.k !== key) {
      txt.dataset.k = key; txt.innerHTML = ""; txt.append(str);
      if (link) { const s = document.createElement("span"); s.className = "link"; s.textContent = link; txt.append(s); }
    }
    caret.style.opacity = typing || Math.floor((t - t0) * 4) % 2 === 0 ? "1" : "0.15";
  }

  window.TYPE = { bar, oneCommand, command, word, roll, caption, reels };
})();
