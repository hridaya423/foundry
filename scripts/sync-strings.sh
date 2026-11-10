#!/usr/bin/env bash
# Adds every string the compiler extracts from the Foundry target to
# Localizable.xcstrings, and marks keys the source no longer uses as stale.
# SwiftPM builds skip the extraction Xcode does, so run this after adding
# user-facing text.
#
# Usage: scripts/sync-strings.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

swift build --package-path "$ROOT" --product Foundry --scratch-path "$WORK/build" \
    -Xswiftc -emit-localized-strings -Xswiftc -emit-localized-strings-path -Xswiftc "$WORK/strings" >/dev/null

args=()
while IFS= read -r file; do args+=(--stringsdata "$file"); done \
    < <(find "$WORK/build" -path '*/Foundry.build/*' -name '*.stringsdata')
xcrun xcstringstool sync "$ROOT/Sources/Foundry/Resources/Localizable.xcstrings" "${args[@]}"
