#!/usr/bin/env bash
# Keeps every user-facing string on the localizable path: SwiftUI literals
# (Text/Button/help/accessibilityLabel) already resolve through
# LocalizedStringKey + Localizable.xcstrings, so the banned patterns are the
# escape hatches that skip the catalog — Text(verbatim:), legacy
# NSLocalizedString, and raw literals handed to AppKit titles, which are
# String-typed and must go through String(localized:).
#
# Usage: scripts/lint-l10n.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

violations=$(find "$ROOT/Sources" -name '*.swift' -print0 \
    | xargs -0 grep -nHE 'Text\(verbatim:|NSLocalizedString\(|NSMenu\(title: "|withTitle: "|accessibilityDescription: "|\.messageText = "|\.informativeText = "|NSAlert\(|feedback: \.(info|success|failure)\("|\.(success|failure|stayOpen|refreshResults|denied)\(message: "|showActionFeedback\(\.(info|success|failure)\("|\b\w*(Status|Error|Message|status|error|message)\s*=\s*"[^"]' \
    || true)

if [[ -n $violations ]]; then
    echo "error: unlocalizable user-facing strings (use String(localized:) or a LocalizedStringKey init):" >&2
    echo "$violations" >&2
    exit 1
fi
