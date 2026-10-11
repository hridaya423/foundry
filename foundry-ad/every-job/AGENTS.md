# every-job: Foundry "Every job." (HyperFrames)

Picture: `index.html` + `js/`, timed by `tools/timing.py` (writes `js/timing.js`). hyperframes is pinned to 0.8.107.

## Sound

Built with [opus-sound-layer](https://github.com/Bodila51/opus-sound-layer), vendored in `sound-layer/`. Never edit
its scripts or loosen its thresholds; fix a failing check by changing cues or sounds.

| File | Does |
| --- | --- |
| `tools/music.py` | the score: one ElevenLabs composition planned from `timing.MUSIC` (`take-N`), and endings in a take's voice (`--end N`); key in `../../.env`, python.org Python needs `SSL_CERT_FILE` from certifi |
| `tools/score.py` | edits the chosen take to picture (`TAKE`/`END`/`SKIP`: tape-stop valley, its drop moved onto the melt's enter, fader rides), the beds (hum, power-down, cascade, roar/pour, air), phonautograph, Armstrong's voice stem; `preview TAKE END SKIP` writes the edited score alone |
| `tools/cues.py` | every sound effect as a cue sheet from `timing.py` (`audio/cues.json`), typing plans, `audio/CREDITS.md` |
| `tools/takes.py` | renders each typed command as one take from kit key recordings |
| `tools/sources.sh` | cuts non-kit and trimmed sounds into `audio/own/` |
| `tools/final.sh` | the whole chain, then mux and `qa.py`; `--skip-render` keeps the video stream and replaces the sound |
| `audio/lab/*.py` | measuring tools: `heroes.py` (how hard each hero hits), `spacing.py` (cluster check), `bands.py`, `bandcorr.py` (phase), `nudge.py` (what a sub-frame nudge does to a hero), `beds.py` (`BEDS_DEBUG=1`), `musictakes.py` (scores music takes against the arc), `look.py` (stills), `env.py`, `peaks.py`, `levels.py`, `overview.py` |
| `audio/gen/` | project-owned ElevenLabs sounds (power-downs, implosions, suck, pour) and the script with every prompt |

Fast iteration: a 60 fps draft takes about 2 minutes (`npx hyperframes@0.8.107 render --fps 60 --quality draft --browser-gpu -o renders/draft.mp4`), then `tools/final.sh renders/draft.mp4 --skip-render` rebuilds the sound and runs QA against it. Full 120 fps renders only for delivery.

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
- The music check flags any 3 s window 12 LU under the median: deliberate quiet (the weight, the hush under
  Armstrong) is ridden up in score.py rather than declared away; a ride can mask a cue, so carve a pocket for it.
- The drop is the melt's enter (7.0): the score's own downbeat is detected and moved there; ignition is on it.
- Quindar tones are generated sines: the Commons recordings are CC BY-SA, which would make the film a ShareAlike adaptation.
