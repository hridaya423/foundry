#!/bin/bash
# Final master: timing -> score -> 120 fps render -> sub-frame pairs averaged (360 degree shutter) -> 60 fps + audio.
# usage: tools/final.sh [out.mp4] [--skip-render]
set -e
cd "$(dirname "$0")/.."
OUT="${1:-renders/foundry-every-job.mp4}"
mkdir -p renders
python3 tools/timing.py >/dev/null
../.venv/bin/python tools/score.py
if [ "$2" != "--skip-render" ]; then
  npx --yes hyperframes@0.8.107 render --fps 120 --quality high --browser-gpu -o renders/hi120.mp4
fi
ffmpeg -v error -y -i renders/hi120.mp4 -vf "tmix=frames=2,select='eq(mod(n\,2)\,1)',setpts=N/60/TB" -r 60 \
  -c:v libx264 -preset slow -crf 10 -pix_fmt yuv420p -an renders/mb60.mp4
ffmpeg -v error -y -i renders/mb60.mp4 -i assets/audio/mix.wav -map 0:v -map 1:a \
  -c:v libx264 -preset slow -crf ${CRF:-15} -pix_fmt yuv420p -profile:v high \
  -colorspace bt709 -color_primaries bt709 -color_trc bt709 -color_range tv \
  -af "volume=+1.0dB,lowpass=f=16500,alimiter=limit=0.7:attack=2:release=60:level=false" -c:a aac -b:a 320k -movflags +faststart -shortest "$OUT"
ffprobe -v error -show_entries format=duration:stream=codec_type,r_frame_rate,width,height -of compact "$OUT"
