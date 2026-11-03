#!/usr/bin/env bash
# Fails when design literals escape FoundryTheme — every font size, colour,
# opacity, radius and duration must come from the token file so the UI stays
# one vocabulary.
#
# Usage: scripts/lint-design.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
THEME="$ROOT/Sources/Foundry/UI/FoundryTheme.swift"

matches() {
    find "$ROOT/Sources" -name '*.swift' ! -path "$THEME" -print0 \
        | xargs -0 grep -nHE "$1" \
        | grep -v 'NSColor(red:' \
        || true
}

failed=0
check() {
    local name=$1 pattern=$2 found
    found=$(matches "$pattern")
    if [[ -n $found ]]; then
        echo "error: $name:" >&2
        echo "$found" >&2
        failed=1
    fi
}

check font-size '\.system\(size:'
check rgb-colour 'Color\(red:'
check literal-opacity 'opacity\(0\.'
check opacity-expression 'opacity\([^)]*[0-9]\.[0-9]'
check corner-radius 'cornerRadius: *[0-9]'
check duration 'duration: *[0-9]'
check spring '\.spring\('
check named-colour '(^|[^S])Color\.(red|green|blue|orange|yellow)\b'
check theme-escape 'FoundryTheme\.(dark|light|primary)\([0-9]'
check pointing-hand 'pointerCursor\(\)'
check frame-height 'frame\((min)?[hH]eight: *[0-9]'

exit $failed
