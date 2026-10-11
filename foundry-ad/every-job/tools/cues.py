#!/usr/bin/env python3
"""Every sound effect in "Every job.", as a sound-layer cue sheet built from tools/timing.py, so the sound moves when
the picture does. Each sound was picked by eye with `sfx.py browse` / `sfx.py sheet`; one family: the machines of
each era, metal, fire and a sub. `visual` names what the picture really does at that frame (measured on the render):
cut = full-frame change, move = frame of peak motion, appear = an element lands.

Spacing rule: mix.py turns a support sound down when its peak lands within 0.15 s of the previous one, so every
support peak keeps GAP from its neighbours and sounds that belong to one instant are layers of one cue ("a+b").
A typed command is one take (tools/takes.py renders it) accented in the gap between its neighbours.

usage: python3 tools/cues.py   -> audio/cues.json, audio/takes.json, audio/CREDITS.md
"""
import json, os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from timing import TM

GAP = 0.155
KIT = os.path.join(ROOT, "audio", "kit")
OWN_DIR = "audio/own"
WWS = "Wikimedia Commons, \"{}\" (World Wide Sounds), CC BY 4.0"
FS = "\"{}\" by {}, CC0, https://freesound.org/people/{}/sounds/{}"
OWN = {  # cut by tools/sources.sh (takes: tools/takes.py, credited through their kit keys)
    "typewriter": WWS.format("WWS Typewriter.ogg"),
    "anvil": WWS.format("WWS Blacksmith8217sanvil.ogg"),
    "whistle": WWS.format("WWS SteamWhistle.ogg"),
    "typing-pool": WWS.format("WWS Teleprintertyping.ogg"),
    "horses": "Wikimedia Commons, \"Six Horses Galloping By.ogg\", CC0",
    "phone-bell": FS.format("old phone ringtone Poland.wav", "blukotek", "blukotek", 245445),
    "morse": FS.format("kki-cw-2011-03-06.10.15cet.mp3", "ok1has", "ok1has", 116237),
    "computer": FS.format("Computer Sounds", "plasterbrain", "plasterbrain", 266165),

    "shuttle-roar": FS.format("shuttlelaunch.wav", "klangfabrik", "klangfabrik", 220127),
    "volcano": FS.format("S35-08 Volcano explosion with debris and lava", "craigsmith", "craigsmith", 675739),
    "furnace": FS.format("flame in furnace.wav", "jokallset", "jokallset", 395883),
    "sizzle": FS.format("Food Sizzling", "LanDub", "LanDub", 182393),
    "quench": FS.format("Food Sizzling", "LanDub", "LanDub", 182393),
    "sand": FS.format("pouring sand and salt 2.mp3", "mariethompson", "mariethompson", 516920),
    "train": FS.format("Train Passing By 113 with Steam Hissing and Puffing", "FunWithSound", "FunWithSound", 593038),
    "quindar": "Generated: NASA Quindar tones are pure sines (2525 Hz intro, 2475 Hz outro, 250 ms)",
}
KIT_CUTS = {  # audio/own/ files trimmed from kit sounds by tools/sources.sh; credited as their kit source
    "overheat": "glitch/fs-534735-digital-glitch-static-noise-1",
    "ignition-punch": "hit/fs-710368-cinematic-punch-1",
    "ignition-boom": "boom/fs-636624-deep-hit-2",
    "cast-hit": "hit/fs-359139-low-metal-hit-3-wav-1",
    "cast-sub": "boom/fs-268608-juno-sub-wav-1",
    "river-fall": "transition/fs-521040-whoosh-large-verb-er-sfx-6-w-1",
    "act2-thunk": "boom/fs-13895-43-wav-1",
    "pass-by": "transition/fs-522693-arrow-ghost-pass-whoosh-1",
}
def own(name): return f"{OWN_DIR}/{name}.wav"
SCORE_BEDS = ("shuttle-roar", "volcano", "furnace", "train")   # continuous roars, placed under the music by tools/score.py

K = {k["kind"]: k for k in TM["kills"]}
cues, takes = [], []
def cue(id_, t, sound, weight="support", visual=None, align="peak", pan=0.0, **kw):
    c = {"id": id_, "t": round(t, 4), "sound": sound, "weight": weight, "align": align, "pan": pan, **kw}
    if visual: c["visual"] = visual
    cues.append(c)

MODERN = ["key/fs-539146-keyboard-typing-001-wav-2", "key/fs-180974-key-1", "key/fs-539146-keyboard-typing-001-wav-3", "key/fs-194799-keyboard5-wav-1"]
FOUNDRY = ["key/fs-348239-mech-keyboard-01-wav-1", "key/fs-442649-keyboard-click-mp3", "key/fs-348238-mech-keyboard-02-wav-1"]
PASTE = "key/fs-180974-key-1"

