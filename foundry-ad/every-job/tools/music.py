#!/usr/bin/env python3
"""The score: one ElevenLabs composition whose sections are timing.py's MUSIC, so picture and music share one grid.

usage: tools/music.py SEED [SEED ...]     writes audio/music/take-SEED.mp3 (+ .json: plan, song id); skips existing
       tools/music.py --end TAKE SEED ...  endings in TAKE's voice (audio/music/end-TAKE-SEED.mp3)
Reads ELEVENLABS_API_KEY from the environment (set -a; . ../../.env). The valley (STALL..MELT_CMD) is generated
through and cut in the edit (score.py): sections can't be shorter than 3 s.
"""
import json, os, sys, time, urllib.error, urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import timing as T

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "audio", "music")

GLOBAL = ["cinematic hybrid orchestral score for a premium tech launch film", "120 BPM, 4/4, in B-flat minor",
          "one simple memorable three-note motif (B-flat, C, F) that every section is built on",
          "industrial percussion: anvil strikes, metallic impacts, typewriter rhythm", "deep clean sub bass",
          "minimal, modern, restrained, emotional", "great production quality, wide stereo, clean mix"]
NEGATIVE = ["vocals", "singing", "choir with words", "EDM", "dubstep", "cheesy", "comedic", "lo-fi", "guitar solo", "ukulele"]
# inline directions per section: the model ramps into sections unless told the event is on the first beat
DIRECT = {
    "lineage": "{solo felt piano plays the three-note motif from the very first beat}",
    "weight": "{tension rises relentlessly to the last beat}",
    "drop": "{enormous orchestral impact on the very first beat, no ramp, no build-up}",
    "build": "{full driving rhythm from the very first beat}",
    "leap": "{near silence for four seconds}{then a slow swell}{the final chord rings out to the very end, no fade-out}",
}
SECTIONS = {
    "lineage": ["intimate", "the motif on a single felt piano, one note on each beat", "soft low string drone",
                "warm, nostalgic, proud", "very sparse"],
    "weight": ["the same motif repeated faster and higher, tightening", "string ostinato building pressure",
               "dissonant clusters creeping in", "ticking percussion accelerating", "anxious, claustrophobic crescendo",
               "everything piling up"],
    "drop": ["massive drop exactly on the first beat", "huge low brass and distorted sub impact",
             "full orchestra with taiko and anvil hits", "the motif in full power on brass",
             "after three seconds it settles into one long sustained low note with shimmering high strings", "relief"],
    "build": ["driving propulsive rhythm, sixteenth-note pulse", "the motif on strings, confident and joyful",
              "percussion building bar by bar", "steadily rising energy", "momentum"],
    "leap": ["drops to near silence", "a single sustained high string note and the soft piano motif", "spacious, awe, wonder",
             "slow swell in the final four seconds", "resolves on a warm B-flat major chord", "ends cleanly with a ringing tail"],
}


def plan():
    edges = [t for _, t in T.MUSIC] + [T.END]
    chunks = []
    for i, (name, t0) in enumerate(T.MUSIC):
        styles = (GLOBAL + SECTIONS[name]) if i == 0 else SECTIONS[name] + ["great production quality"]
        chunks.append({"text": f"[{name.capitalize()}] {{instrumental}}{DIRECT[name]}", "duration_ms": round((edges[i + 1] - t0) * 1000),
                       "positive_styles": styles, "negative_styles": NEGATIVE + (["fade out"] if name == "leap" else []),
                       "context_adherence": "high"})
    return {"chunks": chunks}


def ending(ref):
    """The leap, as its own piece in the take's voice: generated past the film's end, because the model fades out
    whatever it is asked for; the hush runs to "one giant leap", the swell crests through "mankind", then it rings."""
    song = json.load(open(os.path.join(OUT, f"take-{ref}.json")))["song_id"]
    leap = dict(T.MUSIC)["leap"]
    edges = [leap, T.VO_B, T.VO_B + 3.0, T.END + 3.5]
    parts = [("Hush", ["drops to near silence", "a single sustained high string note", "the soft felt piano motif, slow", "awe, wonder, spacious"],
              "{near silence}{one high string note and the piano motif}"),
             ("Swell", ["a slow, enormous orchestral swell", "the motif on full strings and brass", "rising to a warm triumphant B-flat major chord"],
              "{the swell crests}{arrives on a warm B-flat major chord}"),
             ("Ring", ["the final B-flat major chord rings out", "long natural reverb tail", "calm, resolved"], "{the last chord rings}")]
    chunks = [{"text": f"[{n}] {{instrumental}}{d}", "duration_ms": round((edges[i + 1] - edges[i]) * 1000), "positive_styles": s + ["great production quality"],
               "negative_styles": NEGATIVE, "context_adherence": "high"} for i, (n, s, d) in enumerate(parts)]
    chunks[0]["conditioning_ref"] = {"song_id": song, "range": {"start_ms": 12000, "end_ms": round(leap * 1000)}}
    chunks[0]["condition_strength"] = "high"
    return {"chunks": chunks}


def compose(seed, ref=None):
    out = os.path.join(OUT, f"end-{ref}-{seed}.mp3" if ref else f"take-{seed}.mp3")
    if os.path.exists(out):
        print("skip", out); return
    body = {"composition_plan": ending(ref) if ref else plan(), "model_id": "music_v2_5", "seed": seed}
    req = lambda: urllib.request.Request("https://api.elevenlabs.io/v1/music?output_format=mp3_48000_320", data=json.dumps(body).encode(),
                                         headers={"xi-api-key": os.environ["ELEVENLABS_API_KEY"], "Content-Type": "application/json"})
    for attempt in range(6):
        try:
            with urllib.request.urlopen(req(), timeout=600) as r:
                blob, song = r.read(), r.headers.get("song-id")
            open(out, "wb").write(blob)
            json.dump({"seed": seed, "song_id": song, "body": body}, open(out[:-4] + ".json", "w"), indent=1)
            print("ok", out, len(blob)); return
        except urllib.error.HTTPError as e:
            msg = e.read()[:400]
            if e.code == 429:
                time.sleep(5 + attempt * 5); continue
            print("FAIL", seed, e.code, msg); return
    print("FAIL", seed, "rate limited")


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    args = sys.argv[1:]
    ref = int(args.pop(args.index("--end") + 1)) if "--end" in args else None   # --end TAKE: endings for that take
    for s in [a for a in args if a != "--end"]:
        compose(int(s), ref)
