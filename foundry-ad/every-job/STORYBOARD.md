---
title: Foundry — "Every job." (v2)
format: 1920x1080, 60 fps (rendered at 120, sub-frame pairs blended)
duration: 30.03 s
tempo: 120 BPM (beat 0.5 s); all times in tools/timing.py (writes js/timing.js; the score imports it)
---

Status (2026-11-09): the times in this file follow `js/timing.js` and `audio/cues.json`, which both say 30.03 s. An earlier version of this file said 24.3 s. The beat descriptions still describe the picture; the sound section was rewritten for the current score.

# Idea

> A machine for every job. / An app for every job. / One for every job.

Setup and payoff: the jobs the apps in Act II were piled up for are done in Act III, one line each in
Foundry's bar. Armstrong's line spans the finale so "...for mankind." lands on the
wordmark.

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
| 5.0–5.7 | The camera pulls back: an endless wall of sets tilting away into fog, every one a pile of apps. It holds there half a second while every set pings. |
| 5.8–7.0 | `melt them down` is typed from 6.05 with the music stopped. Enter lands at 7.0. Three frames of nothing. |
| 7.0–8.8 | Ignition travels out from our set and every screen burns through from a molten edge; the drips run down the wall and braid into one river under a drift of embers; the camera falls with it. |
| 8.8–10.35 | The river fills a mould: Foundry's bar. It cools from the rim in: the skin crusts and cracks, the casting shrinks from the mould wall, smoke lifts, a few sparks pop. The heat retreats to where the cursor lives. A band of light runs along the iron; the sand mould is knocked out; the iron shell flakes away to the glass bar. |
| 10.35–11.35 | The last molten point is the caret. **One for every job.** types out of it from 10.51. |
| 12.0–17.97 | **The kills**, on one even cadence. Each is just its line typed in the bar while the picture waits, then enter: `convert to gif` (Muybridge's plate gallops), `remove background`, `100 usd in eur` (89.25, ECB rate on 2026-10-05), `tile windows`, `download youtu.be/lumiere-1895` (the clip opens out of the bar; the train comes through). |
| 17.98–24.63 | `translate to japanese`, last. Its enter is the Quindar tone, and then Armstrong, whole and uninterrupted: "That's one small step for man," builds and turns Japanese in his pause; "one giant leap" builds under it. |
| 24.63–30.03 | The picture cuts to the Earth as Armstrong says "...mankind." and the score swells under it. The camera dives at the Earth, the score stops 0.4 s before the logo, the bar holds still in the silence, and its caret flies into the name. The Earth holds in the name for two beats (to 25.63). The wordmark is the last casting: it ignites white-hot as one casting and cools to iron as the camera steps back. Two beats on (26.63) the line lands under it, the last hit, and the caret lights. The Quindar out-tone ends the transmission at 28.13 and the caret goes out on its frame. The chord decays under the held card until the end at 30.03. |

# Sound

The score is composed in code on the picture's own times: D major, 120 BPM, computed instruments (Rhodes, finger bass,
guitar, kit) from `tools/synth.py`, with Armstrong mixed in (`tools/score.py`). The sound effects are computed keys,
enters and a logo drum (`tools/sfx.py`), cued from `tools/timing.py` by `tools/cues.py` and mixed and checked by
[opus-sound-layer](https://github.com/Bodila51/opus-sound-layer). `AGENTS.md` has the pipeline and the rules learned.

## Earlier sound plan (superseded)

The text below describes the first sound plan: percussion and texture with a B-flat drone, and real recordings for
every effect. The current cue sheet (`audio/cues.json`) does not place those recordings.

- **Act I**: each word is a 1940s typewriter strike with its machine on it: the typing pool, a phone bell, Morse, a
  1957 computer's blips. "job." is the Saturn V: a hit and sub, then the shuttle's roar, dead on the Act II cut.
- **Act II**: a modern keyboard for the I-beam; the apps land as glass ticks rising in pitch; the set's static tears
  as it overheats; one whoosh on the pull-back, the whole wall pings once.
- **Melt**: the music stops dead under `melt them down`; the enter and a riser land with the blast; then lava and
  furnace roar, growing as the camera falls with the river.
- **Cast**: the river slams into the mould (metal, sub, the fall's whoosh) and the roar stops; then it sizzles,
  pings as it contracts, the light sweeps, the mould is knocked out (thud and sand), the shell flakes, the caret ticks.
- **Kills**: the bar is summoned, one typing take per command, enter is an anvil. Each job sounds like itself: the
  gallop, a wipe and the horse bolting, ratchet reels landing on a till, latches on the window seams, the steam
  whistle and train; the train passes into the moon.
- **Logo**: a reverse cymbal and a sub on the pull-back through the tiles, the tiles quench, then the Quindar out-tone.
