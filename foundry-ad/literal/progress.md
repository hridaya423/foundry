# Literal. — progress

Project: `foundry-ad/literal` (HyperFrames + three.js). Spec: `SPEC.md`. Sound contract: `audio/SOUND_BRIEF.md`.

Deliverable: `out/film_sound.mp4` (24.000 s, 60 fps h264, AAC 320k). Picture alone: `renders/literal-picture.mp4`.

## How to look at it

- Stills: `node tools/shoot.mjs <t> <t> <s:e:step> [--draft] [--out=dir]`, then `python3 tools/sheet.py <dir> <sheet.jpg>`.
- Cues: `node tools/cues.mjs` writes `out/cues.json` from sampled tile poses (rerun after any choreography change).
- QR check: `./tools/qrscan <png>` (build: `swiftc -O tools/qrscan.swift -o tools/qrscan`).
- Pops: `python3 tools/pops.py renders/literal-picture.mp4 --allow=1.033` (exit 0).
- Data: `PYTHONPATH=tools/.venv/lib/python3.14/site-packages python3 tools/data.py` rebuilds `js/data.js`.

## Picture (done)

- Whole film 0-24 s renders; QR decodes at 12.0 and 13.2 s; loop seam frame 0 = 23.983 s; dive swap invisible.
- Accumulation bug fixed (autoClear wiped the accumulator; brightness was 1/K). Exposure 0.333. K-independent.
- Lens skew sign fixed; DOF only during confetti, focus on the swarm.
- Render: `PRODUCER_BROWSER_GPU_MODE=hardware PRODUCER_PLAYER_READY_TIMEOUT_MS=240000 npx --yes hyperframes@0.8.226 render . -f 60 -q delivery --workers 2 -o renders/literal-picture.mp4`
  (the `--browser-gpu` flag still launches SwiftShader; `--start/--end` always does).

## Sound (done)

Pipeline: `PY=/Users/hridyaagrawal/Honey/earshot/.venv/bin/python`, `S=~/.claude/skills/real-sound`.
- Music: Mixkit "Deep House" (Arulo), Rubber Band R3 stretch 123.996 -> 120 BPM, bar-line edit in `audio/design/music.json`;
  src bar 7 at 22-24 s carries the loop seam into the bar-8 downbeat at 0.
- Design fragments: `audio/design/{tiles,keys,fx}.json`; buses and master in `audio/sounddesign.json`.
- Mix -> qa -> master -> `node $S/scripts/mux.mjs --video renders/literal-picture.mp4 --audio out/audio/soundtrack.wav --out out/film_sound.mp4`.
- Evidence (2026-11-01, on the muxed file): earshot critique launch-grade, 23/23 metrics in range, p_real 0.98,
  music 100%, -14.0 LUFS, -2.0 dBTP, LRA 9.8, final moment -2.2 LU (was 7 LU low before the loop segment).
  Sheet: 97% of 110 cues have an onset within 100 ms, median offset 16 ms (`out/qa/final_sheet.png`).
- Licence audit: `$PY -I $S/scripts/audit.py --root . --report out/qa/mix_report.json` exit 0, 16/16 ok
  (15 Freesound pages and the Mixkit Stock Music Free License text read 2026-11-01).
- Credits: `CREDITS.md`, `out/CREDITS_description.txt` (5 CC BY credits must go in the video description).

## Critic pass (done)

Blind Opus 5.5 critic on v1 scored 6/10. Fixed after checking each claim in frames:
- Calculator and translation rows showed the answer before the query was typed: rows now answer only what is typed.
- QR, orange and 432 slab sat under the panel: reframed (QR d 3300, orange d 2150, slab d 1690-1700).
- Only one of the four full-stop tiles warmed before the swap: all four warm together.
- Stepped motion blur in the dive: 48 samples there.
- Confetti: red tile sides read as stripes (body now #968a7b), fewer extra fliers, no tile crosses the lens, chaff falls from 14.85 s.
Evidence: `qa/v2-sheet.jpg` (frames from the v2 render), QR decodes at 12.0 and 13.2 s from the video, pops exit 0
(seam 0.58), cues identical to v1 (113 events, 0 moved) so the mix stands, earshot critique on the v2 mux launch-grade 23/23.
v1 picture kept as `renders/literal-picture-v1.mp4`.

## Not done (judged, left as is)

- UI size for small feed embeds: a bigger panel would crowd the subjects again.
- Confetti length (2.5 s) and the five-beat cadence: both are locked to the music edit; shortening means a new edit.
- Tagline hold (19.5-21.5 s) and the rigid slab slide: taste calls left for the user.
