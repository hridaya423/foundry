#!/usr/bin/env bash
# Fails when design literals escape FoundryTheme — every font size, colour and
# opacity must come from the token file so the UI stays one vocabulary.
#
# Usage: scripts/lint-design.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
THEME="$ROOT/Sources/Foundry/UI/FoundryTheme.swift"

violations=$(find "$ROOT/Sources" -name '*.swift' ! -path "$THEME" -print0 \
    | xargs -0 grep -nHE '\.system\(size:|Color\(red:|opacity\(0\.' \
    | grep -v 'NSColor(red:' \
    || true)

if [[ -n $violations ]]; then
    echo "error: design literals outside FoundryTheme.swift:" >&2
    echo "$violations" >&2
    exit 1
fi
