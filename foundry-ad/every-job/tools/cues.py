#!/usr/bin/env python3
"""Every sound effect in "Every job.", as a sound-layer cue sheet built from tools/timing.py, so the sound moves when
the picture does. Few sounds, all clean and computed (tools/sfx.py): soft laptop keys, one enter key, one low drum. `visual` names what the picture really does at that frame (measured on the render):
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
ONSET = 0.008                                                  # an enter's peak lands half a frame late, so its attack starts on the frame
KIT = os.path.join(ROOT, "audio", "kit")
OWN_DIR = "audio/own"
WWS = "Wikimedia Commons, \"{}\" (World Wide Sounds), CC BY 4.0"
FS = "\"{}\" by {}, CC0, https://freesound.org/people/{}/sounds/{}"
OWN = {  # cut by tools/sources.sh (takes: tools/takes.py, credited through their kit keys)
    "typewriter": FS.format("secretary typing on 1940s mechanical typewriter", "PostProdDog", "PostProdDog", 550859),
    "carriage": FS.format("Typewriter bell & carriage reset", "knufds", "knufds", 345955),
    "relay": FS.format("relays-fast-switching.aiff", "kasparsj", "kasparsj", 513886),
    "ignition-crack": FS.format("Whip Cracks.WAV", "G.Lamont", "G.Lamont", 118068),
    "ignition-rumble": FS.format("Rocket Launch Rumble (Geofon recording)", "felix.blume", "felix.blume", 613617),
    "glass-alegemaate": FS.format("Glass Tap", "alegemaate", "alegemaate", 667275),
    "glass-cjspellsfish": FS.format("Glass Tap 2", "CJspellsfish", "CJspellsfish", 668383),
    "glass-rutgermuller": FS.format("Glass Tapped By Fingernail.wav", "RutgerMuller", "RutgerMuller", 51038),
    "glass-tairblenn-medium": FS.format("medium wine glass.wav", "Tairblenn", "Tairblenn", 549900),
    "glass-tairblenn-small": FS.format("small wine glass.wav", "Tairblenn", "Tairblenn", 549899),
    "glass-soundbiter": FS.format("Wine Glass Clinking", "SoundBiterSFX", "SoundBiterSFX", 730951),
    "glass-holden": FS.format("OWI_Crystal class ping.wav", "matthewHoldenSound", "matthewHoldenSound", 542561),
    "anvil": WWS.format("WWS Blacksmith8217sanvil.ogg"),
    "whistle": WWS.format("WWS SteamWhistle.ogg"),
    "typing-pool": WWS.format("WWS Teleprintertyping.ogg"),
    "typing-pool-room": WWS.format("WWS Teleprintertyping.ogg"),
    "horses": FS.format("R14-38-Horse Gallops on Cobblestone.wav", "craigsmith", "craigsmith", 479769),
    "phone-bell": FS.format("old phone ringtone Poland.wav", "blukotek", "blukotek", 245445),
    "morse": FS.format("kki-cw-2011-03-06.10.15cet.mp3", "ok1has", "ok1has", 116237),

    "launch-roar": FS.format("shuttlelaunch.wav", "klangfabrik", "klangfabrik", 220127),
    "shuttle-roar": FS.format("shuttlelaunch.wav", "klangfabrik", "klangfabrik", 220127),
    "volcano": FS.format("S35-08 Volcano explosion with debris and lava", "craigsmith", "craigsmith", 675739),
    "furnace": FS.format("flame in furnace.wav", "jokallset", "jokallset", 395883),
    "sizzle": FS.format("Food Sizzling", "LanDub", "LanDub", 182393),
    "sand": FS.format("pouring sand and salt 2.mp3", "mariethompson", "mariethompson", 516920),
    "train": FS.format("Train Passing By 113 with Steam Hissing and Puffing", "FunWithSound", "FunWithSound", 593038),
    "cheer": FS.format("Crowd.Yay.Applause.25ppl.Medium.wav", "jessepash", "jessepash", 139971),
    "applause": FS.format("Short Crowd Cheer 2.flac", "qubodup", "qubodup", 182572),
    "orch-swell": FS.format("Music Dramatic Orchestral Ending 3.mp3", "FunWithSound", "FunWithSound", 588391) + ", 4.0-10.0 s",
    "quindar": "Generated: NASA Quindar tones are pure sines (2525 Hz intro, 2475 Hz outro, 250 ms)",
    "sfx-key": "Computed by tools/sfx.py (no recording)", "sfx-enter": "Computed by tools/sfx.py (no recording)",
    "sfx-logo": "Computed by tools/sfx.py (no recording)",
}
KIT_CUTS = {  # audio/own/ files trimmed from kit sounds by tools/sources.sh; credited as their kit source
    "ignition-punch": "hit/fs-710368-cinematic-punch-1",
    "ignition-boom": "boom/fs-636624-deep-hit-2",
    "backfire": "boom/fs-105351-backfire-ogg-1",
    "cast-hit": "hit/fs-359139-low-metal-hit-3-wav-1",
    "timpani-short": "hit/fs-573245-dark-timpani-1-wav-1", "timpani-arrival": "hit/fs-573245-dark-timpani-1-wav-1",
    "cast-sub": "boom/fs-268608-juno-sub-wav-1",
    "river-fall": "transition/fs-521040-whoosh-large-verb-er-sfx-6-w-1",
    "act2-thunk": "boom/fs-13895-43-wav-1",
    "pass-by": "transition/fs-522693-arrow-ghost-pass-whoosh-1",
    "anvil-body": "thump/fs-585575-metal-thud-1",
    "enter-1": "key/fs-180997-enter-key-2", "enter-2": "key/fs-180997-enter-key-2", "enter-3": "key/fs-180997-enter-key-2",
    "enter-4": "key/fs-180997-enter-key-2", "enter-5": "key/fs-180997-enter-key-2",
}
def own(name): return f"{OWN_DIR}/{name}.wav"


K = {k["kind"]: k for k in TM["kills"]}
cues, takes = [], []
def cue(id_, t, sound, weight="support", visual=None, align="peak", pan=0.0, **kw):
    c = {"id": id_, "t": round(t, 4), "sound": sound, "weight": weight, "align": align, "pan": pan, **kw}
    if visual: c["visual"] = visual
    cues.append(c)

MODERN = ["key/fs-539146-keyboard-typing-001-wav-2", "key/fs-180974-key-1", "key/fs-539146-keyboard-typing-001-wav-3", "key/fs-194799-keyboard5-wav-1"]
FOUNDRY = ["key/fs-348239-mech-keyboard-01-wav-1", "key/fs-442649-keyboard-click-mp3", "key/fs-348238-mech-keyboard-02-wav-1"]
PASTE = own("sfx-key-2")

def typed(tag, c, pool, after, before, pan=0.0, first=False, skip_until=None, step=3, weight="support", soft=(0.5, 0.62, 0.56)):
    """One take for a typed command: a stroke on every `step`th character as it appears, plus the paste; the stroke
    nearest the middle of (after + GAP, before - GAP) carries the accent and the cue, or the first stroke when the
    picture changes on it (`first`)."""
    t0, cps, text = c["t0"], c["cps"], c["text"]
    times = [t0 + i / cps for i in sorted(set(range(0, len(text), step)) | {len(text) - 1})]
    strokes = [[t, pool[n % len(pool)]] for n, t in enumerate(times)]
    if c.get("paste"): strokes.append([c["pasteAt"], PASTE])
    strokes = [s for s in strokes if s[0] <= before - 0.07]    # nothing of the take inside the next event's sync window
    if skip_until: strokes = [s for s in strokes if s[0] > skip_until]     # a stroke the cue before already plays
    lo, hi = after + GAP, before - GAP
    inside = [s for s in strokes if lo <= s[0] <= hi]
    if not inside: sys.exit(f"{tag}: no stroke between {lo:.3f} and {hi:.3f}")
    acc = inside[0] if first else min(inside, key=lambda s: abs(s[0] - (lo + hi) / 2))
    takes.append({"name": f"take-{tag}", "strokes": [[round(t, 4), kid, 1.0 if [t, kid] == acc else soft[n % 3]]
                                                    for n, (t, kid) in enumerate(strokes)]})
    cue(f"{tag}-typing", acc[0], own(f"take-{tag}"), weight=weight, pan=pan)

# ------------------------------------------------------------------ few sounds, all clean: the music carries the film
# Typing is heard only where a command is typed (soft laptop keys, one take each, support). Each enter is one enter
# key; the melt's enter is also the beat drop (score.py). The name lands on one low drum in D. All three are computed
# by tools/sfx.py. Nothing else:
# the archive, the apps, the casting, the results and the climax are carried by the score and Armstrong.
SOFT = [own(f"sfx-key-{i}") for i in range(1, 5)]
ENTER = own("sfx-enter")
LOGO_HIT = own("sfx-logo")
MC, L3 = TM["meltCmd"], TM["line3"]
typed("melt", TM["cmd0"], SOFT, TM["cmd0"]["t0"] - GAP, MC, first=True)
NUDGE = {"melt": -0.003, "gif": -0.003}   # sub-frame: the key's transient sits wholly inside qa's 50 ms window
cue("melt", MC + ONSET + NUDGE["melt"], ENTER, weight="hero", visual="cut")
PLATE = round(round((TM["settle"] + 0.06) * 60 + 0.5) / 60, 4)   # the bar settles and the plate cuts in (film.js: settle + 0.06, next frame)
typed("line3", L3, SOFT, L3["t0"] - GAP, PLATE, first=True)
for n, c in enumerate(TM["kills"][:-1]):
    typed(c["kind"], c, SOFT, (c["flash"] if n else PLATE) - GAP, c["enter"], first=True)
    cue(f"{c['kind']}-enter", c["enter"] + ONSET + NUDGE.get(c["kind"], 0.0), ENTER, weight="hero", visual="cut")
cue("logo", TM["logo"], LOGO_HIT, weight="hero", visual="cut", align="start")

sheet = {
    "fps": 60, "duration_s": TM["end"], "energy": "punchy", "kit": "audio/kit",
    "music": {"file": "audio/music.wav", "start_s": 0, "loop": False, "fade_out_s": 0.25},
    "silence_ok": [[TM["stall"], MC], [TM["kills"][-1]["enter"], dict(TM["music"])["leap"]], [TM["kills"][-1]["live"]["stop"], TM["logo"]]],
    "cues": cues,
}
with open(os.path.join(ROOT, "audio", "cues.json"), "w") as f: json.dump(sheet, f, indent=1)
with open(os.path.join(ROOT, "audio", "takes.json"), "w") as f: json.dump(takes, f, indent=1)

# ------------------------------------------------------------------ credits: every recording the mix uses
cat = {e["id"]: e for e in json.load(open(os.path.join(KIT, "catalog.json")))["sounds"]}
full = dict(l[2:].split(": ", 1) for l in open(os.path.join(KIT, "CREDITS.md")) if re.match(r"- \w+/\S+: ", l))
def kit_credit(kid): return full.get(kid, f"{cat[kid]['credit']}, CC0").strip()   # Kenney packs are credited per pack
tokens = ([tok for c in cues for tok in c["sound"].split("+")] + [kid for tk in takes for _, kid, _ in tk["strokes"]]
          + [own("quindar-in")])
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
