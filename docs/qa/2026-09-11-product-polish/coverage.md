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

## Package 1 remainder (shared navigation)

| Item | Change | Status |
| --- | --- | --- |
| P13 header alignment | Fixed-title header branches now pin to the leading edge next to Back (`headerUsesFixedTitle` + trailing spacer); search/field modes unchanged | Code fixed; **visual pass unverified** (no screen recording permission) |
| ⌘K outside search | `toggleActions` now requires `.search` mode — previously it could arm an invisible action list over a feature surface after `executeCommand`-style stale results | `testCommandKDoesNotArmActionsOutsideSearchMode` passed |
| Return outside search | `executeSelectedResult` now requires `.search` mode — stale results could execute in `.agents` | `testExecuteSelectedResultDoesNothingOutsideSearchMode` passed |
| Keyboard matrix (Enter/Escape/Tab/arrows/⌘K/⌘,) | Source-verified paths: Escape → `handleEscape` → `backToSearch`; arrows → `moveSelection` per-mode; Tab/Return → `LauncherSearchField`; ⌘K/⌘,/⌘V/⌘Q → `FoundryPanel.handleShortcut` | Source-verified; live pass unverified |
| Icon hit areas/accessibility | `FoundryIconButton` uses 30pt frames with accessibility labels and tooltips | Source-verified |

## Package 4 remainder (dev tools, calculator, translation)

| Item | Change | Status |
| --- | --- | --- |
| Base64 whitespace preservation | Already fixed pre-session; `testBase64ToolPreservesWhitespaceWhenEncoding` present | Passed |
| Calculator | New `CalculatorTests` — precedence, parens, implicit multiply, `%` postfix vs modulo, power/factorial/functions, `=`/`calc` prefixes, scientific notation, equation solving, unit conversions, copy action, malformed/non-finite/div-zero → no results | 11 tests passed; live pass unverified |
| Currency conversion | Live Frankfurter fetch; cache exists (5-min TTL) | **Unverified** (network-dependent; intentionally untested hermetically) |
| Translation races | `finish` guards on `activeRequest.id` + cancellation; `testStaleResponseCannotReplaceNewerRequest` exists | Passed |
| Copy feedback | Root-search copies already toast via `ActionFeedback`. Added: translator copy button shows accent checkmark 1.2s (`didCopy`); dev-tools copy buttons show checkmark via `lastCopiedValue` | Compiles; visual pass unverified |

## Package 5 (files, conversion, image tools)

| Item | Change | Status |
| --- | --- | --- |
| Shelf add/dedup/selection | Existing `BackgroundRemovalTests` cover batch add, duplicates, rejected URLs, toggle/range selection, multi-file processing, cancel, source preservation | Passed (15 tests) |
| Conversion targets/cancel/retry | Existing `FileConversionTests` cover common-target gating, provisioning fingerprint, cancel vs late completion, retry aggregation | Passed (12 tests) |
| Artifact safety | `ArtifactStoreTests` — staging, collision no-overwrite, reservation lifecycle | Passed (6 tests) |
| Dependency setup copy | Sheet reworked: readable tool-name sentence + disclosure as primary copy; commands/scope/cleanup moved into a "Command details" disclosure group | Compiles; visual pass unverified |
| Live drag/drop + chooser | — | **Unverified** (no desktop automation) |

## Package 6 (AI, agents, integrations, Settings)

| Item | Change | Status |
| --- | --- | --- |
| AI/agents/browser/camera/settings suites | `AIProviderTests`, `AIChatStoreTests`, `AgentMonitorTests`, `AgentIntegrationTests`, `BrowserProviderTests`, `CameraPreviewTests`, `ConfigServiceTests` | 131 tests passed; live integrations unverified |
| QuickAI failed prompts | Preserved in `quickAILastFailedPrompt` with retry; stale streams guarded by requestID | Source-verified |
| Notes unavailable vs empty | `AppleNotesProvider` now returns an unavailable row ("Couldn't search Apple Notes", Automation permission hint, Open Notes + Open Automation Settings actions) when osascript fails, instead of silent empty | 3 new tests passed |
| Browser tabs | Degrades to history/bookmarks on tab-fetch failure; not conflated with empty since records still render | Source-verified, unchanged |
| Widget staleness | `WeatherSnapshot`/`StockSnapshot` carry `fetchedAt`; stale (>15m) widgets show "Updated HH:mm" instead of condition caption; a11y value includes the update time | Compiles; visual pass unverified |

## Package 7 (final sweep)

| Item | Change | Status |
| --- | --- | --- |
| Emoji picker | Whitespace-only query no longer shows a "Results" header over the full catalog; an empty Pinned section no longer renders a false "No matching emoji" | Compiles; visual pass unverified |
| Window/system/app-search suites | `WindowLayoutEngineTests` (24), `WindowManagementProviderTests` (7), `WindowManagerTests` (19), `AppSearchProviderTests`, `SystemCommandProviderTests` | Passed |
| Full suite | `swift test` | **488 passed, 0 failures** |
| Build + packaging | `build-app.sh` + `verify-packaging.sh` | Passed; app launches without crash (PID confirmed) |
| `git diff --check` | — | Clean |
| Daily-use live sequence | open → search → clipboard → snippet → download → convert → dev tool → AI → settings | **Unverified** — no screen-recording or accessibility permission this session; app launches but panel could not be driven or captured |
