#!/usr/bin/env python3
"""Single source of truth for "Every job." (v2). Writes js/timing.js (window.TM); tools/score.py imports it.

  A machine for every job.   typewriter-struck, a machine per word, in an amber tube
  An app for every job.      typed with an I-beam; the apps pile up; the set overheats; a wall of sets
  `melt them down`           every screen ignites; the metal braids into one river; it fills a mould
  One for every job.         the mould is Foundry's bar; it cools to iron and becomes the bar
  six kills                  each app from the wall comes back, burns, and one line does its job
  logo                       back through tiles that hold the whole film; "...for mankind." lands on it
"""
import json, os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BEAT = 0.5

# ---------------------------------------------------------------- Act I: one word, one machine, one beat
WORDS1 = [("A", 0.0, "typists"), ("machine", 0.5, "operator"), ("for", 1.0, "telegraph"), ("every", 1.5, "console"), ("job.", 2.0, "ignition")]
ACT2 = 2.8
# ---------------------------------------------------------------- Act II
LINE2 = {"text": "An app for every job.", "t0": ACT2 + 0.06, "cps": 52}
HEROES = 3.3                     # the first three apps, big enough to read
BURST0, BURST1 = 4.2, 5.25       # then everything else
HEAT0 = 4.3                      # the set starts to struggle
WALL0, WALL1 = 5.0, 5.7          # pull back: a wall of sets, then hold on it
# the valley: everything stalls (picture freezes, the music tape-stops into a ringing), one caret blinks alone,
# `melt them down` is typed into the silence, and its enter is the drop, on beat 14
STALL = 5.75
CARET_ALONE = 6.1
MELT_CMD = 7.0
D_MELT = MELT_CMD - 6.2          # how far everything after the melt moved when the valley went in
RIVER0, RIVER1 = 6.95 + D_MELT, 8.6 + D_MELT       # the camera falls with the river
CAST = 8.6 + D_MELT
# the casting cools from the rim in; its last heat retreats to where the cursor lives and becomes the caret
COOL = {"fill": 0.0, "core0": 0.55, "core1": 1.45, "gap0": 0.9, "gap1": 1.45, "sweep0": 1.12, "sweep1": 1.45,
        "knock0": 1.4, "knock1": 1.78, "flake0": 1.45, "flake1": 1.82, "point": 1.82}
GLASS = CAST + 1.8
LINE3 = {"text": "One for every job.", "t0": GLASS + 0.16, "cps": 54}
SETTLE = 11.0 + D_MELT           # the bar settles low and stays there

# ---------------------------------------------------------------- the kills: app -> command -> result
KILL_APPS = {
    "gif": "GIF Maker Pro",
    "rmbg": "Background Eraser Online",
    "translate": "Translate",
    "currency": "Currency Converter Plus",
    "tile": "Window Snap",
    "download": "YouTube Downloader MP4 (No Virus)",
}
KILLS = [  # (kind, flash, text, paste, enter, end): enters on the grid, each sooner than the last (1.5, 1.25, 1, 0.75 s)
    ("gif", 12.0, "convert to gif", None, 12.5, 13.55),                  # until the train releases it; translate last,
    ("rmbg", 13.55, "remove background", None, 14.0, 14.8),              # so Armstrong is never interrupted
    ("currency", 14.8, "100 usd in eur", None, 15.25, 15.8),
    ("tile", 15.8, "tile windows", None, 16.25, 16.55),
    ("download", 16.55, "download ", "youtu.be/lumiere-1895", 17.0, 18.3),
    ("translate", 18.3, "translate to japanese", None, 18.75, None),     # runs into the logo
]

# ---------------------------------------------------------------- Armstrong, whole: "That's one small step for man, one giant leap for mankind."
SEG_A = (15.40, 17.75)
SEG_B = [(20.72, 21.02, 0.2), (21.80, 23.72, 0.0)]
A_GAP = 0.7                      # his pause, tightened (but a breath); the line turns Japanese in it
VO_A = KILLS[-1][4] + 0.32       # translate's enter is the Quindar intro tone; then him
VO_B = VO_A + (SEG_A[1] - SEG_A[0]) + A_GAP
FOR_SRC, MANKIND_SRC, END_SRC = 22.60, 22.78, 23.72


def b_at(src):
    s0, s1, g = SEG_B[0]
    return VO_B + (src - s0) if src <= s1 else VO_B + (s1 - s0) + g + (src - SEG_B[1][0])


