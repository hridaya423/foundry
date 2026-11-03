#!/bin/bash
# Final master with motion blur from 8 sub-frames per 60fps frame. HyperFrames renders at most 240fps, so the film is
# rendered twice at 240: once as is and once shifted by half a sub-frame (js/toff.js = 1/480 s); the two passes
# interleave into a 480fps stream, then a centred 7-sub-frame shutter (315 degrees) is integrated per output frame.
# Cuts sit half a frame early ((n - 0.5) / 60), so sub-frames 8k-4 .. 8k+3 belong to one shot and the window
# 8k-3 .. 8k+3 never straddles a cut.
# usage: tools/final.sh [out.mp4] [--skip-render]
set -e
cd "$(dirname "$0")/.."
OUT="${1:-renders/foundry-ad.mp4}"
mkdir -p renders
restore() { printf '%s\n' "// Composition-time offset in seconds, rewritten by tools/final.sh for the half-sub-frame render pass." "window.__TOFF = 0;" > js/toff.js; }
trap restore EXIT
if [ "$2" != "--skip-render" ]; then
  .venv/bin/python tools/mix.py
  restore
  npx --yes hyperframes@0.8.98 render --fps 240 --quality high --browser-gpu --experimental-fast-capture=false -o renders/hi-a.mp4
  printf '%s\n' "// Composition-time offset in seconds, rewritten by tools/final.sh for the half-sub-frame render pass." "window.__TOFF = 1 / 480;" > js/toff.js
  npx --yes hyperframes@0.8.98 render --fps 240 --quality high --browser-gpu --experimental-fast-capture=false -o renders/hi-b.mp4
  restore
  ffmpeg -v error -y -i renders/hi-a.mp4 -i renders/hi-b.mp4 -filter_complex \
    "[0:v]settb=1/480,setpts=2*N[a];[1:v]settb=1/480,setpts=2*N+1[b];[a][b]interleave,tmix=frames=7,select='eq(mod(n\,8)\,3)',setpts=N/60/TB" \
    -r 60 -c:v libx264 -preset slow -crf 10 -pix_fmt yuv420p -an renders/mb60.mp4
fi
ffmpeg -v error -y -i renders/mb60.mp4 -i assets/audio/mix.wav -map 0:v -map 1:a \
  -vf setparams=color_primaries=bt709:color_trc=bt709:colorspace=bt709:range=tv \
  -c:v libx264 -preset slow -crf ${CRF:-16} -pix_fmt yuv420p -profile:v high \
  -colorspace bt709 -color_primaries bt709 -color_trc bt709 -color_range tv \
  -c:a aac -b:a 320k -movflags +faststart -shortest "$OUT"
ffprobe -v error -show_entries format=duration:stream=codec_type,r_frame_rate,width,height -of compact "$OUT"
