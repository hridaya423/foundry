#!/usr/bin/env bash
# The local gate: every lint script, a Swift build that includes the tests, and
# the website checks. It does not run `swift test`: the suite binds Foundry's
# agent socket and registers global hotkeys, so run filtered classes instead.
#
# Usage: scripts/check.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

for lint in "$ROOT"/scripts/lint-*.sh; do
    "$lint"
done

(cd "$ROOT" && swift build --build-tests)

(
    cd "$ROOT/anvil"
    npx tsc --noEmit
    npx eslint .
    npm test
    npx next build
)

echo "All checks passed."
