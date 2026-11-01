#!/usr/bin/env bash
# Fails when design literals escape FoundryTheme — every font size, colour,
# opacity, radius and duration must come from the token file so the UI stays
# one vocabulary.
#
# Rules listed in scripts/lint-design-ratchet.txt may hold at most their
# allowed count; a count may only go down. Every other rule allows none.
#
# Usage: scripts/lint-design.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
THEME="$ROOT/Sources/Foundry/UI/FoundryTheme.swift"
RATCHET="$ROOT/scripts/lint-design-ratchet.txt"

matches() {
    find "$ROOT/Sources" -name '*.swift' ! -path "$THEME" -print0 \
        | xargs -0 grep -nHE "$1" \
        | grep -v 'NSColor(red:' \
        || true
}

allowance() {
    [[ -f $RATCHET ]] || { echo 0; return; }
    awk -F'\t' -v rule="$1" '$1 == rule { print $2; found = 1 } END { if (!found) print 0 }' "$RATCHET"
}

failed=0
check() {
    local name=$1 pattern=$2 found count allowed
    found=$(matches "$pattern")
    count=$(printf '%s' "$found" | grep -c . || true)
    allowed=$(allowance "$name")
    if (( count > allowed )); then
        echo "error: $name — $count found, $allowed allowed:" >&2
        echo "$found" >&2
        failed=1
    elif (( count < allowed )); then
        echo "note: $name — $count found, ratchet allows $allowed; lower it in $(basename "$RATCHET")" >&2
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

exit $failed
