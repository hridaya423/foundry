#!/bin/bash
# Cuts every sound the mix uses that is not in the sound-layer kit into audio/own/ (48 kHz mono).
# Sources: the film's own period recordings (../research/audio-pd) and CC0 Freesound recordings fetched by
# `sfx.py search` into audio/candidates/. Credits for each file: tools/cues.py (OWN, KIT_CUTS).
# usage: tools/sources.sh
set -e
cd "$(dirname "$0")/.."
PD=../research/audio-pd; CA=audio/candidates; OUT=audio/own
mkdir -p "$OUT"

# cut SRC START DUR FADE_IN FADE_OUT NAME [EXTRA_FILTER]
cut() {
  local st; st=$(python3 -c "print(max(0, $3 - $5))")
  ffmpeg -v error -y -ss "$2" -t "$3" -i "$1" -ac 1 -ar 48000 \
    -af "${7:+$7,}afade=t=in:d=$4,afade=t=out:st=$st:d=$5" "$OUT/$6.wav"
}

i=1; for t in 4.44 4.86 7.35 8.22 11.11; do cut "$PD/WWS_Typewriter.ogg" $t 0.15 0.003 0.05 typewriter-$i; i=$((i + 1)); done
cut "$PD/WWS_Blacksmith8217sanvil.ogg" 63.626 0.62 0.003 0.25 anvil-1
cut "$PD/WWS_Blacksmith8217sanvil.ogg" 18.046 0.68 0.003 0.25 anvil-2
cut "$PD/WWS_Blacksmith8217sanvil.ogg" 78.946 0.62 0.003 0.25 anvil-3
cut "$PD/WWS_Blacksmith8217sanvil.ogg" 31.786 0.62 0.003 0.25 anvil-4
cut "$PD/Six_Horses_Galloping_By.ogg" 8.3 1.1 0.01 0.3 horses
cut "$PD/WWS_SteamWhistle.ogg" 1.0 1.0 0.01 0.3 whistle
# the Act I machines layer onto their typewriter strike, so each is cut to peak within 30 ms of its start
cut "$PD/WWS_Teleprintertyping.ogg" 1.915 0.36 0.003 0.06 typing-pool
cut "$CA/chime/ov-52f48b01.wav" 0.06 0.42 0.002 0.12 phone-bell
cut "$CA/glitch/ov-bbdaf771.wav" 0 0.42 0.002 0.06 morse
cut "$CA/ui/ov-fdc656c8.wav" 0.065 0.40 0.002 0.06 computer
# tails that would ring over the next picture event stop before it: ignition -> the Act II cut (0.8 s), the cast ->
# the first ping of the cooling iron (0.9 s), the Act II thunk -> the first keystroke, the train pass-by -> the typing
K=audio/kit
cut $K/hit/fs-710368-cinematic-punch-1.wav 0 0.8 0.001 0.08 ignition-punch
cut $K/boom/fs-636624-deep-hit-2.wav 0 0.8 0.001 0.08 ignition-boom
cut $K/hit/fs-359139-low-metal-hit-3-wav-1.wav 0 0.9 0.001 0.35 cast-hit
cut $K/boom/fs-268608-juno-sub-wav-1.wav 0 0.9 0.001 0.35 cast-sub
cut $K/transition/fs-521040-whoosh-large-verb-er-sfx-6-w-1.wav 0 2.3 0.01 0.3 river-fall
cut $K/boom/fs-13895-43-wav-1.wav 0 0.2 0.001 0.08 act2-thunk
cut $K/transition/fs-522693-arrow-ghost-pass-whoosh-1.wav 0 0.45 0.01 0.15 pass-by
# the set's static tears above the groove: its hum would sit on the kick
cut $K/glitch/fs-534735-digital-glitch-static-noise-1.wav 0.35 0.8 0.05 0.25 overheat "highpass=f=1000:poles=2,highpass=f=1000:poles=2"
cut "$CA/boom/_raw/ov-a70995b6.mp3" 0.25 0.8 0.003 0.04 shuttle-roar
cut "$CA/transition/_raw/ov-95d0ac29.mp3" 7.35 2.7 0.003 0.35 volcano
cut "$CA/transition/_raw/ov-4300c350.mp3" 2.0 2.4 0.15 0.3 furnace
cut "$CA/riser/_raw/ov-47f6a4ef.mp3" 3.0 1.0 0.1 0.4 sizzle
cut "$CA/riser/_raw/ov-47f6a4ef.mp3" 10.3 0.5 0.1 0.25 quench
cut "$CA/paper/ov-f96e3f0a.wav" 0 0.6 0.01 0.3 sand
cut "$CA/swish/_raw/ov-96619ca8.mp3" 7.0 0.95 0.08 0.15 train
# Quindar tones are pure sines by definition (NASA: 2525 Hz intro, 2475 Hz outro, 250 ms)
for q in "2525 quindar-in" "2475 quindar-out"; do set -- $q
  ffmpeg -v error -y -f lavfi -i "sine=f=$1:d=0.25:sample_rate=48000" -af "volume=-6dB,afade=t=in:d=0.004,afade=t=out:st=0.24:d=0.01" "$OUT/$2.wav"
done
ls "$OUT" | wc -l | xargs echo "audio/own:"
