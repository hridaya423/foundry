#!/bin/bash
# Fast dev stills: seek the composition in a plain browser and save 1920x1080 frames + a contact sheet.
# usage: tools/shots.sh out_dir t1 t2 ...   (needs `python3 -m http.server 8769` in melt/)
set -e
OUT="$1"; shift
mkdir -p "$OUT"
agent-browser set viewport 1920 1080 >/dev/null
agent-browser open "http://localhost:8769/index.html?$(date +%s)" >/dev/null
for i in $(seq 1 300); do
  r=$(agent-browser eval "!!window.__ready" 2>/dev/null | tail -1)
  [ "$r" = "true" ] && break; sleep 0.5
done
inputs=()
for t in "$@"; do
  agent-browser eval "window.__timelines.main.seek($t); 1" >/dev/null
  agent-browser screenshot "$OUT/t$t.png" >/dev/null
  inputs+=("$OUT/t$t.png")
done
n=${#inputs[@]}; cols=$(( n < 3 ? n : 3 )); rows=$(( (n + cols - 1) / cols ))
layout=$(python3 -c "print('|'.join(f'{(i%$cols)*640}_{(i//$cols)*360}' for i in range($n)))")
args=(); for f in "${inputs[@]}"; do args+=(-i "$f"); done
filt=""; for i in $(seq 0 $((n-1))); do filt+="[$i]scale=640:360[s$i];"; done
for i in $(seq 0 $((n-1))); do filt+="[s$i]"; done
if [ "$n" -gt 1 ]; then filt+="xstack=inputs=$n:layout=$layout:fill=black"; else filt="[0]scale=640:360"; fi
ffmpeg -v error -y "${args[@]}" -filter_complex "$filt" "$OUT/sheet.jpg"
echo "$OUT/sheet.jpg"
