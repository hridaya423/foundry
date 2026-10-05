#!/bin/bash
# Download Wikimedia Commons files by title and log their license.
# usage: tools/commons.sh out_dir "Title one.jpg" "Title two.webm" ...
set -e
OUT="$1"; shift
mkdir -p "$OUT"
for t in "$@"; do
  q=$(python3 -c "import urllib.parse,sys;print(urllib.parse.quote('File:'+sys.argv[1]))" "$t")
  for k in 1 2 3 4 5 6; do
    info=$(curl -s -A "foundry-ad research" "https://commons.wikimedia.org/w/api.php?action=query&prop=imageinfo&iiprop=url|size|extmetadata&format=json&titles=$q")
    echo "$info" | python3 -c "import json,sys;json.load(sys.stdin)" 2>/dev/null && break
    sleep $((k * 3))
  done
  line=$(echo "$info" | python3 -c "
import json,sys
p=next(iter(json.load(sys.stdin)['query']['pages'].values()))['imageinfo'][0]
m=p.get('extmetadata',{})
print(p['url']+'\t'+str(m.get('LicenseShortName',{}).get('value'))+'\t'+str(p.get('width'))+'x'+str(p.get('height')))")
  url=$(echo "$line" | cut -f1)
  f="$OUT/$(echo "$t" | tr ' ' '_')"
  [ -s "$f" ] || curl -sL -A "foundry-ad research" -o "$f" "$url"
  printf '%s\t%s\n' "$t" "$(echo "$line" | cut -f2-3)" | tee -a "$OUT/LICENSES.tsv"
done
