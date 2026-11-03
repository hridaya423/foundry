# Sound brief: Foundry "Literal."

## Concept

A 24 s seamless loop (48 beats at 120 BPM, 12 bars) for Foundry, a macOS launcher (⌘ Space, type a few letters, Return). Every picture is one
wall of 4,400 chalk tiles: glazed ceramic squares, pillowy, the size of a large keycap. The wall answers
every command literally: background tiles fall off the wall, tiles flip over to translate, tiles are thrown in
the air as confetti and land as the wordmark.

**The tiles are the instrument.** Every sound is caused by tiles or by the keyboard. One material family: glazed
ceramic / stoneware tiles on a hard surface, plus one keyboard. No glass, no metal, no whooshy "magic".

The reference for density and punch is a recruiting film whose cinematic feel comes from its sound design:
dry, close, compressed (-13 LUFS, LRA ~3-4 LU), every move carried by a sound, risers into hits.

## Picture map (exact frames: `out/cues.json`, generated from the picture by `tools/cues.mjs`)

Beat = 0.5 s; bar n starts at 2(n-1) s. The film loops: 23.98 s flows into 0.0 s.

| time (s) | picture | sound need |
|---|---|---|
| 0.0-0.45 | an orange built from tiles on a chalk wall, raking light | room tone, nearly silent |
| 0.47, 3.97, 6.47, 9.97, 12.47 | ⌘ Space: the panel appears | `key_chord`: ⌘ then Space (deeper) |
| after each chord | 2-17 typed letters (≤ 12 sounded keys/s) | `key_type`: one keyboard, sliced, 12+ takes |
| 1.68, 4.93, 7.68, 10.68, 13.93 | Return | `key_return`: a deeper, longer key |
| 1.83-3.35 | 3,968 background tiles tip backward off the wall in a radial wave from the orange | `tile_cascade`: ceramic tiles falling and clattering, a spreading wave, 1.5 s |
| 5.26-5.44 | the orange's 432 tiles regroup into a 24 × 18 block, row by row | `tile_lock`: a quick run of clacks into one unison seat |
| 6.05-6.26 | 43 tiles flip to read "432" | `tile_flip`: single tiles turned over, a fast run |
| 8.17 | the block splits and slides into a strip, one unison snap | `tile_slide` + `tile_lock` |
| 8.51-8.75 | tiles flip to read HELLO | `tile_flip` run |
| 8.98-9.52 | a full wave of 432 flips to こんにちは | `tile_flip`, a longer wave |
| 10.78-11.03 | tiles lift off the strip | `tile_lift`: light ceramic scrape / pick-up |
| 11.17-11.76 | 1,369 tiles land as a scannable QR code, top rows first | `tile_drop`: single tiles landing flat, many takes |
| 13.0-14.0 | the build into the drop | `riser`, or the music's own build |
| 14.0 | Make Confetti: the QR bursts, every tile thrown at the camera | `drop_hit`: the music's DROP + one real broadband impact |
| 14.0-16.3 | tumbling tiles, then the chaff falls away out of frame | the music carries it; distant clatter at most |
| 16.1-18.3 | 461 tiles land left to right and build "foundry" | `tile_settle`: light clacks, a run that thins out |
| 18.5 | the last letter seats; the music stops on this beat | near-silence |
| 19.0 | the orange full stop lands (beat 38) | `logo_note`: the period's tile tock + ONE soft resolved note, tail to silence |
| 19.5, 20.0 | caption "⌘ Space," then "then anything." | nothing, or a very soft ⌘ Space chord on 19.5 |
| 21.5-22.45 | the camera dives into the period's tile | `swish`: real air / bamboo swish, apex 22.38 |
| 22.5 | inside the tile; it becomes a pixel of the orange | `tock`: one soft tile tock |
| 22.55-24.0 | the camera pulls back out to frame 0 | `swish` (softer), tail into the loop's room tone |

## Music

ONE licensed instrumental track, 116-126 BPM, 4/4: minimal tech house / minimal techno / percussive electronic
with a dry punchy kick and space in it (the tile foley must sit on top). Structure needed: a sparse intro or a
groove that can start cold (bar 1), a build or a stop into bar 8 (14.0 s, 58 %), a strong drop on bar 8, and a
bar line where it can stop cleanly (18.5 s). The music is silent from about 19 s to 24 s so the loop seam is clean. No vocals, no ukulele / whistling, no trailer braams, no lo-fi hiss, no EDM brostep.
Professionally mixed, full bandwidth.

## Licences

Allowed: CC0, public domain, CC BY 3.0/4.0, Mixkit free licences, Pixabay. Forbidden: NC, ND, SA, Sampling+,
custom, unclear. Read each item's own page.

## Quality bar

Real recordings only (earshot realness "real or pro-produced" on the trim used); close-miked, dry, clean floor
(under -55 dBFS between events), full bandwidth (rolloff above 12 kHz), no clipping, no voices or room in the
window used. Many takes of the same object preferred (natural variation).

## Files

- `audio/assets/<category>/<source>-<id>_<slug>.<ext>`; manifests in `audio/assets/manifests/<category>.json`.
- Categories: `music`, `tiles`, `keys`, `fx` (riser, impact, swish, logo note).
- Review work in `out/audio-review/<category>/`.
