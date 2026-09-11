# Foundry product-polish coverage — 2026-09-11

Status: in progress. Continues the 2026-09-05 pass. Records what was actually verified; unchecked items are not implied to work.

## Environment

- Build: staged `build/Foundry.app` via `./scripts/build-app.sh` (release, signed, packaging verification passed).
- Tests: `swift test` — 472 passed, 0 failures. Focused `swift test --filter TimeConversionTests` — 20 passed.
- Desktop automation: unavailable this session; live UI behavior is marked unverified where applicable.

## Timezone conversion (new surface)

Natural-language time queries from root search. Provider: `TimeConversionProvider` (immediate tier), engine `TimeConversionEngine` (injected `now`/local zone, deterministic), resolver `TimeZoneResolver` (curated abbrev/city table + IANA city fallback; never `TimeZone(abbreviation:)` for lookup).

| Query shape | Verified by | Status |
| --- | --- | --- |
| `now` (local + UTC + unix rows) | `testNowReturnsLocalUTCAndUnixRows` | Passed |
| `now in sf` / `now in tokyo` | `testNowInSanFranciscoAlias`, `testNowInTokyo` | Passed; labels show real in-effect abbrev (PDT, JST) and offset-vs-local |
| `what time is it in berlin` | `testWhatTimeIsItInBerlin` | Passed |
| `12pm est` (implicit targets: local + UTC) | `testConversionToLocalAndUTC`, `testConversionToOtherLocalZone` | Passed; local target adapts to injected zone |
| `12pm est to pst and ist` (multi-target) | `testExplicitMultiTarget` | Passed |
| Unresolvable targets skipped / all-unresolvable → no results | `testExplicitTargetsSkipUnresolvableZones`, `testAllUnresolvableTargetsReturnNothing` | Passed |
| 24-hour input `15:30 london` | `testTwentyFourHourInput` | Passed |
| `noon` / `midnight` | `testNoonAndMidnight` | Passed |
| `tomorrow` / `yesterday` / weekday modifiers | `testTomorrowModifier`, `testYesterdayModifier`, `testWeekdayModifierPicksNextOccurrenceInSourceZone` | Passed; weekday picks next occurrence in source zone |
| DST: US-forward/Europe-not gap (4h on 2026-03-20) | `testUSForwardEuropeNotGapIsFourHours` | Passed |
| DST: nonexistent wall time on spring-forward | `testSpringForwardNonexistentWallTimeStillResolves` | Passed (`.nextTime` skips gap) |
| Honest winter abbrev (`nyc` → EST not EDT in January) | `testWinterAbbreviationIsHonest` | Passed |
| Non-time queries return nothing | `testNonTimeQueriesReturnNothing` | Passed |
| Provider: copyable results, `isActive` gating | `testProviderProducesCopyableResults` | Passed |
| Live typing in the launcher UI | — | **Unverified** (no desktop automation; needs manual pass) |

## Notes

- Uncurated IANA city lookups fall back to `GMT±N` abbreviations — honest, if less friendly.
- Source zone defaults to `TimeZone.current` (system timezone) at runtime; tests inject zones.
