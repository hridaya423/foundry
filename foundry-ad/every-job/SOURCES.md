# Sources and licenses

Footage and stills are public domain; fonts are OFL.

Status (2026-11-09): the music (`tools/score.py`) is computed in code (`tools/synth.py`). The current cue sheet places computed keys, enters and a logo drum (`tools/sfx.py`). Most rows in the Audio table below are recordings from earlier versions. `audio/cues.json` and `audio/CREDITS.md` list what the film places now. `tools/music.py` and `audio/music/` hold earlier ElevenLabs takes that `score.py` does not read.

| Asset | Source | License |
| --- | --- | --- |
| Muybridge plate (`assets/img/plate.jpg`) | Wikimedia Commons, "The Horse in Motion high res.jpg" (Muybridge, 1878) | Public domain |
| Gallop animation (`seq/gallop`, `seq/horse` matte) | Wikimedia Commons, "Horse in Motion - Sallie Gardner (animation).webm" | Public domain |
| Armstrong audio | Wikimedia Commons, "Armstrong Small Step.ogg" (NASA, 1969) | Public domain |
| Apollo 11 ladder, Aldrin, flag, launch, Earth, splashdown, crowd | NASA, Apollo 11 25th Anniversary b-roll (images.nasa.gov) | NASA media, not copyrighted |
| The people the line reaches today, at the launch (`seq/smile`, `seq/couple`) | NASA, "Artemis II Live Launch Coverage - Banana Creek Reaction Shots" (`KSC-20260401-MH-AJN01-0001-Artemis_II_Launch_ISO_Banana_Creek_Reaction_Shots_4K`, Kennedy Space Center, 1 April 2026; https://images.nasa.gov/details/KSC-20260401-MH-AJN01-0001-Artemis_II_Launch_ISO_Banana_Creek_Reaction_Shots_4K), cut from the 3840×2160 original over HTTP by `tools/artemis.sh`: the same couple in the low sun, she watches and then gasps, 197.35-199.35 s (a 1.5× crop that follows the camera's pan); she watches, then her smile breaks, 217.1-219.6 s (a 1.33× crop) | NASA media, not copyrighted (public domain). Mission patches and lanyards are visible on clothing; no endorsement is implied. NASA's guidelines: commercial use of an identifiable person may need their permission (check before release) |
| Earthrise (`assets/img/earthrise.jpg`) | Wikimedia Commons, "NASA-Apollo8-Dec24-Earthrise.jpg" | Public domain |
| Wright Flyer (`assets/img/wright.jpg`) | Wikimedia Commons, "First flight2.jpg" (1903) | Public domain |
| Lumière train | Wikimedia Commons, "Arrival of a Train at La Ciotat (The Lumière Brothers, 1895).webm" | Public domain |
| Méliès moon, capsule | Wikimedia Commons, "Le Voyage dans la Lune (1902).webm" | Public domain |
| Switchboard operator | *Invisible Diplomats* (1965), Prelinger Archives | Public domain |
| Telegraph, ticker, teleprinter | *Telegram for America* (1956), Prelinger Archives | Public domain |
| Card catalogue | *Library Organization* (1951), Prelinger Archives | Public domain |
| Console, tape reels | *Electronic Computers Improve Management Control* (1957), Prelinger Archives | Public domain |
| Typing pool | *I Want to Be a Secretary* (1941), Prelinger Archives | Public domain |
| Blacksmith (intro, panes) | *Blacksmith Scene* (Edison, 1893), archive.org | Public Domain Mark |
| Apollo 11 EVA TV (line B) | Wikimedia Commons, "Restored Apollo 11 Moonwalk - Original NASA EVA Mission Video" | Public domain |
| Steel pour, crucible | *Master Hands* (1936), Prelinger Archives | Public domain |
| Saturn V liftoff | NASA Apollo 11 b-roll | NASA media |
| Foundry wordmark (`js/tiles.js`) | `anvil/public/assets/foundry/tile-layout.json` | Foundry |
| Lumière train (download beat) | same file, 9.2–12.4 s | Public domain |
| Act I machines | typing pool (*I Want to Be a Secretary*, 1941), switchboard (*Invisible Diplomats*, 1965), telegraph and teleprinter (*Telegram for America*, 1956), card catalogue (*Library Organization*, 1951), computer console (*Electronic Computers Improve Management Control*, 1957), Wright Flyer (1903), Saturn V (NASA) | Public domain |
| TV set (`assets/img/tv/`) | Modelled and rendered for this film, `blender/tv.py` | Made for this film |
| Fonts | IBM Plex Mono; IBM Plex Sans, Plex Sans JP, Plex Sans Devanagari and Plex Sans Arabic (the translations: Plex Mono's own family), the unmodified files from [google/fonts](https://github.com/google/fonts/tree/main/ofl) (`ofl/ibmplexsans*/`): Plex is a Reserved Font Name, so they are not subset. Licence text: `OFL-IBMPlexSans.txt` | SIL OFL |
| The four answers (`timing.py` ANSWERS) | The second half of each language's best-attested published rendering (audit/gauntlet/climax/translations.md) of "That's one small step for man, one giant leap for mankind." (Japanese: the line the bar already used) | Facts, not copyrightable |
| Super-resolution of the step, flag and Earthrise plates (`tools/seq.py` SR, `earthrise`) | [Real-ESRGAN](https://github.com/xinntao/Real-ESRGAN) model `realesrgan-x4plus`, run by [Real-ESRGAN-ncnn-vulkan](https://github.com/xinntao/Real-ESRGAN-ncnn-vulkan) (macOS release build, `~/Honey/tools/realesrgan`); blended into each plate's own upscale at 0.4 (step), 0.6 (flag) and 0.6 on the Earth's disc only (Earthrise) | Real-ESRGAN and its weights: BSD 3-Clause; ncnn-vulkan port: MIT. The output frames are the public-domain footage, processed |

## Audio (credit required for CC BY items)

| Sound | Source | License |
| --- | --- | --- |
| Phonautograph, "Au clair de la lune" (Scott de Martinville, 1860) | Wikimedia Commons, "Au Clair de la Lune (1860) new.ogg" | Public domain |
| Armstrong, "That's one small step..." | Wikimedia Commons, "Armstrong Small Step.ogg" (NASA) | Public domain |
| Anvil | Wikimedia Commons, "WWS Blacksmith8217sanvil.ogg" (World Wide Sounds) | CC BY 4.0 |
| Typewriter | Wikimedia Commons, "WWS Typewriter.ogg" (World Wide Sounds) | CC BY 4.0 |
| Teleprinter | Wikimedia Commons, "WWS Teleprintertyping.ogg" (World Wide Sounds) | CC BY 4.0 |
| Steam whistle | Wikimedia Commons, "WWS SteamWhistle.ogg" (World Wide Sounds) | CC BY 4.0 |
| Horses | Wikimedia Commons, "Six Horses Galloping By.ogg" | CC0 |
| Every other sound effect and roar | Freesound and Kenney recordings via [opus-sound-layer](https://github.com/Bodila51/opus-sound-layer); one line per file in `audio/CREDITS.md` | CC0 |
| The kills' sixteenth-note tick (`tools/score.py` TICK) | Freesound, "Metal tick 1" by kubawolanin (185611), via the sound-layer kit (`tick/fs-185611-metal-tick-1-1`) | CC0 |
| The keys under "gran" and "salto" (`tools/cues.py` RING_KEYS) | Freesound, "vintage keyboard 2" (194796) and "vintage keyboard 3" (194797), via the sound-layer kit; landing pages in `audio/CREDITS.md` | CC0 |
| The orchestra under the payoff (`audio/own/orch-swell.wav`, `tools/score.py` ORCH) | Freesound, "Music Dramatic Orchestral Ending 3.mp3" by FunWithSound (588391), 4.0-10.0 s, two semitones down | CC0 (checked on the Freesound page, 19 Oct 2026) |
| The fire under the answers | Freesound, "shuttlelaunch.wav" by klangfabrik (220127), 36.0-40.4 s | CC0 |
| Quindar tones | Generated pure sines (2525 / 2475 Hz, 250 ms), as NASA's were; the Commons recordings are CC BY-SA and would make the film a ShareAlike adaptation | — |
| The score from the moon cut to the logo (`audio/music/end-16-32.mp3`) | ElevenLabs Music (`music_v2_5`), generated for this film by `tools/music.py --end 16 32`, conditioned on take 16; the end card keeps `end-16-25` | ElevenLabs output under the account's plan terms (commercial use depends on the plan: check before release) |