def typed(tag, c, pool, after, before, pan=0.0):
    """One take for a typed command: a stroke on every third character as it appears, plus the paste; the stroke
    nearest the middle of (after + GAP, before - GAP) carries the accent and the cue."""
    t0, cps, text = c["t0"], c["cps"], c["text"]
    times = [t0 + i / cps for i in sorted(set(range(0, len(text), 3)) | {len(text) - 1})]
    strokes = [[t, pool[n % len(pool)]] for n, t in enumerate(times)]
    if c.get("paste"): strokes.append([c["pasteAt"], PASTE])
    strokes = [s for s in strokes if s[0] <= before - 0.07]    # nothing of the take inside the next event's sync window
    lo, hi = after + GAP, before - GAP
    inside = [s for s in strokes if lo <= s[0] <= hi]
    if not inside: sys.exit(f"{tag}: no stroke between {lo:.3f} and {hi:.3f}")
    acc = min(inside, key=lambda s: abs(s[0] - (lo + hi) / 2))
    takes.append({"name": f"take-{tag}", "strokes": [[round(t, 4), kid, 1.0 if [t, kid] == acc else (0.5, 0.62, 0.56)[n % 3]]
                                                    for n, (t, kid) in enumerate(strokes)]})
    cue(f"{tag}-typing", acc[0], own(f"take-{tag}"), pan=pan)

# ------------------------------------------------------------------ Act I: a typewriter strike per word, and that word's machine on it
MACHINE = {"typists": "typing-pool", "operator": "phone-bell", "telegraph": "morse", "console": "computer"}
PLATEN = "thump/fs-264879-three-dull-thumps-with-hamme-1"
words = TM["words1"]
for n, (w, t, clip) in enumerate(words[:-1]):
    cue(f"strike-{w}", t, f"{own(f'typewriter-{n + 1}')}+{own(MACHINE[clip])}+{PLATEN}", visual="cut" if t > 0 else None,
        pan=[0.0, -0.25, 0.25, -0.15][n])
IGN = words[-1][1]
cue("ignition", IGN, f"{own('ignition-punch')}+{own('ignition-boom')}+{own('typewriter-5')}",       # both stop on the Act II cut
    weight="hero", visual="cut", stop_before=True, build=True)
cue("carriage-bell", IGN + 0.45, "chime/fs-159011-ding2-wav-1", pan=0.4)

# ------------------------------------------------------------------ Act II: the I-beam, the pile of apps, the set overheats
A2, APP = TM["act2"], TM["appT"]
cue("act2", A2, own("act2-thunk"), visual="cut")
typed("line2", TM["line2"], MODERN, A2, APP[0])
# the apps land as bright ticks on the set's glass, above the groove (a heavier tap's body cancels against the kick)
for n, t in enumerate(APP[:3]):                                # the three apps you can read
    cue(f"app-{n}", t, f"tap/kenney-impact-impact-glass-light-00{[1, 2, 4][n]}+ui/kenney-interface-select-00{[3, 4, 7][n]}",
        visual="cut", pan=[-0.3, 0.3, 0.0][n])
OVERHEAT = TM["heat0"] + 0.558                                 # the static's loudest tear (audio/own/overheat.wav peak)
cue("overheat", TM["heat0"], own("overheat"), align="start", pan=0.1)
WALL_MOVE = 5.367                                              # peak camera speed of the pull-back (measured)
POPS = ["ui/kenney-interface-select-001", "ui/kenney-interface-select-003", "ui/kenney-interface-select-004", "ui/kenney-interface-select-007"]
last, n = APP[2], 0
for t in APP[3:]:                                              # then twenty more, rising as they pile up
    if t - last < GAP or abs(t - OVERHEAT) < GAP or t > WALL_MOVE - 0.25: continue      # clear of the whoosh's rise too
    cue(f"pile-{n}", t, POPS[n % len(POPS)], pan=0.5 if n % 2 else -0.5, pitch=round(n * 1.5, 1)); last, n = t, n + 1
cue("wall-pullback", WALL_MOVE, "whoosh/fs-30240-swoop1-flac-1", visual="move", pitch=-2)   # one clear apex (noise whooshes have none); bigger
WALL_PING = WALL_MOVE + 0.19                                   # the whole wall pings at once
cue("wall-ping", WALL_PING, "chime/fs-404104-glass-ding-3+chime/fs-127149-ding-wav-1+chime/fs-243701-correct-1", pan=0.0)

