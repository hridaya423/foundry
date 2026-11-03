#!/usr/bin/env python3
"""Single source of truth for "Every job." (v2). Writes js/timing.js (window.TM); tools/score.py imports it.

  A machine for every job.   typewriter-struck, a machine per word, in an amber tube
  An app for every job.      typed with an I-beam; the apps pile up; the set overheats; a wall of sets
  `melt them down`           every screen ignites; the metal braids into one river; it fills a mould
  One for every job.         the mould is Foundry's bar; it cools to iron and becomes the bar
  six kills                  each app from the wall comes back, burns, and one line does its job
  logo                       back through tiles that hold the whole film; "...for mankind." lands on it
"""
import json, math, os, re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BEAT = 0.5


def on_frame(t):
    """the nearest 60 fps frame (a tie goes later): a picture change and its sound land on the same frame"""
    return round(math.floor(t * 60 + 0.5) / 60, 4)


# ---------------------------------------------------------------- Act I: one word, one machine, one beat
WORDS1 = [("A", 0.0, "typists"), ("machine", 0.5, "operator"), ("for", 1.0, "telegraph"), ("every", 1.5, "console"), ("job.", 2.0, "ignition")]
ACT2 = 2.8
# ---------------------------------------------------------------- Act II
LINE2 = {"text": "An app for every job.", "t0": ACT2, "cps": 52}     # its first key lands on the cut
# the apps land in time with the score: its beat falls 2 frames after the 0.5 s grid (earshot: 3.03, 3.53, 4.03...)
PILE_GRID = 0.125
def on_grid(t): return on_frame(round((t - 2 / 60) / PILE_GRID) * PILE_GRID + 2 / 60)
HEROES = on_grid(3.25)           # the first three apps, big enough to read, an eighth apart
BURST0, BURST1 = 4.45, 5.25      # then everything else (the three titles hold 0.65-1.15 s first)
HEAT0 = 4.3                      # the set starts to struggle
WALL0, WALL1 = 5.0, 5.7          # pull back: a wall of sets, then hold on it
# the valley: everything stalls (picture freezes, the music tape-stops into a ringing), one caret blinks alone,
# `melt them down` is typed into the silence, and its enter is the drop, on beat 14
STALL = 5.75
CARET_ALONE = 5.8                # the caret waits as the wall settles, and the verb is typed over it
MELT_CMD = 7.0
D_MELT = MELT_CMD - 6.2          # how far everything after the melt moved when the valley went in
RIVER_CUT = 0.6                  # the river runs 1.05 s, so "One for every job." holds a full second before the plates
RIVER0, RIVER1 = 6.95 + D_MELT, 8.6 + D_MELT - RIVER_CUT       # the camera falls with the river
CAST = 8.6 + D_MELT - RIVER_CUT
# the casting cools from the rim in; its last heat retreats to where the cursor lives and becomes the caret
# (cooled 14% faster than first cut, so the glass bar holds a breath of quiet before the kills: the plate stays on SETTLE)
COOL_K = 0.86
COOL = {k: round(v * COOL_K, 3) for k, v in {"fill": 0.0, "core0": 0.55, "core1": 1.45, "gap0": 0.9, "gap1": 1.45,
        "knock0": 1.4, "knock1": 1.78, "flake0": 1.45, "flake1": 1.82, "point": 1.82}.items()}
GLASS = round(CAST + 1.8 * COOL_K, 4)
LINE3 = {"text": "One for every job.", "t0": GLASS + 0.16, "cps": 54}
SETTLE = 11.0 + D_MELT           # the first plate cuts in here
BARDOWN = round(SETTLE - 0.45, 4) # the bar docks on black before the plate arrives, so nothing slides over the picture

