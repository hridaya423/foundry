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

GLOBAL = ["modern uplifting electronic music for a tech product launch film", "120 BPM, 4/4, in D major",
          "warm analog synths, felt piano, plucked synth arpeggios, tight punchy modern drums, deep clean bass",
          "one simple memorable four-note motif that every section is built on",
          "ambitious, optimistic, confident, human, minimal", "polished modern production, clean mix, wide stereo"]
NEGATIVE = ["vocals", "singing", "choir", "orchestra", "orchestral hits", "brass", "timpani", "taiko", "epic trailer",
            "cinematic trailer", "anvil", "industrial", "dubstep", "EDM drop", "riser", "lo-fi", "hip hop", "cheesy", "ukulele"]
# inline directions per section: the model ramps into sections unless told the event is on the first beat
DIRECT = {
    "lineage": "{felt piano plays the motif from the very first beat}",
    "weight": "{gently building to the last beat}",
    "drop": "{the full beat comes in on the very first beat, no build-up}",
    "build": "{driving groove from the very first beat}",
    "leap": "{the drums drop out on the first beat}{airy and spacious}{slowly lifting in the last two seconds}",
    "card": "{a warm resolved major chord on the very first beat}{it rings out to the very end, no fade-out}",
}
SECTIONS = {
    "lineage": ["the motif on felt piano, one note per beat", "a soft warm synth pad underneath", "curious, intimate", "very sparse"],
    "weight": ["a plucked synth arpeggio enters and grows busier", "soft hi-hats", "a little restless", "gently building"],
    "drop": ["the beat arrives: punchy kick, crisp clap, warm bass", "the motif on a bright synth", "confident, release, clarity"],
    "build": ["driving sixteenth-note synth arpeggio", "crisp drums", "momentum, forward motion", "the motif on a bright lead"],
    "leap": ["no drums", "airy synth pad and felt piano", "spacious, hopeful, awe", "slowly lifting in the last two seconds"],
    "card": ["a warm resolved major chord on felt piano and soft pad", "calm, confident, complete", "no drums", "rings out"],
}


def plan():
    edges = [t for _, t in T.MUSIC] + [T.END + 2.0]   # past the end: the model fades out whatever it is asked for
    chunks = []
    for i, (name, t0) in enumerate(T.MUSIC):
        styles = (GLOBAL + SECTIONS[name]) if i == 0 else SECTIONS[name] + ["great production quality"]
        chunks.append({"text": f"[{name.capitalize()}] {{instrumental}}{DIRECT[name]}", "duration_ms": round((edges[i + 1] - t0) * 1000),
                       "positive_styles": styles, "negative_styles": NEGATIVE + (["fade out"] if name == "card" else []),
                       "context_adherence": "high"})
    return {"chunks": chunks}


def ending(ref):
    """The leap, as its own piece in the take's voice: generated past the film's end, because the model fades out
    whatever it is asked for; the hush under "one small step" swells through "one giant leap for mankind." and arrives
    as the translation completes (timing.py ARRIVE) on a warm chord, strings and piano, and keeps opening into the logo."""
    song = json.load(open(os.path.join(OUT, f"take-{ref}.json")))["song_id"]
    leap = dict(T.MUSIC)["leap"]
    edges = [T.ARRIVE - 6.25, T.ARRIVE - 3.0, T.ARRIVE, T.END + 3.5]   # the API takes chunks of 3 s or more
    parts = [("Hush", ["drops to near silence", "a single sustained high string note", "the soft felt piano motif, slow", "awe, wonder, spacious"],
              "{near silence}{one high string note and the piano motif}"),
             ("Swell", ["a slow string swell, low cellos and violas rising together", "no percussion, no snare, no riser",
                        "the motif on solo cello", "intimate, warm, rising to the very last beat, unresolved"],
              "{the strings swell to the very last beat}"),
             ("Arrival", ["on the very first beat the swell opens into a warm B-flat major chord, strings and felt piano together",
                          "the motif on felt piano over sustained strings, close and human", "hopeful, tender, a lump in the throat",
                          "no orchestral hit, no cymbal, no brass stab, no trailer drums", "the strings keep opening for four seconds",
                          "then the last chord rings"],
              "{the swell opens into a warm chord on the very first beat}{piano and strings, still opening}{the last chord rings}")]
    chunks = [{"text": f"[{n}] {{instrumental}}{d}", "duration_ms": round((edges[i + 1] - edges[i]) * 1000), "positive_styles": s + ["great production quality"],
               "negative_styles": NEGATIVE + ["fade out"], "context_adherence": "high"} for i, (n, s, d) in enumerate(parts)]
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
