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

# Act I: a 1940s manual typewriter, the typebar slap, the platen and the room (earshot z 4.3-4.5 "manual typewriter", 0.94-0.997
# against a modern keyboard; the WWS strikes read as a mech keyboard, z 2.56). Each cut starts 12 ms before the slap
OP=$CA/opening
i=1; for t in 37.308 234.670 317.423 434.663 473.235; do cut "$OP/typewriter/hit/_raw/ov-1bfe29bc.mp3" $t 0.26 0.003 0.08 typewriter-$i; i=$((i + 1)); done
cut "$OP/typewriter/hit/_raw/ov-b3b9eac2.mp3" 0.075 0.42 0.003 0.12 carriage              # bell and carriage return, peak at 30 ms
cut "$OP/relay/click/_raw/ov-88ad20c6.mp3" 45.16 0.42 0.002 0.08 relay                     # the 1957 console: relays switching, peak at 17 ms
cut "$OP/crack/hit/_raw/ov-963ac838.mp3" 11.477 0.45 0.001 0.15 ignition-crack             # the 2-4 kHz crack the ignition lacked
cut "$CA/boom/ov-c3bb55fc.wav" 3.0 0.8 0.003 0.08 ignition-rumble                          # a real launch rumble under it
# the apps land on the set's glass: real glass taps (p_real 0.74-0.96; the Kenney taps read synthetic, 0.035-0.17)
for g in dd84c796:alegemaate 8e2ec086:cjspellsfish ebed486f:rutgermuller beb7f099:tairblenn-medium 2948ae02:tairblenn-small ee99cca2:soundbiter d48e72e1:holden; do
  cut "$OP/glass/tick/ov-${g%%:*}.wav" 0 0.15 0.001 0.04 "glass-${g##*:}"; done
# the anvils ring over a metal thud on every kill enter (cues.py), each set so that its 1-2 kHz ring carries less
# energy than the thud's low mids: the thud leads the hit, and mix.py levels it where the score is loud
cut "$PD/WWS_Blacksmith8217sanvil.ogg" 63.626 0.62 0.003 0.25 anvil-1 "volume=-8dB"
cut "$PD/WWS_Blacksmith8217sanvil.ogg" 18.046 0.45 0.003 0.25 anvil-2 "volume=-16dB"
cut "$PD/WWS_Blacksmith8217sanvil.ogg" 78.946 0.45 0.003 0.25 anvil-3 "volume=-14dB"
cut "$PD/WWS_Blacksmith8217sanvil.ogg" 31.786 0.62 0.003 0.25 anvil-4 "volume=-10dB"
# a gallop that reads as horses (earshot z 4.7 vs 0.8 for the old Six Horses trim); `sfx.py search "horse gallop" --type thump`
cut "$CA/thump/_raw/ov-e9ebc7e4.mp3" 11.3 0.92 0.01 0.3 horses     # done before the next command is typed
cut "$PD/WWS_SteamWhistle.ogg" 1.0 1.0 0.01 0.3 whistle
# the Act I machines layer onto their typewriter strike, so each is cut to peak within 30 ms of its start
cut "$PD/WWS_Teleprintertyping.ogg" 1.915 0.36 0.003 0.06 typing-pool
# the room the words are struck in: the same teleprinter, running, under Act I until the ignition's dead stop (score.py)
cut "$PD/WWS_Teleprintertyping.ogg" 3.0 1.62 0.002 0.08 typing-pool-room "highpass=f=400:poles=2,lowpass=f=5000:poles=2"   # clear of the strikes' bodies
cut "$CA/chime/ov-52f48b01.wav" 0.06 0.42 0.002 0.12 phone-bell "lowpass=f=4000:poles=2"   # its body, not its shimmer, carries the strike (qa hero body)
cut "$CA/glitch/ov-bbdaf771.wav" 0 0.42 0.002 0.06 morse
# tails that would ring over the next picture event stop before it: ignition -> the Act II cut (0.8 s), the cast ->
# the first ping of the cooling iron (0.9 s), the Act II thunk -> the first keystroke, the train pass-by -> the typing
K=audio/kit
cut $K/hit/fs-710368-cinematic-punch-1.wav 0 0.8 0.001 0.08 ignition-punch
cut $K/boom/fs-636624-deep-hit-2.wav 0 0.8 0.001 0.08 ignition-boom
cut $K/boom/fs-105351-backfire-ogg-1.wav 0 0.6 0.001 0.25 backfire      # the logo's ignition: gone before the press
cut $K/hit/fs-359139-low-metal-hit-3-wav-1.wav 0 0.9 0.001 0.35 cast-hit
cut $K/boom/fs-268608-juno-sub-wav-1.wav 0 0.9 0.001 0.35 cast-sub
cut $K/transition/fs-521040-whoosh-large-verb-er-sfx-6-w-1.wav 0 2.3 0.01 0.3 river-fall
cut $K/boom/fs-13895-43-wav-1.wav 0 0.2 0.001 0.08 act2-thunk
cut $K/hit/fs-573245-dark-timpani-1-wav-1.wav 0 0.45 0.001 0.2 timpani-short   # the arrival: gone before the first answer
cut $K/hit/fs-573245-dark-timpani-1-wav-1.wav 0 0.20 0.001 0.12 timpani-arrival   # the arrival, short enough that "gran" and "salto" get their keys
cut "$CA/orch/hit/_raw/ov-ee6f0bf9.mp3" 4.0 6.0 0.05 0.3 orch-swell   # a real string section holding D major (score.py: two semitones down, under the payoff)
cut $K/transition/fs-522693-arrow-ghost-pass-whoosh-1.wav 0 0.45 0.01 0.15 pass-by
# the kill enters: a metal thud under each anvil gives it 200-700 Hz body on phone speakers; the enter key moves a
# little every time it is pressed (semitones rise through the kills, +-1 dB)
cut $K/thump/fs-585575-metal-thud-1.wav 0 0.5 0.001 0.2 anvil-body "highpass=f=150:poles=2"
i=1; for v in "-1 0" "-0.5 -1" "0 1" "0.5 0" "1 -1"; do set -- $v
  cut $K/key/fs-180997-enter-key-2.wav 0 0.085 0.001 0.02 enter-$i "asetrate=$(python3 -c "print(round(48000 * 2 ** ($1 / 12)))"),aresample=48000,volume=$2dB"
  i=$((i + 1)); done