# ---------------------------------------------------------------- the kills: app -> command -> result
KILL_APPS = {
    "gif": "GIF Maker Pro",
    "rmbg": "Background Eraser Online",
    "translate": "Translate",
    "currency": "Currency Converter Plus",
    "tile": "Window Snap",
    "download": "YouTube Downloader MP4 (No Virus)",
}
# Each command is typed over the last result (the picture waits, dimmed) and its enter is the next state change.
# Enters on the 16th-note grid, each sooner than the last (1.25, 1.125, 1, 0.875 s), and each typed faster; the
# download's train then cuts to the moon.
KILLS = [  # (kind, enter, text, cps, paste)
    ("gif", 12.5, "convert to gif", 62, None),            # typed over the plate as it cuts in
    ("rmbg", 13.75, "remove background", 66, None),
    ("currency", 14.875, "100 usd in eur", 72, None),
    ("tile", 15.875, "tile windows", 80, None),
    ("download", 16.75, "download ", 88, "youtu.be/lumiere-1895"),
]
GIF_FLASH = 12.0                 # the plate has cut in; the bar starts the first command
HOLD = 0.11                      # the whole command sits in the bar this long before enter
# the moon: no command. The picture cuts from the train to the moon, struck like every enter, and he speaks into the bar
MOON = on_frame(17.983)
LEAP_AT = on_frame(18.375)       # the score's last section starts here; the beat grid hangs from it

# ---------------------------------------------------------------- Armstrong, whole: "That's one small step for man, one giant leap for mankind."
SEG_A = (15.40, 17.75)
SEG_B = [(20.72, 21.02, 0.05), (21.80, 23.64, 0.0)]   # "one", a breath, "giant leap for mankind."
A_GAP = 0.22                     # his pause, a breath: the flag cut comes on the next beat after "man," and nothing waits
VO_A = on_frame(MOON + 0.15)     # the channel opens on the cut (Quindar) and his first word is typed 0.08 s after it
VO_B = VO_A + (SEG_A[1] - SEG_A[0]) + A_GAP
# "mankind." starts, his voice ends (after it the downlink's static: earshot hears a scratch, not speech), the word is
# said with its static, and the channel closes
MANKIND_SRC, VOICED_SRC, SAID_SRC, END_SRC = 22.74, 23.27, 23.58, 23.64


def b_at(src):
    s0, s1, g = SEG_B[0]
    return VO_B + (src - s0) if src <= s1 else VO_B + (s1 - s0) + g + (src - SEG_B[1][0])


