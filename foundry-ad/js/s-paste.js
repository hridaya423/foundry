// 3 paste: a rolodex of clipboard history riffles behind "paste"; the e works loose and falls out of the word,
// a molten period drops into its place on the beat: "past." The period is the next dot.
window.SC = window.SC || {};
window.SC.paste = (function () {
  const { prog, ease, PLAN, clamp, lerp } = window.L;
  const { el, img } = window.UI;
  const [A, B] = PLAN.paste;
  const ZOOM = 0.42;
  const FS = 470;
  const HIT = A + 2 * PLAN.beat;                                    // the period lands on the beat
  const LOOSE = HIT - 0.15, FALL = HIT - 0.1;
  const exit = { x: 0, y: 0, r: 30, t0: B - ZOOM, t1: B };

  const IMGS = ["camera", "currency", "dice", "emoji", "note", "quicklink", "script", "shortcut", "snippet", "unit", "uuid", "widget"];
  const TEXT = ["brew install foundry", "#FF5A1F", "meet at 7?", "https://foundry.app", "git push origin main", "13.6 ms",
    "rgb(255, 90, 31)", "~/Desktop/launch.mov", "SELECT * FROM tiles\nWHERE hot = true", "⌥ Space", "sk-…redacted"];
  const N = IMGS.length + TEXT.length + 1;
  const R0 = A + 0.02, R1 = LOOSE;                                   // riffle window
  const FLIPD = 0.13;
  const fallAt = (i) => R0 + (R1 - R0 - FLIPD) * (1 - Math.pow(1 - i / (N - 2), 1.6));

  function build(tl) {
    const root = document.getElementById("s-paste");
    const deck = el("div", "deck", root);
    const cards = [];
    for (let i = 0; i < N; i++) {
      const c = el("div", "card", deck);
      if (i === N - 1) {
        c.classList.add("sw");
        el("div", "tx", c, "#FF5A1F");
      } else if (i % 2 === 0 && i / 2 < IMGS.length) {
        img(`assets/img/cards/${IMGS[i / 2]}.jpg`, null, c);
      } else {
        const k = (i - 1) / 2 | 0;
        el("div", "tx", c, TEXT[Math.min(TEXT.length - 1, k)]);
      }
      c.style.zIndex = String(N - i);
      cards.push(c);
    }

    // the word, as letters so the e can leave
    const word = el("div", "verb word", root);
    word.style.fontSize = FS + "px";
    const spans = [..."paste"].map((ch) => el("span", null, word, ch));
    for (const s of spans) s.style.display = "inline-block";
    const w = word.getBoundingClientRect().width;
    const m = document.createElement("canvas").getContext("2d");
    m.font = `800 ${FS}px Archivo`;
    m.fontStretch = "condensed";
    const xh = m.measureText("x").actualBoundingBoxAscent;
    const base = 540 + xh / 2;
    // DOM line box: top of a line-height:1 box sits (ascent+descent-FS)/2 above the em box; baseline from metrics
    const mt = m.measureText("p");
    const asc = mt.fontBoundingBoxAscent, desc = mt.fontBoundingBoxDescent;
    const top = base - (FS - (asc + desc)) / 2 - asc;
    Object.assign(word.style, { left: 960 - w / 2 + "px", top: top + "px", zIndex: 40 });
    const e = spans[4];
    const eBox = { l: e.offsetLeft, w: e.offsetWidth };
    e.style.transformOrigin = "20% 92%";

    exit.x = 960 - w / 2 + eBox.l + FS * 0.11;
    exit.y = base - exit.r;
    const dot = el("div", "dot", root);
    Object.assign(dot.style, { left: exit.x - exit.r + "px", top: exit.y - exit.r + "px", width: exit.r * 2 + "px", height: exit.r * 2 + "px", zIndex: 41 });

    window.L.on((t) => {
      // riffle: each card hinges on its bottom edge and falls toward the lens; the stack behind steps forward
      let fallen = 0;
      for (let i = 0; i < N; i++) {
        const c = cards[i];
        const t0 = fallAt(i);
        const p = i === N - 1 ? 0 : prog(t, t0, t0 + FLIPD);
        fallen += p;
        const back = Math.max(0, i - fallen);
        if (p >= 1 || back > 4) { c.style.visibility = "hidden"; continue; }
        c.style.visibility = "inherit";
        const ang = -98 * ease.inCubic(p);
        const lift = back * 14, sc = 1 - back * 0.035;
        c.style.transform = `translateY(${(-lift).toFixed(2)}px) scale(${sc.toFixed(4)}) rotateX(${ang.toFixed(2)}deg)`;
        c.style.filter = back > 0.01 ? `brightness(${(1 - back * 0.16).toFixed(3)})` : "none";
      }

      // the e: loosens on its foot, then drops out of frame tumbling
      const lp = ease.outCubic(prog(t, LOOSE, FALL));
      const f = Math.max(0, t - FALL);
      const y = 5200 * f * f, rot = 14 * lp + 260 * f;
      e.style.transform = `translate(${(f * 260).toFixed(1)}px, ${y.toFixed(1)}px) rotate(${rot.toFixed(2)}deg)`;

      // the period drops in from above and lands on the beat with a squash
      const dp = prog(t, HIT - 0.09, HIT);
      const sq = t >= HIT ? Math.exp(-(t - HIT) * 22) * Math.cos((t - HIT) * 40) : 0;
      dot.style.visibility = t >= HIT - 0.09 ? "inherit" : "hidden";
      dot.style.transform = `translateY(${(-(1 - ease.inCubic(dp)) * 520).toFixed(1)}px) scale(${(1 + sq * 0.3).toFixed(3)}, ${(1 - sq * 0.3).toFixed(3)})`;
      dot.style.transformOrigin = "50% 100%";
    }, { continuous: true });
  }
  return { build, exit, root: "#s-paste" };
})();
