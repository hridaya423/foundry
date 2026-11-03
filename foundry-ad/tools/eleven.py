"""Sequential ElevenLabs generation (SFX + VO) with retry on 429.

usage: .venv/bin/python tools/eleven.py sfx|vo
Reads ELEVENLABS_API_KEY from the environment (source ../.env first). Skips files that already exist.
"""
import json
import os
import sys
import time
import urllib.error
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
KEY = os.environ["ELEVENLABS_API_KEY"]

SFX = {
    "crt-on": ("Old CRT television switching on in a silent room: sharp electric pop, degauss thunk, then a thin rising high-pitched whine and faint static crackle", 2.2),
    "projector": ("16mm film projector running, fast mechanical shutter flutter and clatter, close", 3.0),
    "furnace": ("Furnace door opening, deep roaring fire whoosh and molten metal pouring, short", 1.6),
    "anvil": ("One massive blacksmith hammer strike on a steel anvil, huge bright metallic clang with long shimmering ring", 3.0),
    "thock": ("Single heavy mechanical keyboard key pressed and bottoming out, deep satisfying thock, very close microphone, dry", 0.6),
    "sparks": ("Burst of electric sparks, sharp crackle and sizzle, grinder sparks flying", 1.2),
    "freeze": ("Time freezing: tape stop slowdown, sound sucked into a vacuum, low muffled ringing suspended air", 2.0),
    "reverse": ("Reverse cymbal swell sucking upward, rising into an impact, ends abruptly", 1.5),
    "riser": ("Short white noise riser building tension fast, ends abruptly", 1.6),
    "ticks": ("Fast mechanical stopwatch ticking, crisp, accelerating", 2.0),
    "typing": ("Five quick crisp keystrokes on a premium mechanical keyboard, close and dry", 1.2),
    "whoosh-a": ("Very fast clean air swish whoosh passing by, short", 0.5),
    "whoosh-b": ("Fast heavy cinematic whoosh pass-by with low body", 0.8),
    "glitch": ("Digital glitch stutter burst, data corruption chirps, short", 0.7),
    "brush": ("Fast wet paint brush stroke swiped across canvas, short", 0.5),
    "shutter": ("Rapid camera shutter clicks, motor drive burst", 1.0),
    "sub": ("Deep cinematic sub bass drop boom, clean", 2.5),
    "quench": ("Red hot steel plunged into water, loud violent hiss and steam sizzle fading out", 3.0),
    "slam": ("Heavy steel slab slamming onto a steel floor, huge metallic impact with long ring", 2.5),
    "click-ui": ("Single soft crisp UI click, minimal, dry", 0.5),
    "pop": ("Small crisp digital pop blip, minimal", 0.5),
    "ding": ("Tiny bright glass tink, crystal ping, short", 0.8),
    "keyboard-return": ("Mechanical keyboard return key press, firm decisive clack, close and dry", 0.5),
    "room": ("Quiet empty dark room tone with faint electrical hum", 4.0),
}

VO_TEXT = "Thirteen point six milliseconds."
VOICES = {
    "brian": "nPczCjzI2devNBz1zQrb",
    "adam": "pNInz6obpgDQGcFmaJgB",
    "daniel": "onwK4e9ZLuTAKqWW03F9",
    "lily": "pFZP5JQG7iQjIQuC4Bku",
    "adamstone": "NFG5qt843uXKj4pFvR7C",
}


def post(url, body, out):
    if os.path.exists(out):
        print("skip", out)
        return
    data = json.dumps(body).encode()
    for attempt in range(8):
        req = urllib.request.Request(url, data=data, headers={"xi-api-key": KEY, "Content-Type": "application/json"})
        try:
            with urllib.request.urlopen(req, timeout=180) as r:
                blob = r.read()
            with open(out, "wb") as f:
                f.write(blob)
            print("ok", out, len(blob))
            return
        except urllib.error.HTTPError as e:
            msg = e.read()[:300]
            if e.code == 429:
                time.sleep(4 + attempt * 3)
                continue
            print("FAIL", out, e.code, msg)
            return
    print("FAIL", out, "rate limited")


def main():
    mode = sys.argv[1]
    if mode == "sfx":
        d = os.path.join(ROOT, "assets/audio/sfx")
        os.makedirs(d, exist_ok=True)
        for name, (text, dur) in SFX.items():
            post("https://api.elevenlabs.io/v1/sound-generation?output_format=mp3_44100_192",
                 {"text": text, "duration_seconds": dur, "prompt_influence": 0.6}, os.path.join(d, f"{name}.mp3"))
    elif mode == "vo":
        d = os.path.join(ROOT, "assets/audio/vo")
        os.makedirs(d, exist_ok=True)
        for name, vid in VOICES.items():
            post(f"https://api.elevenlabs.io/v1/text-to-speech/{vid}?output_format=mp3_44100_192",
                 {"text": VO_TEXT, "model_id": "eleven_multilingual_v2",
                  "voice_settings": {"stability": 0.55, "similarity_boost": 0.8, "style": 0.25, "use_speaker_boost": True}},
                 os.path.join(d, f"vo-{name}.mp3"))


main()