# ------------------------------------------------------------------ `melt them down`: three frames of nothing, then fire
MC = TM["meltCmd"]
typed("melt", TM["cmd0"], FOUNDRY, WALL_PING, MC)
MELT0 = MC + 0.05                                              # the enter is 3 frames before ignition: one event, the riser peaking on it
cue("melt", MELT0, "hit/fs-113747-kl-ex1bb-wav-2+boom/fs-105351-backfire-ogg-1+riser/fs-503801-reverse-fx-3-wav-1+key/fs-180997-enter-key-2",
    weight="hero", visual="cut", stop_before=True, build=True)                               # the roar after it: score.py

# ------------------------------------------------------------------ the casting: the river slams in, it sets, cracks, is knocked out to glass
CAST, C = TM["cast"], TM["cool"]
NUDGE = -0.003                                                    # sub-frame: keeps the slam in phase with the lava's tail
cue("cast", CAST + NUDGE, f"{own('cast-hit')}+{own('cast-sub')}+{own('river-fall')}",
    weight="hero", visual="move")
cue("cast-sizzle", CAST + 0.45, own("sizzle"), align="start")                                # peaks 0.23 s in
cue("cast-ping", CAST + C["gap0"], "tick/fs-185611-metal-tick-1-1", pan=-0.4)              # the iron pings as it contracts
cue("cast-sweep", CAST + C["sweep0"], "swish/fs-14176-28-wav-3", pan=-0.3)                   # the band of light
cue("knockout", CAST + C["knock0"], f"thump/fs-342535-medium-thud-1-2+{own('sand')}")
L3 = TM["line3"]
CARET = L3["t0"] - 0.08
for n, t in enumerate((CAST + C["flake0"] + 0.12, CARET - GAP - 0.005)):                     # the shell flakes off
    cue(f"flake-{n}", t, f"tap/kenney-impact-impact-metal-light-00{n + 1}", pan=[0.45, -0.3][n])
cue("caret", CARET, "click/kenney-interface-switch-002")
PLATE = 11.067                                                 # the bar settles and the plate cuts in (measured)
typed("line3", L3, FOUNDRY, CARET, PLATE)

# ------------------------------------------------------------------ the kills: summon, type, enter; each job sounds like itself
cue("plate", PLATE, "boom/fs-13875-23-wav-1", visual="cut")
SUMMON = "ui/kenney-interface-select-006"
ENTER = "key/fs-180997-enter-key-2"
kg, kr, kc, kt, kd, ktr = (K[n] for n in ("gif", "rmbg", "currency", "tile", "download", "translate"))
# gif: its flash lands a frame after the plate cut, so the plate's boom is its summon
typed("gif", kg, FOUNDRY, PLATE, kg["enter"], pan=0.1)
cue("gif-enter", kg["enter"], f"{own('anvil-1')}+boom/fs-13862-10-wav-1+{ENTER}", weight="hero", visual="cut")
cue("gif-gallop", kg["enter"] + 0.075, own("horses"), align="start", pan=-0.1)               # peaks 0.095 s in
cue("gif-push", 12.033, "whoosh/fs-30240-swoop1-flac-1", visual="move")                      # the camera pushes into one panel
cue("rmbg-summon", kr["flash"], SUMMON, visual="cut")
typed("rmbg", kr, FOUNDRY, kr["flash"], kr["enter"], pan=0.1)
cue("rmbg-enter", kr["enter"], f"{own('anvil-2')}+{ENTER}", visual="cut")
cue("rmbg-wipe", kr["enter"] + 0.025, "whoosh/fs-449988-whoosh-med-high-1", align="start", pan=-0.3)   # peaks 0.13 s in
# the horse bolts out of frame and the currency bar cuts in on the same frame
cue("currency-summon", kc["flash"], f"whoosh/fs-449992-whoosh-short-low-wav-1+{SUMMON}", visual="cut", pan=0.3)
typed("currency", kc, FOUNDRY, kc["flash"], kc["enter"], pan=0.1)
cue("currency-enter", kc["enter"], f"{own('anvil-3')}+{ENTER}", visual="appear")
cue("currency-reels", kc["enter"] + 0.17, "tick/fs-386206-ratchet-stahlwille-tighten-1-3", pan=-0.2)   # the reels spin
cue("currency-land", kc["enter"] + 0.34, "key/fs-348240-cashier-register-keyboard-be-1")              # and land on 89.25
cue("tile-summon", kt["flash"], SUMMON, visual="cut")
typed("tile", kt, FOUNDRY, kt["flash"], kt["enter"], pan=0.1)
cue("tile-enter", kt["enter"], f"{own('anvil-4')}+{ENTER}", visual="move")
for n in (2, 4):                                               # the splits snap shut on their seams (one every 0.09 s)
    cue(f"tile-snap-{n}", kt["enter"] + n * 0.09, "click/kenney-rpg-metal-latch" if n == 2 else "click/kenney-rpg-metal-click",
        pan=0.4 if n == 2 else -0.4)