MANKIND_AT, VO_END = b_at(MANKIND_SRC), b_at(END_SRC)
QUINDAR_IN = MOON                    # the struck cut opens the channel
# the score (tools/music.py): one composition, five sections; boundaries on the bar grid where they can be
MUSIC = [("lineage", 0.0), ("weight", 3.0), ("drop", MELT_CMD), ("build", 12.0), ("leap", LEAP_AT)]
WORDS_B = [("one", 20.80), ("giant", 21.88), ("leap", 22.18), ("for", 22.56), ("mankind.", MANKIND_SRC)]
WORDS_A = [("That's", 15.48), ("one", 15.82), ("small", 16.30), ("step", 16.78), ("for", 17.18), ("man,", 17.40)]
# the leap's beat: every 0.5 s from LEAP - 0.25 (the ending is placed on it: score.py SKIP)
GRID = [round(on_frame(LEAP_AT) - 0.25 + BEAT * k, 4) for k in range(1, 40)]
# Armstrong lives in the bar: each word appears as he starts to say it (LEAD: measured onsets are 0.03-0.17 s before
# WORDS_*, so the type leads the voice instead of trailing it like a subtitle). Above it Foundry speaks Japanese with him,
# a phrase at a time on his words: line A's under his first half (it goes as the picture cuts to the flag), line B's
# under his second, whole on the cut to the Earth and held there into the logo.
LEAD = 0.12
RISE = on_frame(max(b for b in GRID if b < b_at(WORDS_B[0][1]) - 0.1))
ARRIVE = on_frame(min(b for b in GRID if b >= b_at(SAID_SRC) + 0.1))
EARTH_HOLD = 1.5                 # the Earth carries the frame from the arrival, and the camera dives into it for the name
LOGO = on_frame(min(b for b in GRID if b >= ARRIVE + EARTH_HOLD))
MUSIC.append(("card", LOGO))      # the score resolves on the name
# the picture cuts to the Earth as he says "mankind." and the score swells under it, the camera pushing in. The arrival
# lights it; then the camera dives at the Earth, the score stops, the bar holds in the silence, and its caret leaves for
# the name. The name cuts in as a window onto the Earth
EARTH = on_frame(MANKIND_AT)
STOP, DEPART, LET_GO = 0.4, 0.2, 0.12  # the score stops this long before the logo; the bar holds still in the silence until its
# caret leaves (DEPART before the logo) and flies straight into the name; the bar and its line are gone LET_GO after
# the end card: the Earth holds in the name for two beats, then it ignites white-hot as one casting and cools to iron
# as it steps back; two beats on, the line lands under it (the last hit) and the caret lights after the name; it holds,
# the Quindar out-tone ends the transmission and the caret goes out on its frame, the chord decays under the held card,
# then 0.5 s of silence
IGNITE = on_frame(LOGO + 2 * BEAT)
PRESS = on_frame(IGNITE + 2 * BEAT)
SIGN_OFF = on_frame(PRESS + 3 * BEAT)
DECAY, ROOM = 0.9, 1.0
END = round(SIGN_OFF + DECAY + ROOM, 2)
PULSE = [b for b in GRID if b < ARRIVE]
def typed_as_said(words, end):
    """each word with the time its letters take to appear: until just before the next word (or `end`), as long as he says it"""
    return [[w, at, round(max(0.06, (words[k + 1][1] if k + 1 < len(words) else end) - at - 0.06), 4)] for k, (w, at) in enumerate(words)]


LINE_A = [(w, round(VO_A + (s - SEG_A[0]) - LEAD, 4)) for w, s in WORDS_A]
LINE_B = [(w, RISE if k == 0 else EARTH if w == "mankind." else round(b_at(s) - LEAD, 4)) for k, (w, s) in enumerate(WORDS_B)]
# the Japanese, a phrase on each of his words, in Japanese order: "for man / small / one step" lands on "one / small /
# step" and is whole well before the flag cut; "for mankind / giant / leap" lands on "giant / leap / mankind.", whole on
# the cut to the Earth
JA = [{"p": [["人間にとっては", LINE_A[1][1]], ["小さな", LINE_A[2][1]], ["一歩だが、", LINE_A[3][1]]], "until": RISE},
      {"p": [["人類にとっては", LINE_B[1][1]], ["偉大な", LINE_B[2][1]], ["飛躍である。", EARTH]], "until": ARRIVE}]


LIVE = {
    "a": typed_as_said(LINE_A, round(LINE_A[-1][1] + 0.3, 4)), "ja": JA, "rise": RISE,
    # "one" is in the bar on the flag-cut frame and "mankind." on the Earth-cut frame, typed until his voice ends: the
    # period lands with the word, not with the static after it
    "b": typed_as_said(LINE_B, b_at(VOICED_SRC)),
    "answers": [],
    "stop": round(LOGO - STOP, 4), "letGo": round(LOGO - DEPART, 4), "gone": round(LOGO - DEPART + LET_GO, 4), "earth": EARTH,
}