LOGO = b_at(FOR_SRC)             # cut to the logo on "for" in "...leap for mankind."
MANKIND_AT, VO_END = b_at(MANKIND_SRC), b_at(END_SRC)
QUINDAR = VO_END + 0.14          # end of transmission
END = round(LOGO + 2.6, 2)       # the cast, the caret's last blink, then the room
# the score (tools/music.py): one composition, five sections; boundaries on the bar grid where they can be
MUSIC = [("lineage", 0.0), ("weight", 3.0), ("drop", MELT_CMD), ("build", 12.0), ("leap", KILLS[-1][4])]
WORDS_B = [("one", 20.80), ("giant", 21.88), ("leap", 22.18)]
WORDS_A = [("That's", 15.48), ("one", 15.82), ("small", 16.30), ("step", 16.78), ("for", 17.18), ("man,", 17.40)]


def kill_cmd(k):
    kind, flash, text, paste, enter, end = k
    end = end if end is not None else LOGO
    t0 = flash + 0.1
    c = {"kind": kind, "app": KILL_APPS[kind], "flash": flash, "text": text, "t0": t0, "cps": 62, "enter": enter, "end": end, "where": "bar", "dim": 0.5}
    if paste:
        c.update({"paste": paste, "pasteAt": t0 + len(text) / 62 + 0.04})
    return c


APPS = [  # the pile: the six to be killed first and biggest, then the rest
    (KILL_APPS["download"], "reels"), (KILL_APPS["rmbg"], "smith"), (KILL_APPS["gif"], "gallop"),
    (KILL_APPS["translate"], "operator"), (KILL_APPS["currency"], "ticker"), (KILL_APPS["tile"], "typists"),
    ("HEIC to JPG Converter - Free Trial", "drawers"), ("Free Photo Converter HD", "card"), ("Clipboard Manager Pro", "cards"),
    ("Unit Converter", "telegraph"), ("Screen Recorder Free", "moonface"), ("Notes", "teleprinter"), ("File Finder Pro", "drawers"),
    ("Emoji Keyboard+", "crowd"), ("PDF Merge Online", "capsule"), ("Color Picker Free", "flag"), ("Calculator", "console"),
    ("Timer", "ignition"), ("Snippets", "typists"), ("Password Saver", "console"), ("Weather Widget", "earthorbit"),
    ("Dictionary", "card"), ("Music Downloader Pro", "reels"), ("Image Resizer Online", "smith"),
]
APP_T = [HEROES, HEROES + 0.3, HEROES + 0.6] + [round(BURST0 + (BURST1 - BURST0) * (1 - (1 - k / 20) ** 1.7), 4) for k in range(len(APPS) - 3)]

TM = {
    "beat": BEAT, "words1": WORDS1, "act2": ACT2, "line2": LINE2, "heroes": HEROES, "burst": [BURST0, BURST1], "heat0": HEAT0,
    "wall": [WALL0, WALL1], "meltCmd": MELT_CMD, "river": [RIVER0, RIVER1], "cast": CAST, "glass": GLASS, "line3": LINE3,
    "settle": SETTLE, "logo": LOGO, "end": END, "apps": APPS, "appT": APP_T,
    "stall": STALL, "caretAlone": CARET_ALONE, "music": MUSIC,
    "cmd0": {"text": "melt them down", "t0": CARET_ALONE + 0.35, "cps": 50, "enter": MELT_CMD, "out": MELT_CMD + 0.06, "dim": 0.3},
    "kills": [kill_cmd(k) for k in KILLS],
    "vo": {"a": VO_A, "segA": SEG_A, "b": round(VO_B, 4), "segB": SEG_B, "mankind": round(MANKIND_AT, 4), "end": round(VO_END, 4), "quindar": round(QUINDAR, 4)},
    "cool": COOL, "rate": "89.25",
    "wordsA": [[w, round(VO_A + (s - SEG_A[0]), 4)] for w, s in WORDS_A],
    "wordsB": [[w, round(b_at(s), 4)] for w, s in WORDS_B],
    "translateA": round(VO_A + (17.40 - SEG_A[0]) + 0.1, 4),    # as "man," lands, the line becomes Japanese
}

if __name__ == "__main__":
    with open(os.path.join(ROOT, "js", "timing.js"), "w") as f:
        f.write("// generated by tools/timing.py\nwindow.TM = " + json.dumps(TM) + ";\n")
    print(json.dumps({"vo": TM["vo"], "translateA": TM["translateA"], "appT": APP_T[:6]}))
