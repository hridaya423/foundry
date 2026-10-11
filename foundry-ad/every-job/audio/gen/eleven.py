#!/usr/bin/env python3
"""The valley and the drop's own sounds, generated with ElevenLabs sound generation (project-owned; credited in
tools/cues.py OWN as "Generated (ElevenLabs)"). Several takes of each so the wall of sets never repeats one recording.

usage: set -a; . ../../.env; set +a; SSL_CERT_FILE=... uv run audio/gen/eleven.py   -> audio/gen/NAME-K.mp3 (skips existing)
"""
import json, os, sys, time, urllib.error, urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
KEY = os.environ["ELEVENLABS_API_KEY"]

SFX = {  # name: (prompt, seconds, takes)
    "tvoff": ("Cinematic old television power off sound effect, loud and close: a heavy electric thunk, then a bright "
              "high-pitched electronic whine sweeping quickly down in pitch, ending in a short burst of static that cuts dead", 1.0, 4),
    "implode": ("A CRT television picture tube bursting: a sharp electrical pop and crack, glass shattering violently, "
                "shards scattering, short and dry", 1.0, 4),
    "suck": ("A huge reverse air suck-in, air violently sucked into a vacuum, rising fast and ending abruptly on a cut, "
             "just before an explosion", 1.5, 3),
    "pour": ("A thick stream of molten metal pouring into a steel mould: heavy liquid roar, deep rumble, crackle and "
             "sizzle, steady", 3.0, 2),
}


def post(body, out):
    if os.path.exists(out): print("skip", out); return
    for attempt in range(8):
        req = urllib.request.Request("https://api.elevenlabs.io/v1/sound-generation?output_format=mp3_44100_192",
                                     data=json.dumps(body).encode(), headers={"xi-api-key": KEY, "Content-Type": "application/json"})
        try:
            with urllib.request.urlopen(req, timeout=180) as r: blob = r.read()
            open(out, "wb").write(blob); print("ok", out, len(blob)); return
        except urllib.error.HTTPError as e:
            if e.code == 429: time.sleep(4 + attempt * 3); continue
            print("FAIL", out, e.code, e.read()[:300]); return
    print("FAIL", out, "rate limited")


for name, (text, dur, n) in SFX.items():
    if len(sys.argv) > 1 and name not in sys.argv[1:]: continue
    for k in range(1, n + 1):
        post({"text": text, "duration_seconds": dur, "prompt_influence": 0.6}, os.path.join(HERE, f"{name}-{k}.mp3"))
