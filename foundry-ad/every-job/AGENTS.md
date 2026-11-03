# every-job: Foundry "Every job." (HyperFrames)

Picture: `index.html` + `js/`, timed by `tools/timing.py` (writes `js/timing.js`). hyperframes is pinned to 0.8.107.

## Sound

Built with [opus-sound-layer](https://github.com/Bodila51/opus-sound-layer), vendored in `sound-layer/`. Never edit
its scripts or loosen its thresholds; fix a failing check by changing cues or sounds.

| File | Does |
| --- | --- |
| `tools/score.py` | the score, composed in code on the picture's times (D major, 120 BPM: Rhodes, finger bass, guitar, kit), Armstrong mixed in; `STEMS=1` also writes `/tmp/stem_*.wav` for earshot |
| `tools/synth.py` | the score's instruments, computed (felt piano, Rhodes, Karplus-Strong guitar, finger bass, pad, kick, snare, shaker, room) |
| `tools/sfx.py` | the sound effects, computed: four laptop keys, the enter, the low drum the name lands on (key seeds chosen by earshot `compare` against kit keys) |
| `tools/cues.py` | every sound effect as a cue sheet from `timing.py` (`audio/cues.json`), typing plans, `audio/CREDITS.md` |
| `tools/takes.py` | renders each typed command as one take from the `sfx.py` keys |
| `tools/sources.sh` | cuts non-kit and trimmed sounds into `audio/own/` |
| `tools/final.sh` | the whole chain, then mux and `qa.py`; `--skip-render` keeps the video stream and replaces the sound |
| `audio/lab/*.py` | measuring tools: `tonal.py` (every pure tone has a picture event within one frame), `voicegap.py` (Armstrong over the score), `heroes.py` (how hard each hero hits), `spacing.py` (cluster check), `bands.py`, `bandcorr.py` (phase), `env.py`, `peaks.py`, `levels.py`, `overview.py` |

First run on a new machine (needs ffmpeg and uv): `uv run sound-layer/scripts/sfx.py kit` (about 10 minutes,
226 MB), the `sfx.py search` downloads that `sources.sh` reads from `audio/candidates/` (ids are in its paths,
landing pages in `audio/CREDITS.md`), then `tools/sources.sh`, then `tools/final.sh renders/foundry-every-job.mp4 --skip-render`.

Rules learned on this film (mix.py's model):
- A support sound whose peak lands within 0.15 s of the previous peak is turned down 4.4 dB and fails `audible`:
  keep peaks `GAP` apart, or make same-instant sounds layers of one cue (`a+b`). Check with `audio/lab/spacing.py`.
- A hero is levelled against what sustains under it in its own window, so a roar must be at full on its hit or the
  hit comes out quiet. QA can't see this; `audio/lab/heroes.py` does. Hero body lands near 3.2 dB by construction,
  so a hit and a bed that cancel in its main band fail it: phase-align (`CATCH` in score.py, `NUDGE` in cues.py).
- mix.py and qa.py filter each hero's 50 ms window from rest, so a loud low end at the window's start reads as a step, a
  click in every band, and the hero comes out short of its 3 dB body: the bass gives way under each enter (score.py).
- Continuous roars are beds (score.py), not cues. Long tails are trimmed to stop before the next picture event.
- Noise whooshes have no single 2 ms peak and fail `sync`; pick ones with a clear apex. Steady tones align `start`.
- mix.py levels any voice stem to -16 LUFS, which put Armstrong at the arrival's level and held the climax's loudness
  range to 2.1 LU (measured: on its channel his line B is the film's loudest 3 s, 4.1 LU over integrated). So score.py
  mixes him into `music.wav` at a level it sets, and the cue sheet has no voice. `audio/voice.wav` is his line alone at
  the same scale, for measuring: qa.py's `voice` check no longer runs, so run `audio/lab/voicegap.py` (same rule, >= 8).
- Anything on mix.py's voice channel ducks the score, and the duck's 250 ms release lands on whatever follows:
  put a tone just before a hit on the score's bus (score.py `music`), not on a voice channel.
- A hit over a running score needs a dip of at least 0.2 s before it (score.py `inhale`): earshot's bed is the median
  level of the 0.3 s before an event, so a shorter dip leaves the hit "+1 dB over the bed". Keep the dip's edges sharp
  (250 Hz): at 40 Hz the score's recovery lands 25-50 ms after the frame and becomes the attack.
- `stop_before` in a cue does not trim the cue: mix.py stops the music for 0.4 s before it.
- A pure tone with nothing changing on screen reads as stray: three critics flagged the end card's Quindar out-tone
  while the caret only blinked. Every tonal cue needs a picture event within one frame, one that stands alone (the
  caret is steady, then goes out on the tone's frame, not a blink among blinks). Run `uv run audio/lab/tonal.py
  renders/sota-draft.mp4` after every draft; it exits 1 on a miss.
- Quindar tones are generated sines: the Commons recordings are CC BY-SA, which would make the film a ShareAlike adaptation.
