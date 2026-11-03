#!/bin/bash
# usage: ef.sh <file> "<query>" <top> <tag> [kind]
PY=/Users/hridyaagrawal/Honey/earshot/.venv/bin/python
f=$1; q=$2; n=$3; tag=$4; kind=${5:-event}
out=out/audio-review/$(basename $(dirname $f))/find_$(basename $f .ogg)_$tag.json
$PY -m earshot find "$f" "$q" --kind $kind --top $n --json --out "$out" >/dev/null 2>&1
python3 - "$out" "$f" "$q" <<'PYEOF'
import json,sys
d=json.load(open(sys.argv[1])); print('##',sys.argv[2].split('/')[-1][:40],'|',sys.argv[3])
for s in d['segments']:
    print('  %7.3f-%7.3f (%.2fs) z%+.1f %-9s pk%6.1f head%5.0f tail%5.0f %s'%(s['start'],s['end'],s['duration'],s['z'],s['verdict'],s['peak_dbfs'],s['head_db'],s['tail_db'],('['+s['cut']+']') if s['cut'] else ''))
PYEOF
