#!/usr/bin/env bash
# Fails when design literals escape FoundryTheme — every font size, colour,
# opacity, radius and duration must come from the token file so the UI stays
# one vocabulary.
#
# Usage: scripts/lint-design.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

ALLOWED='ImageActions\.swift:[0-9]+:.*String\(format: "NSColor\(red: %'

matches() {
    local out rc=0
    out=$(grep -rnHE --include='*.swift' --exclude='FoundryTheme.swift' "$1" "$ROOT/Sources") || rc=$?
    if (( rc > 1 )); then
        echo "error: grep failed with status $rc" >&2
        exit 2
    fi
    printf '%s\n' "$out" | grep -vE "$ALLOWED" || true
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