def kill_cmds():
    """The kills as the picture and the cue sheet use them: `flash` clears the bar and dims the result (from the second
    kill on, the first keystroke lands on it), typing runs from `t0`, `end` is where the next kill takes the bar."""
    out = []
    for i, (kind, enter, text, cps, paste) in enumerate(KILLS):
        typing, enter = len(text) / cps + (0.04 if paste else 0.0), on_frame(enter)
        t0 = GIF_FLASH + 0.1 if i == 0 else on_frame(enter - typing - HOLD)
        c = {"kind": kind, "app": KILL_APPS[kind], "flash": GIF_FLASH if i == 0 else t0, "text": text, "t0": t0,
             "cps": cps, "enter": enter, "where": "bar", "dim": 0.5}
        if paste:
            c.update({"paste": paste, "pasteAt": round(t0 + len(text) / cps + 0.04, 4)})
        out.append(c)
    # the moon: nothing typed; the cut is its enter, and the bar goes live on it
    out.append({"kind": "translate", "app": KILL_APPS["translate"], "flash": round(MOON - 1 / 60, 4), "text": "", "t0": MOON, "cps": 1,
                "enter": MOON, "where": "bar", "dim": 0.5, "live": LIVE})
    for a, b in zip(out, out[1:]):
        a["end"] = b["flash"]
    out[-1]["end"] = LOGO
    return out


APPS = [  # the pile: the six to be killed first and biggest, then the rest
    (KILL_APPS["download"], "reels"), (KILL_APPS["rmbg"], "smith"), (KILL_APPS["gif"], "gallop"),
    (KILL_APPS["translate"], "operator"), (KILL_APPS["currency"], "ticker"), (KILL_APPS["tile"], "typists"),
    ("HEIC to JPG Converter - Free Trial", "drawers"), ("Free Photo Converter HD", "card"), ("Clipboard Manager Pro", "cards"),
    ("Unit Converter", "telegraph"), ("Screen Recorder Free", "moonface"), ("Notes", "teleprinter"), ("File Finder Pro", "drawers"),
    ("Emoji Keyboard+", "crowd"), ("PDF Merge Online", "capsule"), ("Color Picker Free", "flag"), ("Calculator", "console"),
    ("Timer", "ignition"), ("Snippets", "typists"), ("Password Saver", "console"), ("Weather Widget", "earthorbit"),
    ("Dictionary", "card"), ("Music Downloader Pro", "reels"), ("Image Resizer Online", "smith"),
]
APP_T = [on_grid(HEROES + 0.25 * k) for k in range(3)] + [on_grid(BURST0 + (BURST1 - BURST0) * (1 - (1 - k / 20) ** 1.7)) for k in range(len(APPS) - 3)]

TM = {
    "beat": BEAT, "words1": WORDS1, "act2": ACT2, "line2": LINE2, "heroes": HEROES, "burst": [BURST0, BURST1], "heat0": HEAT0,
    "wall": [WALL0, WALL1], "meltCmd": MELT_CMD, "river": [RIVER0, RIVER1], "cast": CAST, "glass": GLASS, "line3": LINE3,
    "settle": SETTLE, "bardown": BARDOWN, "logo": LOGO, "ignite": IGNITE, "press": PRESS, "signOff": SIGN_OFF, "decay": DECAY, "end": END, "apps": APPS, "appT": APP_T,
    "stall": STALL, "caretAlone": CARET_ALONE, "music": MUSIC,
    "cmd0": {"text": "melt them down", "show": CARET_ALONE, "t0": CARET_ALONE + 0.25, "cps": 22, "size": 168, "enter": MELT_CMD, "out": MELT_CMD + 0.06, "dim": 0.3},
    "kills": kill_cmds(),
    "pulse": PULSE, "quindarIn": QUINDAR_IN, "arrive": ARRIVE,
    "vo": {"a": VO_A, "segA": SEG_A, "b": round(VO_B, 4), "segB": SEG_B, "mankind": round(MANKIND_AT, 4), "end": round(VO_END, 4)},
    "cool": COOL, "rate": "89.25",
}

if __name__ == "__main__":
    with open(os.path.join(ROOT, "js", "timing.js"), "w") as f:
        f.write("// generated by tools/timing.py\nwindow.TM = " + json.dumps(TM) + ";\n")
    index = os.path.join(ROOT, "index.html")
    html = open(index).read()
    open(index, "w").write(re.sub(r'data-duration="[0-9.]+"', f'data-duration="{END}"', html))
    print(json.dumps({"vo": TM["vo"], "rise": RISE, "appT": APP_T[:6]}))
