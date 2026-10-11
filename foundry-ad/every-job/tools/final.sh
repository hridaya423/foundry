#!/bin/bash
# Final master: timing -> music/voice stems -> sound-effect cues -> sound-layer mix -> 120 fps render -> sub-frame
# pairs averaged (360 degree shutter) -> 60 fps + audio -> sound-layer QA.
# usage: tools/final.sh [out.mp4] [--skip-render]
# needs: ffmpeg, uv; the kit (uv run sound-layer/scripts/sfx.py kit) and tools/sources.sh run once.
set -e
cd "$(dirname "$0")/.."
OUT="${1:-renders/foundry-every-job.mp4}"
mkdir -p renders
python3 tools/timing.py >/dev/null
uv run -q tools/score.py
python3 tools/cues.py
uv run -q tools/takes.py >/dev/null
uv run -q sound-layer/scripts/mix.py audio/cues.json --out audio | head -1
cp audio/mix.wav assets/audio/mix.wav
if [ "$2" != "--skip-render" ]; then
  npx --yes hyperframes@0.8.107 render --fps 120 --quality high --browser-gpu -o renders/hi120.mp4
  ffmpeg -v error -y -i renders/hi120.mp4 -vf "tmix=frames=2,select='eq(mod(n\,2)\,1)',setpts=N/60/TB" -r 60 \
    -c:v libx264 -preset slow -crf 10 -pix_fmt yuv420p -an renders/mb60.mp4
  VIDEO=renders/mb60.mp4
  ffmpeg -v error -y -i "$VIDEO" -i audio/mix.wav -map 0:v -map 1:a \
    -c:v libx264 -preset slow -crf ${CRF:-15} -pix_fmt yuv420p -profile:v high \
    -colorspace bt709 -color_primaries bt709 -color_trc bt709 -color_range tv \
    -c:a aac -b:a 320k -movflags +faststart -shortest "$OUT"
else
  # picture unchanged: keep the existing video stream, replace only the sound
  ffmpeg -v error -y -i "$OUT" -i audio/mix.wav -map 0:v -map 1:a -c:v copy -c:a aac -b:a 320k -movflags +faststart -shortest renders/.remux.mp4
  mv renders/.remux.mp4 "$OUT"
fi
ffprobe -v error -show_entries format=duration:stream=codec_type,r_frame_rate,width,height -of compact "$OUT"
uv run -q sound-layer/scripts/qa.py "$OUT"
