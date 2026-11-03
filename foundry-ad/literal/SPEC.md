# Literal. — spec

A 24 s seamless loop for Foundry. One wall of 4,400 chalk tiles answers five real Foundry commands literally, then
throws itself in the air and lands as the wordmark. The last move dives into the full stop, which turns out to be a
pixel of the orange in frame 0.

## Time

- 120 BPM, beat 0.5 s, 48 beats, 12 bars. Every event sits on a beat or half beat (`js/timing.js`).
- Commands: summon, type, Return on the beat grid. Return at beats 3.5, 10, 15.5, 21.5, 28.
- Drop (confetti) on bar 8 downbeat, 14.0 s. Last letter 18.5 s. Full stop 19.0 s (beat 38). Caption 19.5 / 20.0 s.
- Loop: dive 21.5-22.5 s, swap at 22.5 s, pull-out 22.5-24.0 s lands exactly on frame 0.

## Look

- Wall: 88 × 50 tiles, pitch 24, tile geometry and chalk material ported from the website (ExtrudeGeometry depth 8,
  bevel 1.7, MeshPhysical roughness 0.7, clearcoat 0.12). Chalk #c6bbab, orange #ef672e, body #968a7b (neutral, so tumbling tiles show no coloured stripe), ink checker
  #1a1715 / #24201c.
- Light: RoomEnvironment 0.42, ambient 0.72, key 3.3 from upper left, following the camera target, PCF shadows.
- Output: exposure 0.333, light pool centred (0.42, 0.6), highlight compression, vignette 0.16, S-curve 0.22,
  grain 0.035.
- Camera: fov 24, shots in `js/camera.js`, distance interpolated in log space. Panel at top 104 px; while it is open the subject's top edge
  sits at y >= 340 px.
- Sampling per frame: 6 (rest), 16 (fast beats), 48 (the dive into the full stop), 80 (confetti), averaged (autoClear off). Shutter 0.5/60 s, Halton
  jitter, thin-lens DOF during confetti only: aperture 10 units, focus on the swarm's median depth
  (1030 · (1 − e^(−1.35 s)) / 1.35 in front of the wall).

## Motion rules

- Tiles are heavy ceramic: hinge-tip then gravity 2600 for the cascade; chaff gravity 2600 from 14.85 s; 15% extra fliers; QR burst depth capped so no tile crosses the lens.
- One ease family: brandOut bezier(0.23, 1, 0.32, 1) for seats, inOutCubic for camera, outQuart for rises.
- Flips 0.2-0.22 s. Landings: Hermite into the slot, 0.75 s (full stop 0.9 s), damped bounce 1.6 units.
- Panel rows answer only what is typed: the calculator row is live and only for a valid expression, the translation
  appears with the full query.
- Loop swap: all four full-stop tiles warm to the hook tile's colour over the last 0.5 s of the dive; distance scaled by the
  tile width ratio; zero camera velocity at the swap; 0.16 s of full-frame tile.

## Verified

- QR at 12.0 s and 13.2 s decodes to `https://foundry.hridya.tech` (`tools/qrscan`, Apple Vision).
- Frame 0 and 23.983 s match in framing and exposure.
- No single-frame pops: `python3 tools/pops.py renders/literal-picture.mp4 --allow=1.033` exits 0 (1.033 s is the
  panel's first result row appearing, an instant UI change like the real launcher).

## Banned

- Floating "magic" particles, glow, bloom, lens flares, chromatic aberration.
- Any motion not caused by a tile or the camera. Text animating on its own.
- Uniform snow: a field of equal small tiles with no focal point.
- Synthesized sound. Every sound is a real recording (`audio/SOUND_BRIEF.md`).