cut "$CA/boom/_raw/ov-a70995b6.mp3" 0.25 0.8 0.003 0.04 shuttle-roar
# the same launch, at full burn: the fire under the world's answer (score.py)
cut "$CA/boom/_raw/ov-a70995b6.mp3" 36.0 4.4 0.05 0.3 launch-roar
cut "$CA/transition/_raw/ov-95d0ac29.mp3" 7.35 2.7 0.003 0.35 volcano
cut "$CA/transition/_raw/ov-4300c350.mp3" 2.0 2.4 0.15 0.3 furnace
cut "$CA/riser/_raw/ov-47f6a4ef.mp3" 3.0 1.0 0.1 0.4 sizzle
cut "$CA/paper/ov-f96e3f0a.wav" 0 0.6 0.01 0.3 sand
cut "$CA/swish/_raw/ov-96619ca8.mp3" 7.0 0.95 0.08 0.15 train
# the room that heard it (the Mission Control insert, cues.py and score.py): a 25-person cheer from its first breath,
# and two sharp bursts of clapping and whoops
cut "$CA/crowd/_raw/ov-e78d0fd3.mp3" 0.2 1.6 0.01 0.3 cheer
cut "$CA/crowd/_raw/ov-bfb7ab87.mp3" 0.053 0.5 0.002 0.2 applause-1
cut "$CA/crowd/_raw/ov-bfb7ab87.mp3" 6.15 0.4 0.002 0.15 applause-2
# Quindar tones are pure sines by definition (NASA: 2525 Hz intro, 2475 Hz outro, 250 ms)
for q in "2525 quindar-in" "2475 quindar-out"; do set -- $q
  ffmpeg -v error -y -f lavfi -i "sine=f=$1:d=0.25:sample_rate=48000" -af "volume=-6dB,afade=t=in:d=0.004,afade=t=out:st=0.24:d=0.01" "$OUT/$2.wav"
done
ls "$OUT" | wc -l | xargs echo "audio/own:"
