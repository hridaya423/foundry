"""Compose the 15 s score with the ElevenLabs Music API from a sectioned composition plan.

usage: .venv/bin/python tools/score.py <name> [seed] [--drive]   (--drive: the 11.25 s drive + finale plan only)
Reads ELEVENLABS_API_KEY from the environment (source ../.env first). Writes assets/audio/music/<name>.mp3.
"""
import json
import os
import sys
import urllib.error
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
KEY = os.environ["ELEVENLABS_API_KEY"]

PLAN = {
    "positive_global_styles": [
        "128 BPM", "cinematic electronic", "hybrid trailer percussion", "punchy modern sound design", "tight sub bass",
        "precise, clean, expensive mix", "instrumental", "minor key", "industrial metallic textures",
    ],
    "negative_global_styles": ["vocals", "lyrics", "lo-fi", "acoustic guitar", "jazz", "orchestral swell cliche", "muddy", "slow"],
    "sections": [
        {"section_name": "Tube", "duration_ms": 3750, "lines": [],
         "positive_local_styles": ["dark low drone", "electrical hum", "sparse", "tension", "one huge metallic impact halfway",
                                   "suspended reverse swell building into the next section"],
         "negative_local_styles": ["drums", "melody", "busy"]},
        {"section_name": "Drive", "duration_ms": 7500, "lines": [],
         "positive_local_styles": ["full energy from the first beat", "driving four-on-the-floor kick", "fast sixteenth-note hi-hats",
                                   "glitchy stutter edits", "distorted pulsing synth bass", "relentless forward momentum",
                                   "builds harder every bar"],
         "negative_local_styles": ["intro", "fade in", "breakdown", "ambient"]},
        {"section_name": "Finale", "duration_ms": 3750, "lines": [],
         "positive_local_styles": ["massive drop impact on the first beat", "then a wide sustained resolving synth chord",
                                   "warm triumphant", "decays to silence"],
         "negative_local_styles": ["drums continuing", "new melody", "abrupt cut"]},
    ],
}


DRIVE = dict(PLAN, sections=PLAN["sections"][1:])


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    name = args[0]
    body = {"composition_plan": DRIVE if "--drive" in sys.argv else PLAN, "model_id": "music_v1"}
    if len(args) > 1:
        body["seed"] = int(args[1])
    out = os.path.join(ROOT, "assets/audio/music", name + ".mp3")
    req = urllib.request.Request("https://api.elevenlabs.io/v1/music?output_format=mp3_44100_192", data=json.dumps(body).encode(),
                                 headers={"xi-api-key": KEY, "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=300) as r:
            blob = r.read()
    except urllib.error.HTTPError as e:
        raise SystemExit(f"FAIL {e.code} {e.read()[:600]}")
    with open(out, "wb") as f:
        f.write(blob)
    print("ok", out, len(blob))


main()