cue("download-summon", kd["flash"], SUMMON, visual="cut")
typed("download", kd, FOUNDRY, kd["flash"], kd["enter"], pan=0.1)
cue("download-enter", kd["enter"], f"{own('anvil-1')}+boom/fs-13875-23-wav-1+{ENTER}", weight="hero", visual="move")
cue("download-whistle", kd["enter"] + 0.05, own("whistle"), align="start", pan=0.2)           # peaks 0.28 s in
# the train comes through the lens into the moon: the pass-by peaks on the cut, with the bar's summon
cue("translate-summon", ktr["flash"], f"{own('pass-by')}+{SUMMON}", visual="cut")
typed("translate", ktr, FOUNDRY, ktr["flash"], ktr["enter"], pan=0.1)
cue("translate-quindar", ktr["enter"], own("quindar-in"), visual="cut", align="start")        # a steady tone: it starts on the cue

# ------------------------------------------------------------------ the logo: back through the tiles, "...mankind.", end of transmission
LOGO_MOVE = TM["logo"] + 0.45                                  # peak speed of the pull-back through the tiles
cue("logo", LOGO_MOVE, "reverse/fs-244837-rev-cymb-23-wav-1+boom/fs-268608-juno-sub-wav-1", weight="hero", visual="move")
cue("logo-cool", TM["logo"] + 0.52, own("quench"), align="start")                            # the first tiles go white-hot (film.js logo ign); peaks 0.21 s in
cue("quindar-out", TM["vo"]["quindar"], own("quindar-out"), align="start")

sheet = {
    "fps": 60, "duration_s": TM["end"], "energy": "punchy", "kit": "audio/kit",
    "music": {"file": "audio/music.wav", "start_s": 0, "loop": False, "fade_out_s": 0.25},
    "voice": [{"file": "audio/voice.wav", "start_s": 0}],
    "duck_db": 6,                                              # Armstrong is already compressed and lifted; 6 dB keeps him 15 LU clear
    "silence_ok": [[round(TM["vo"]["quindar"] + 0.1, 2), TM["end"]]],
    "cues": cues,
}
with open(os.path.join(ROOT, "audio", "cues.json"), "w") as f: json.dump(sheet, f, indent=1)
with open(os.path.join(ROOT, "audio", "takes.json"), "w") as f: json.dump(takes, f, indent=1)

# ------------------------------------------------------------------ credits: every recording the mix uses
cat = {e["id"]: e for e in json.load(open(os.path.join(KIT, "catalog.json")))["sounds"]}
full = dict(l[2:].split(": ", 1) for l in open(os.path.join(KIT, "CREDITS.md")) if re.match(r"- \w+/\S+: ", l))
def kit_credit(kid): return full.get(kid, f"{cat[kid]['credit']}, CC0").strip()   # Kenney packs are credited per pack
tokens = ([tok for c in cues for tok in c["sound"].split("+")] + [kid for tk in takes for _, kid, _ in tk["strokes"]]
          + [own(b) for b in SCORE_BEDS])
lines, missing = set(), []
for tok in tokens:
    if tok.startswith(OWN_DIR):
        name = os.path.basename(tok)[:-4]
        if name.startswith("take-"): continue
        src = "quindar" if name.startswith("quindar") else re.sub(r"-\d+$", "", name)
        if name in KIT_CUTS: lines.add(f"- {name}: cut from {KIT_CUTS[name]}, {kit_credit(KIT_CUTS[name])}")
        elif src in OWN: lines.add(f"- {name}: {OWN[src]}")
        else: missing.append(tok)
    elif tok in cat: lines.add(f"- {tok}: {kit_credit(tok)}")
    else: missing.append(tok)
if missing: sys.exit(f"unknown sounds: {sorted(set(missing))}")
with open(os.path.join(ROOT, "audio", "CREDITS.md"), "w") as f:
    f.write("# Sound effect credits\n\nEvery recording placed by `tools/cues.py`. Kit sounds come from the sound-layer library "
            "(Kenney packs and Freesound, CC0); `audio/own/` files are cut by `tools/sources.sh`, and the typing takes are "
            "built by `tools/takes.py` from the kit keys below. Music and voice: see SOURCES.md.\n\n"
            + "\n".join(sorted(lines)) + "\n")
print(f"{len(cues)} cues, {sum(c['weight'] == 'hero' for c in cues)} heroes, {len(takes)} takes, {len(lines)} credited sounds")
