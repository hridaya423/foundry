# Sources and licenses

Every piece of third-party media in the film, where it came from, and the terms it is used under. Nothing here is copyrighted material used without permission: the footage and documents are public domain, the museum objects are CC0, the fonts are OFL, and the audio was generated for this project with ElevenLabs.

## Footage

| Clip in film | Source | License |
| --- | --- | --- |
| `tube-silhouette`, `tube-pour`, `tube-ladle`, `pour-ladle`, `pour-streams`, `crucible` | *Master Hands*, part 2 (Jam Handy Organization for Chevrolet, 1936). Prelinger Archives, [archive.org/details/MasterHa1936_2](https://archive.org/details/MasterHa1936_2) | Public domain (Prelinger Archives) |
| reference only | *Master Hands*, part 1 (1936). [archive.org/details/MasterHa1936](https://archive.org/details/MasterHa1936) | Public domain (Prelinger Archives) |
| reference only | *American Maker* (1960). [archive.org/details/American1960](https://archive.org/details/American1960) | Public domain (Prelinger Archives) |
| `tube-smith` | *Blacksmith Scene* (Edison Manufacturing Co., 1893). [archive.org/details/blacksmith-scene-1893_202602](https://archive.org/details/blacksmith-scene-1893_202602) | Public Domain Mark 1.0 |
| `flash-fireball`, `flash-curtain`, `app-liftoff`, `engines-pad` | NASA, *Apollo 11 25th Anniversary Historical Footage and B-roll* (KSC-19940705-MH-NAS01-0001). [images.nasa.gov](https://images.nasa.gov/details/KSC-19940705-MH-NAS01-0001-Apollo_11_25th_Historical_Footage_and_Broll-B_0905) | NASA media, not copyrighted |
| every-job `listen` (climax reaction shot) | Same reel, Cut 3 "Lunar Orbit & Descent", item c "LEM descends to the Moon": the CAPCOM console during the landing, 20 July 1969; `footage/nasa-a11-broll.mp4` 1216.72-1218.52 s | NASA media, not copyrighted |
| `orbit-earth`, `interstage` | NASA, *HD 049 Mercury Gemini Apollo Resource Reel 1*. [images.nasa.gov](https://images.nasa.gov/details/HD%20049%20Mercury_Gemini_Apollo_Resource%20Reel%201) | NASA media, not copyrighted |

## Stills and documents

| Asset | Used for | Source | License |
| --- | --- | --- | --- |
| `assets/img/earth.png` | EVERY LANGUAGE, file grid, cast wall | NASA, "The Blue Marble" (AS17-148-22727, Apollo 17, 1972) | NASA media, not copyrighted |
| `assets/img/flightplan.jpg` | EVERY FILE grid, strobe | NASA Manned Spacecraft Center, *Apollo 11 Final Flight Plan*, July 1, 1969, page 3-42 | U.S. government work, public domain |
| `assets/img/patent-lamp.jpg` | EVERY FILE Quick Look (`patent_1880.png`), EVERY COPY, cast wall | Thomas A. Edison's patent petition for the electric lamp, U.S. National Archives | U.S. government record, public domain |
| `assets/img/bust.jpg` (and the derived `bust-cut.png`, `format/*.png`) | EVERY FORMAT | Cleveland Museum of Art, *Head of a Woman*, 1938.426, [clevelandart.org/art/1938.426](https://clevelandart.org/art/1938.426) | CC0 (CMA Open Access) |

## Museum objects (`assets/img/objects/`, card crops in `assets/img/cards/`)

All from the Cleveland Museum of Art Open Access program, CC0. Matched to the collection by exact image dimensions and a pixel comparison against the museum's own files.

| File | Object | Accession |
| --- | --- | --- |
| `camera.jpg` | *Priest, France* (daguerreotype) | [2021.76](https://clevelandart.org/art/2021.76) |
| `currency.jpg` | *Coin: Havishka* (obverse) | [1999.227.a](https://clevelandart.org/art/1999.227.a) |
| `dice.jpg` | *Gambling Dice* | [1917.413.2.a](https://clevelandart.org/art/1917.413.2.a) |
| `emoji.jpg` | *Noh Mask: Waka-onna* | [1972.69](https://clevelandart.org/art/1972.69) |
| `note.jpg` | *Studies of a Seated Female, Child's Head, and Three Studies of a Baby* | [1978.37](https://clevelandart.org/art/1978.37) |
| `quicklink.jpg` | *Twelve Medallions Mounted as a Necklace* | [1947.507](https://clevelandart.org/art/1947.507) |
| `script.jpg` | *Poem by Wang Wei in the Cursive Script Style* | [1961.421.2](https://clevelandart.org/art/1961.421.2) |
| `shortcut.jpg` | *Key* | [1952.586](https://clevelandart.org/art/1952.586) |
| `snippet.jpg` | *Scissors* | [1916.313.a](https://clevelandart.org/art/1916.313.a) |
| `unit.jpg` | *Miniature Table with Compass* | [1966.480](https://clevelandart.org/art/1966.480) |
| `uuid.jpg` | *Cylinder Seal* | [1964.458](https://clevelandart.org/art/1964.458) |
| `widget.jpg` | *Clock* | [1966.475](https://clevelandart.org/art/1966.475) |

## Made for this film

| Asset | How |
| --- | --- |
| CRT television (`assets/img/tv/`) | Modeled and rendered in Blender (`assets/img/tv/tv.py`) |
| Keycaps, sparks, tile cast, wordmark | Three.js, built in `js/gl.js` and `js/cast.js` |
| Painted strokes, UI, network, keycaps | SVG and DOM, built in `js/ui.js` and `js/act*.js` |
| Grain (`assets/img/grain.png`) | Generated noise |
| Foundry wordmark geometry | Foundry's own logo (`js/data.js`) |

## Type

| Font | License |
| --- | --- |
| Archivo (variable) | SIL Open Font License, `assets/fonts/OFL-Archivo.txt` |
| IBM Plex Mono | SIL Open Font License, `assets/fonts/OFL-IBMPlexMono.txt` |
| Noto Sans, Noto Sans JP, Noto Sans SC (subsets) | SIL Open Font License, `assets/fonts/OFL-Noto.txt` |

## Audio

| Asset | How |
| --- | --- |
| Score (`assets/audio/music/score15-b.mp3`, `drive15-b.mp3`) | Generated with ElevenLabs Music from a sectioned composition plan (`tools/score.py`), spliced on the 128 BPM grid in `data/timing.json` |
| Sound effects (`assets/audio/sfx/`) | Generated with ElevenLabs Sound Effects (`tools/eleven.py`) |
| Voice, "Thirteen point six milliseconds." (`assets/audio/vo/vo-adamstone.mp3`, tempo 1.08 in `vo-adamstone-fast.wav`) | ElevenLabs text to speech, multilingual v2 |
| Master (`assets/audio/mix.wav`) | `tools/mix.py`: cues from `data/cues.json`, static gain to -14 LUFS, true peak under -1 dBTP |

Commercial use of the generated audio follows the ElevenLabs plan the key belongs to.

## Style references (not in the film)

Studied for pacing, cut length, and technique only, kept in `research/refs/` and analysed in `research/analysis/`: three a16z films, LexnLin, ideogram, and the Lexis ad v11.
