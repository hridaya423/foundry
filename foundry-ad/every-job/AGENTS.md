# every-job: Foundry "Every job." (HyperFrames)

Picture: `index.html` + `js/`, timed by `tools/timing.py` (writes `js/timing.js`). hyperframes is pinned to 0.8.107.

## Sound

Built with [opus-sound-layer](https://github.com/Bodila51/opus-sound-layer), vendored in `sound-layer/`. Never edit
its scripts or loosen its thresholds; fix a failing check by changing cues or sounds.

| File | Does |
| --- | --- |
| `tools/score.py` | music stem (drone, kick, bass, typewriter hat, phonautograph), the roar beds, Armstrong's voice stem |
| `tools/cues.py` | every sound effect as a cue sheet from `timing.py` (`audio/cues.json`), typing plans, `audio/CREDITS.md` |
| `tools/takes.py` | renders each typed command as one take from kit key recordings |
| `tools/sources.sh` | cuts non-kit and trimmed sounds into `audio/own/` |
| `tools/final.sh` | the whole chain, then mux and `qa.py`; `--skip-render` keeps the video stream and replaces the sound |
| `audio/lab/*.py` | measuring tools: `heroes.py` (how hard each hero hits), `spacing.py` (cluster check), `bands.py`, `bandcorr.py` (phase), `env.py`, `peaks.py`, `levels.py`, `overview.py` |

First run on a new machine (needs ffmpeg and uv): `uv run sound-layer/scripts/sfx.py kit` (about 10 minutes,
226 MB), the `sfx.py search` downloads that `sources.sh` reads from `audio/candidates/` (ids are in its paths,
landing pages in `audio/CREDITS.md`), then `tools/sources.sh`, then `tools/final.sh renders/foundry-every-job.mp4 --skip-render`.

Rules learned on this film (mix.py's model):
- A support sound whose peak lands within 0.15 s of the previous peak is turned down 4.4 dB and fails `audible`:
  keep peaks `GAP` apart, or make same-instant sounds layers of one cue (`a+b`). Check with `audio/lab/spacing.py`.
- A hero is levelled against what sustains under it in its own window, so a roar must be at full on its hit or the
  hit comes out quiet. QA can't see this; `audio/lab/heroes.py` does. Hero body lands near 3.2 dB by construction,
  so a hit and a bed that cancel in its main band fail it: phase-align (`CATCH` in score.py, `NUDGE` in cues.py).
- Continuous roars are beds (score.py), not cues. Long tails are trimmed to stop before the next picture event.
- Noise whooshes have no single 2 ms peak and fail `sync`; pick ones with a clear apex. Steady tones align `start`.
- Quindar tones are generated sines: the Commons recordings are CC BY-SA, which would make the film a ShareAlike adaptation.
