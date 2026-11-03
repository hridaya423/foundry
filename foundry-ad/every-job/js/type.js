// Type layer (DOM over the GL canvas). Every call is a pure function of time: set state, never accumulate.
(function () {
  const { clamp, prog, ease, hash, lerp, rng } = window.L;
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
    const a = ease.outExpo(prog(t, o.t0, o.t0 + 0.14));      // there on the enter frame, settling up into place
    el.style.opacity = "1";
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
  // docked low and big enough to read in a phone feed (78 px type at 1080p)
  const DOCK = { w: 1560, h: 184, cy: 930, font: 78, pad: 80 };
  // after the last enter the bar is Armstrong's live line: each word is typed as he says it, its letters over the time he
  // takes to say it. The bar holds what he said; its translation is set just above it (answers)
  const esc = (x) => x.replace(/&/g, "&amp;").replace(/</g, "&lt;");
  const said = (t, words) => words.filter(([, wt]) => t >= wt).map(([w, wt, d]) => w.slice(0, Math.ceil(w.length * clamp((t - wt) / d)))).join(" ");

  function bar(el, t, c, TM) {
    if (t < TM.glass || t >= TM.logo) { el.style.visibility = "hidden"; return; }
    el.style.visibility = "visible";
    const a = ease.inOutCubic(prog(t, TM.glass, TM.glass + 0.14));
    const d = ease.inOutCubic(prog(t, TM.bardown, TM.bardown + 0.34));
    const out = ease.inOutCubic(prog(t, TM.letGo, TM.gone));   // the bar and its line let go as its caret leaves for the name
    // enter presses the bar: it gives 2.5% on the frame and springs back
    const kick = (at) => (t >= at ? 1 - ease.outCubic(prog(t, at, at + 0.2)) : 0);
    // live, the bar presses again as it sends line B (the arrival) and as each translation leaves it
    const sends = c && c.live ? [1.6 * kick(TM.arrive), ...c.live.answers.map((a) => kick(a.at))] : [];
    const press = c ? 1 - 0.025 * Math.max(kick(c.enter), ...sends) : 1;
    // live, the bar opens a little wider, so the longest line and the chip that names the translation share it
    const wide = c && c.live ? 140 * ease.inOutCubic(prog(t, c.enter, c.enter + 0.3)) : 0;
    const w = (lerp(1360, DOCK.w, d) + wide) * press, h = lerp(168, DOCK.h, d) * press, cy = lerp(540, DOCK.cy, d) + out * 24;
    el.style.width = `${w}px`; el.style.height = `${h}px`; el.style.left = `${960 - w / 2}px`; el.style.top = `${cy - h / 2}px`;
    el.style.borderRadius = `${h / 2}px`; el.style.opacity = String(a * (1 - out));
    const font = lerp(84, DOCK.font, d), pad = lerp(76, DOCK.pad, d);   // the cast bar's line reads as the film's third line
    el.style.fontSize = `${font}px`; el.style.paddingLeft = `${pad}px`;
    // still warm from the pour: a glow under the glass that cools away
    const warm = 1 - ease.outCubic(prog(t, TM.glass, TM.glass + 0.9));
    el.style.setProperty("--warm", warm.toFixed(3));
    const txt = el.querySelector(".txt"), caret = el.querySelector(".caret");
    let html = "", typing = false, t0 = TM.line3.t0, wipe = 0;
    if (c && c.live && t >= c.enter) {
      // the command flashes molten and fades; then he speaks into the bar
      const L = c.live;
      wipe = ease.inOutCubic(prog(t, c.enter + 2 / 60, c.enter + 0.16));
      el.classList.toggle("exec", t < c.enter + 2 / 60);
      if (wipe < 1) html = esc(c.text);
      else {
        wipe = 0; t0 = c.enter + 0.16;
        const ws = t < L.rise ? L.a : L.b;
        html = esc(said(t, ws));
        typing = ws.some(([, wt, d]) => t >= wt && t < wt + d + 0.1);
      }
    } else if (c) {
      const n = Math.floor(clamp((t - c.t0) * c.cps, 0, c.text.length));
      html = esc(c.text.slice(0, n)); typing = t >= c.t0 && n < c.text.length; t0 = c.t0;
      if (c.paste && t >= c.pasteAt) html += `<span class="link">${esc(c.paste)}</span>`;
      el.classList.toggle("exec", t >= c.enter && t < c.enter + 2 / 60);
    } else if (t < TM.clear) {
      // the line rides the bar down and holds over the first plate; it clears just before the first command
      const o = TM.line3, n = Math.floor(clamp((t - o.t0) * o.cps, 0, o.text.length));
      let str = o.text.slice(0, n); typing = t >= o.t0 && n < o.text.length;
      el.classList.remove("exec");
      const wp = ease.inOutCubic(prog(t, TM.clear - 0.1, TM.clear));
      if (wp > 0) str = str.slice(0, Math.round(str.length * (1 - wp)));
      html = esc(str);
    }
    // live: a chip names the translation. It lights on the Quindar tone's frame (the channel opens), and its molten dot
    // beats with the pulse under him (score.py, TM.pulse)
    const chip = el.querySelector(".chip"), live = c && c.live && t >= TM.quindarIn;
    chip.style.opacity = live ? "1" : "0";
    // it names the language of the line above the bar: Japanese for line A, then, from the cut to each person, theirs
    const to = chip.querySelector(".to"), ans = live ? c.live.answers.filter((a) => t >= a.cut).pop() : null;
    const name = ans ? ans.name : "日本語";
    if (to.textContent !== name) { to.textContent = name; to.style.fontFamily = `"${ans ? ans.font : "Plex JP"}", sans-serif`; }
    if (live) {
      const rise = c.live.rise, last = [TM.quindarIn, ...TM.pulse].filter((b) => b <= t && (b >= rise || b === TM.quindarIn || Math.round((rise - b) / 0.5) % 2 === 0)).pop();
      chip.style.setProperty("--beat", (last == null ? 0 : Math.exp(-(t - last) / 0.16)).toFixed(3));
    }
    if (txt.dataset.k !== html) { txt.dataset.k = html; txt.innerHTML = html; }
    txt.style.opacity = String(1 - wipe);
    // once line B is sent the caret stops blinking and holds, lit: Foundry's caret, as it waits after the name on the end card
    // it leaves the bar for the name (film.js handoff), which draws it from here on
    const held = c && c.live && t >= TM.arrive;
    caret.style.opacity = t < TM.line3.t0 - 0.06 || (c && c.live && t >= TM.letGo) ? "0" : held || typing || Math.floor((t - t0) * 4) % 2 === 0 ? "1" : "0.15";
  }

  // ---------------------------------------------------------------- the translations, set just above the line they translate
  // Foundry speaks Japanese with him, a phrase on each of his words: line A's goes as the picture cuts to the flag, line
  // B's is whole on the cut to the Earth and holds there. Then the world answers: on the cut to each person their own
  // language lands, a word at a time from the cut frame; it goes with them on the next cut, and the last lets go with
  // the bar. Arabic is set right to left, flush with the bar's right edge
  const ANSWER = { x: 960 - (DOCK.w + 140) / 2 + DOCK.pad, right: 960 + (DOCK.w + 140) / 2 - DOCK.pad, y: 760, size: 72 };
  // received: molten as it lands, cooling to bone; colour only, so the letterforms stay sharp
  const heat = (st, t, at) => {
    const h = Math.exp(-(t - at) / 0.18);
    st.color = `rgb(${Math.round(lerp(241, 255, h))}, ${Math.round(lerp(239, 122, h))}, ${Math.round(lerp(234, 64, h))})`;
  };
  // one line: its words (or phrases), each [text, at], in place from the start so nothing moves as they land
  function line(el, parts, lang, font, from, until) {
    const s = document.createElement("span");
    s.lang = lang; s.style.fontFamily = `"${font}", sans-serif`; s.style.fontSize = `${ANSWER.size}px`;
    s.style.textShadow = "0 2px 18px rgba(0, 0, 0, 0.8)";
    if (lang === "ar") { s.dir = "rtl"; s.style.textAlign = "right"; }
    const w = parts.map(([text, at], i) => {
      const c = document.createElement("b");
      c.textContent = (i && lang !== "ja" ? " " : "") + text; c.style.fontWeight = "inherit";
      s.appendChild(c);
      return { st: c.style, at };
    });
    el.appendChild(s);
    return { st: s.style, w, from, until, rtl: lang === "ar" };
  }
  function answers(el, t, TM, L) {
    if (t < L.ja[0].p[0][1] || t >= L.gone) { el.style.visibility = "hidden"; return; }
    if (!el._lines) {
      const A = L.answers;
      el._lines = [...L.ja.map((j) => line(el, j.p, "ja", "Plex JP", j.p[0][1], j.until)),
        ...A.map((a, i) => line(el, a.words, a.lang, a.font, a.cut, A[i + 1] ? A[i + 1].cut : L.gone))];
    }
    el.style.visibility = "visible";
    const out = ease.inOutCubic(prog(t, L.letGo, L.gone));
    el._lines.forEach((q) => {
      if (t < q.from || t >= q.until) { q.st.opacity = "0"; return; }
      q.w.forEach((w) => { w.st.opacity = t >= w.at ? "1" : "0"; heat(w.st, t, w.at); });
      q.st.opacity = (1 - out).toFixed(3);
      q.st.transform = `translate3d(${q.rtl ? ANSWER.right : ANSWER.x}px, ${(ANSWER.y - out * 40).toFixed(1)}px, 0) translate(${q.rtl ? "-100%" : "0"}, -50%)`;
      q.st.filter = out > 0 ? `blur(${(out * 6).toFixed(2)}px)` : "none";
    });
  }

  // the end card: once the name has stepped back, the line lands under it on the beat (the last hit)
  const TAG_Y = 700;
  function card(tag, t, TM) {
    const a = ease.outExpo(prog(t, TM.press, TM.press + 0.14));
    tag.style.visibility = a > 0 ? "visible" : "hidden";
    tag.style.top = `${(TAG_Y - 38 + (1 - a) * 24).toFixed(1)}px`;
    tag.style.opacity = a.toFixed(3);
  }

  window.TYPE = { bar, card, oneCommand, command, word, roll, reels, answers, DOCK };
})();
