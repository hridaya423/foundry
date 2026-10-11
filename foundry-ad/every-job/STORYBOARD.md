---
title: Foundry — "Every job." (v2)
format: 1920x1080, 60 fps (rendered at 120, sub-frame pairs blended)
duration: 26.0 s
tempo: 120 BPM (beat 0.5 s); all times in tools/timing.py (writes js/timing.js; the score imports it)
---

# Idea

> A machine for every job. / An app for every job. / One for every job.

Alchemy: many into one. Setup and payoff: the jobs the apps in Act II were piled up for are done in Act III, one
line each in Foundry's bar. Armstrong's line spans the finale so "...for mankind." lands on the wordmark.

The arc is the references' (research/feel/): lineage (pride), the weight (pressure), a valley (held breath), the
drop (the "oh shit"), the one (relief), the kills (momentum), Armstrong (awe), the cast logo (arrival). One motif
runs through it: the caret. The caret alone in the dark at 6.1 s is where, and the size, the molten caret is born
from the cast bar at 10.9 s.

# System

- **Three typists, one typeface** (IBM Plex Mono): a typewriter strikes line 1 (whole words, letters a
  little off the line, the tube jolts); an I-beam types line 2 in a note app; Foundry's molten caret types
  line 3 in the cast bar.
- **Past** in an amber tube on a Blender set; **present** full frame and crisp; heat is the only colour.
- **The wall**: the set tiled into an endless wall (`uBox`), other screens from a live 48-slot atlas. It sits in
  perspective and falls into fog; out-of-focus sets blur, and ignition is a wave that burns each screen through
  from its edges.
- **Metal**: red = in the picture, blue = in the room (drips, the river), green = emission. Every hot thing —
  melt, cast, caret, logo — shares one blackbody ramp (≈650–2600 K), so the film's heat is one physical thing.
  The bar cools physically to cast iron, one band of light, then glass that frosts and refracts what is behind
  it; its caret is a light on the picture.
- **The grade**: halation (wide, red, highlights only), a shadow toe, edge chromatic aberration, gate weave and
  grain on everything; Act I's footage also gets projector flicker, dust and hairline scratches — inside the
  tube, never on the frame. The camera breathes and pushes in and out on Act I's words.

# Beats

| Time | What happens |
|---|---|
| 0.0–2.8 | **A machine / for every / job.** struck by a typewriter, one word per beat, each word a hard cut to its machine: typing pool, switchboard, telegraph, 1957 computer, Saturn V ignition. |
| 2.8–5.0 | **An app for every job.** typed with an I-beam; *YouTube Downloader MP4 (No Virus)*, *Background Eraser Online*, *GIF Maker Pro* land big and readable, then twenty more. The set overheats: the picture rolls and tears, the glass glows. |
| 5.0–5.75 | The camera pulls back: an endless wall of sets tilting away into fog, every one a pile of apps; every set pings. |
| 5.75–7.0 | **The valley.** Everything stalls: the pictures freeze, every set powers down (raster, line, dot, off), ours first and the wall outward; the room goes dark. One caret blinks alone; `melt them down` is typed into the silence. |
| 7.0 | **The drop**, on the enter: our set goes white and the heat hits the lens (flash, halation, shake, haze); the blast lights the dead wall for a few frames. |
| 7.0–9.4 | Ignition travels out from our set and every screen burns through from a molten edge, throwing sparks; the drips run down the wall and braid into one river; the camera falls with it. |
| 9.4–11.2 | The river fills a mould: Foundry's bar. It cools from the rim in: the skin crusts and cracks, the casting shrinks from the mould wall, smoke lifts. The heat retreats to where the cursor lives. A band of light runs along the iron; the sand mould is knocked out; the iron shell flakes away to the glass bar. |
| 11.2–11.8 | The last molten point is the caret, where the caret in the dark was. **One for every job.** types out of it. |
| 12.0–18.75 | **The kills**, each sooner than the last. Each is its line typed in the bar while the picture waits, then enter: `convert to gif` (Muybridge's plate gallops), `remove background`, `100 usd in eur` (89.25, ECB rate on 2026-10-05), `tile windows`, `download youtu.be/lumiere-1895` (the clip opens out of the bar; the train comes through). |
| 18.75–23.42 | `translate to japanese`, last. Its enter is the Quindar tone; the bar gets out of the way, and then Armstrong, whole and uninterrupted: "That's one small step for man," builds and turns Japanese in his pause; "one giant leap" builds under it. |
| 23.42–26.0 | Cut on "for": back through tiles holding the flag planting until they are the wordmark; **"...mankind."** as it resolves. The wordmark is the last casting: a wave sends each tile white-hot, sparks tear off its edges, thin strokes cool first through orange and cracked oxide, the cores hold heat longest, and it settles as pale iron that one band of light runs along. The molten caret after the name blinks through the Quindar beep (end of transmission) and goes out with it. |

# Sound

The score is one orchestral-hybrid composition (ElevenLabs, `tools/music.py`, planned from `timing.MUSIC`) in B-flat
minor on a three-note motif: felt piano for the lineage, tightening strings for the weight, a tape-stop into a
ringing for the valley, the full drop on the melt's enter, one held note as the iron cools, a build through the
kills, quiet strings under Armstrong and a swell that crests on "mankind". `tools/score.py` edits it to picture.

Every sound effect is a real recording or a project-owned generation placed from `tools/timing.py` (`tools/cues.py`,
mixed and checked by [opus-sound-layer](https://github.com/Bodila51/opus-sound-layer)); the roars are beds in
`tools/score.py`.

- **Act I**: each word is a 1940s typewriter strike with its machine on it: the typing pool, a phone bell, Morse, a
  1957 computer's blips. "job." is the Saturn V: a hit and sub, then the shuttle's roar, dead on the Act II cut.
- **Act II**: a modern keyboard for the I-beam; the apps land as glass ticks rising in pitch; the sets hum and strain;
  the set's static tears as it overheats; one whoosh on the pull-back, the whole wall pings once.
- **Valley**: every set powers down (thunk, static cut, whine collapsing with the dot) across the stereo field,
  farther ones quieter and later; then only the ringing, a caret tick and `melt them down` typed close and dry.
- **Drop**: an air-suck ends on the enter; the hit lands with the score's drop; screens implode outward along the
  picture's ignition wave; the roar arrives late (sound is slower than light), swells, then narrows into a pour.
- **Cast**: the river slams into the mould (metal, sub, the fall's whoosh) and the roar stops; then it sizzles,
  pings as it contracts, the light sweeps, the mould is knocked out (thud and sand), the shell flakes, the caret ticks.
- **Kills**: the bar is summoned, one typing take per command, enter is an anvil. Each job sounds like itself: the
  gallop, a wipe and the horse bolting, ratchet reels landing on a till, latches on the window seams, the steam
  whistle and train; the train passes into the moon.
- **Logo**: a reverse cymbal and a sub on the pull-back through the tiles, the tiles quench, then the Quindar out-tone.
