#!/usr/bin/env bash
# Fails when any Swift source line exceeds the configured character cap.
#
# Usage: scripts/lint-lines.sh [--max N] [--tests]
#   --max N   Line-length cap (default 160)
#   --tests   Also scan Tests/ (default is Sources/ only)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MAX=160
INCLUDE_TESTS=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --max) MAX="$2"; shift 2 ;;
        --tests) INCLUDE_TESTS=1; shift ;;
        *) echo "unknown argument: $1" >&2; exit 2 ;;
    esac
done

dirs=("$ROOT/Sources")
if [[ $INCLUDE_TESTS -eq 1 ]]; then
    dirs+=("$ROOT/Tests")
fi

violations=$(find "${dirs[@]}" -name '*.swift' -print0 \
    | xargs -0 awk -v max="$MAX" 'length($0) > max { printf "%s:%d: %d chars\n", FILENAME, FNR, length($0) }' \
    | sort)

if [[ -n $violations ]]; then
    echo "error: Swift source lines over $MAX characters:" >&2
    echo "$violations" >&2
    exit 1
fi
