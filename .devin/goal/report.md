# Goal report

## Objective
/gauntlet-loop work towards this high quality standard. make sure to commit in phases and work is not finished until all the phases are fully implemented.

Quality bar: Raycast. Plan: `docs/plans/2026-10-11-foundry-raycast-bar-audit.md` (56 findings).

## Progress

### Phase 0 — measurement lab ✅ (commit 9a64ed3)
- Signpost marks/spans for hotkey→panel-front, panel first-frame, keystroke→results, results commit (`DiagnosticsService`, `PanelController`, `CommandPanelState`, `CommandPanelView`)
- `scripts/drive-signposts.swift` extended with latency capture; `docs/benchmarks/2026-10-11-latency-budgets.md`
- `PanelShellTests`, `PanelHideGateTests`, `PanelKeyboardTests` added

### Phase 1 — window model + keyboard ✅ (commit 9a64ed3)
- Dismissal orders the panel out; focus returns to previous app via `AppActivation`; stays active when another Foundry window (onboarding) is visible
- Home never opens blank — cached snapshot + async reconcile
- Keyboard: navigation only traverses rendered rows; Esc clears query before closing and pops feature modes; footer shows the real preferred action; ⌘C/⌘V/⌘⌫ routed correctly through field editor first

### Phase 2 — search quality ✅ (commit 9f64945)
- Single scalar rank: `SearchMatchTier.score` + fuzzy nudge (< tier gap) + bounded usage frecency (< 0.15, can't cross tiers) + favorite nudge
- Flat result list — removed `ResultSection.ordered` re-bucketing that forced apps ahead of commands regardless of match strength
- Strict weak ordering, total tie-breaks — provider return order cannot leak into result order
- Stable-prefix merge: deferred-phase results can't reshuffle the head after the 120ms glance window or user interaction
- File search: in-process `NSMetadataQuery` replaces per-search `mdfind` spawn; results ranked by basename match quality (was raw Spotlight index order); Spotlight-disabled detected by a once-per-launch probe
- Kind labels describe the result kind (Application/File/Snippet/…) not the action verb
- New golden tests: `als` boundary-fuzzy case, weak-app-vs-strong-command, determinism under provider reorder, heavy-usage tier boundary
- Fixed flaky `ConversionGate` test helper (release-before-wait lost wakeup — suite deadlocked twice under load)

### Phase 3 — performance/data ✅ (commit 7778f1c)
- Clipboard poll runs only while the panel is open (`start`/`stop` on resetForOpen/panelWillClose/shutdown); launch does a one-shot capture — kills the 0.7 s runloop wake that ran forever
- ConfettiBurst's 60 fps `TimelineView` pauses while idle (was ticking an empty Canvas for the panel's whole life)
- Clipboard store: incremental diff-write (insert new / update changed pin+position / delete missing via keep-table) replaces the rewrite-every-row save; images live on disk keyed by signature, first 24 eager, rest lazy (`imageData(signature:)`, hydrated via `resolvedPayload`/`selectedItem`); fixed the empty-payload signature hazard; `policy.bounded` O(N²)→O(N)
- Direct paste: 750 ms staged-clipboard hold after ⌘V before restoring — slow targets no longer paste the old clipboard
- Icons: synchronous `cachedImage` seed for FileIcon/RemoteIcon (no placeholder flash), one shared URLSession+URLCache, top-12 results prewarmed, `scaleEffect(1.04)` resample removed
- Config writes: debounced 300 ms background persist (`flush` on terminate and before backup export, `discardPending` on restore); 100 rapid updates → 1 write (`persistedWriteCount`)
- Test speed: clipboard workload 35 s → ~1 s (unique payloads actually exercise bounds now — identical fixtures dedup'd to 1 row); scoring measure 10→3 iterations; OCR fixture 640×160→300×80
- D33 resolved: the `com.apple.dt.xctest` launch lines come from `RecapPerformanceTesting.framework`, loaded by AppKit on macOS 26 — OS behaviour, not Foundry code; no app-side fix exists
- Deferred (documented): FTS5 text index (in-memory filter over ≤1,000 items is cheap), at-rest encryption, thumbnail column, NSPasteboardItem lazy providers

### Phase 4.7 — readability (partial, this commit)
- All >240-char lines eliminated across `Sources/`; >300 golfed one-liners reformatted one-statement-per-line (OperationCoordinator, DependencyModels/Provisioning, ExecutableLocator, ProcessRunner, WindowPlacementMetadata, Translation provider/models, clipboard files, AI instruction strings → heredocs)
- `scripts/lint-lines.sh` added — gates Sources at 240 now; ~290 lines remain over the 160 target (ratchet tracked below)

### Phase 4.8 — dev-run safety ✅ (this commit)
- Removed the DEBUG `SMAppService.mainApp.unregister()` — `swift run` no longer unregisters the installed app's login item
- Rebuild+install over /Applications now requires explicit `INSTALL_APP=1`; a plain `swift run` runs the dev binary only

### Bug found via test-env fragility (this commit)
- `PanelController.hide()` ordered the panel out only inside an `NSAnimationContext` completion — in a headless/occluded context the completion never fires and the panel leaks onscreen. Added a 120 ms deadline failsafe (generation-guarded so a show() still wins); PanelShellTests that hung 3 s now pass in 0.3 s

### Phase 4.6 — one persistence model ✅ (this commit)
- `FoundryLocalState` on `FoundryConfig` (additive field, decodes empty from legacy files, no schema bump) absorbs all 20 `UserDefaults` app-state keys: browser, currency quote, login consent, color recents, media folder, snippet export dir, conversion celebration, Firefox prompt, download notice, onboarding step/version, emoji recents/columns/tone, script dirs + trust, calculator history
- `UserDefaultsMigration` — one-shot import in `ConfigService.init`; keys removed as they land. `UserDefaults.standard` appears **once** in `Sources/` (the `legacyDefaults` param)
- `LocalStateStore` facade — `shared` bound to the app's `ConfigService` at launch (`AppDelegate`); unbound stores keep an in-memory snapshot for tests. All consumers migrated: `ScriptDirectoryStore`, `CalculatorHistoryStore`, `EmojiPickerState`, `OnboardingState`, `SnippetState`, `FileConversionState`, `ActionRunner`, `BrowserProvider`, `CalculatorProvider`, `CalculatorViews`, `MediaDownloadDestination`, `DownloadNotice`, `FirefoxConnectorInstaller`, `AppDelegate`, `CommandPanelState`
- `ConfigService.updateLocalState` + `reload()` (post-restore re-read that also clears a stale read-only state)
- Backup restore applies **live** — no more `NSApp.terminate`: reload → re-apply script dirs → `apply(config:)` re-mirrors panel fields → clipboard/snippet/usage/AI-state refresh + hotkey re-registration + preference callbacks. `UsageRankingStore.reload()` + `CommandRegistry.reloadUsage()` + `AISettingsState.reloadFromConfig()` added for that
- Kept deliberately outside the model: `com.apple.symbolichotkeys` suite (macOS system domain), `SourceRootLocator` (DEBUG non-packaged suite)
- New tests: migration import/removal/no-rerun, config-init import, bound vs standalone store, legacy-JSON decode, backup round-trip carries localState inside config.json

### Phase 4.1 — typed `ResultPayload` ✅ (this commit)
- `ResultPayload` enum on `CommandResult` — required init arg so all ~37 construction sites were compiler-enumerated: `.app(identity:)`, `.file(URL)`, `.snippet(id:)`, `.calculation/.calculationConversion(expr:value:)`, `.calculatorFallback`, `.quicklink(id:)`, `.script(path:)`, `.url(URL)`, `.note(id:)`, `.aiPrompt`, `.command`. `id` remains a stable string key for ranking/favorites.
- Every `result.id.hasPrefix("file."/"snippet."/"calculator."/"quicklink."/"app."/"foundry.quick.")` dispatch + every `id.dropFirst` decode migrated to payload switches: kind labels, ResultSections bucketing, quicklink partition, meta-action gating, promotion filter, Open-With/Quick Look/drag-provider path decode, home-suggestion bundle id.
- `openCommandSettings(commandID:)` → `openCommandSettings(SettingsDeepLink)`; `pendingSettingsCommandID` → typed `pendingSettingsDeepLink` — Settings pane routing no longer re-parses prefixes.
- Calculator history record reads `payload.calculationExpression` — kills the subtitle `" · "` split (which also silently broke on expressions containing " · ").
- `clipboard.`/`systemPane` cases omitted: nothing mints them (dead exclusion) — noted, not cargo.
- Caught by suite: promotion lookup must read `results` not `selectedResult` (the latter resolves via `navigableResults` → cycle → stack overflow). Fixed via `selectedPromotedCalculatorResult`.
- Gate: build clean, 631/0, lint PASS. Fixture helpers gained `payload:` params (default `.command`).

### Phase 4.2 — feature-owned `ResultAction` ✅ (this commit)
- `CommandActionKind` (68 cases) deleted; `CommandAction.behavior: any ResultAction` replaces `kind`. `ResultAction` carries `icon`, `shortcut`, `style` (.normal/.destructive), `hidesPanelForHotkey`, `resultSection`, `@MainActor perform(_ ctx:) async -> CommandOutcome`.
- `ActionContext` (class, implicitly Sendable) holds every former runner dependency + `emit`, `invocation`, and `PanelPorts` (toggleFavorite / presentSettings / presentMediaDownloads / celebrate / onQuickLook) — wired by `CommandPanelState` at init. State's `toggleFavorite`/`openCommandSettings`/`downloadMedia`/`celebrate` intercepts are gone; the actions own that behaviour.
- `ActionRunner.swift`: **1551 → 136 lines** — init, `execute` task tracking + cancellation, `perform` = confirmation policy + context build + `behavior.perform`. All feature logic moved to feature folders: `App/AppActions`, `Clipboard/ClipboardActions`, `Files/FileActions`, `Snippets/SnippetActions`, `Quicklinks/QuicklinkActions`, `Media/MediaActions`, `Commands/Execution/PanelActions` (routes + meta), `Images/ImageActions` (OCR/color/QR + `TextPreview` entry points), `System/SystemActions` (+ KeepAwake/AudioDeviceController), `Scripts/ScriptActions`, `WindowManagement/WindowActions`.
- UI dispatch eliminated: icon switch → `behavior.icon`; destructive → `behavior.style`; section bucketing → `behavior.resultSection`; tile-window checks → `as? TileWindowAction`; app detection → `.app` payload; hotkey-hide → `hidesPanelForHotkey`. Adding a command now touches only its feature folder.
- All actions `Equatable` (members are Hashable) — tests assert `behavior as? XAction`.
- Collateral cleanup: `runner.onQuickLook` → `panel.onQuickLook` port; `extractTextPreview`/`decodeBarcodePreview`/`shareFile(at:)` moved to `TextPreview`/free funcs.
- Gate: build clean 0 warnings, 631/0, lint PASS.

### Phase 4.3 — `CommandPanelState` split ✅ (this commit)
- 1,283-line god object → `CommandPanelState` (296) + focused collaborators: `PanelSession` (474 — query/results/selection/actions-overlay), `PanelRouter` (233 — mode stack + `open*` navigation), `SettingsStore` (457 — all config-backed settings, `ConfigService`-wrapped), `ShellPort` (23 — replaces the 15 `on*` closures; `ShellController` conforms), `PanelFeature` (178 — `handleModeShortcut`/`handleMove`/`pasteText` adopted by 7 feature states)
- Extensions keep the panel a thin coordinator: `+Lifecycle` (reset/shutdown), `+Input` (⌘-shortcuts/⌘V/arrows dispatch through `feature(for:)`), `+Drop` (drop choice flow), `+Paste` (direct-paste/snippet/Vision), `+Media` (downloads), `+Settings` (restore mirror)
- `performModeShortcut`, `pasteFromClipboard`, `moveSelection` per-mode `if` chains → `feature(for: mode)` dispatch; search-mode exceptions (⌘Y Quick Look, ⌘+digit action shortcuts) stay at the dispatch layer
- Delayed agent socket start deleted — `agents.start()` runs from `resetForOpen` only when `settings.isAgentShelfVisible`, and `AgentMonitorState.start()` already owns `startSocket()`
- `UI/` files >500 lines are views (`CommandPanelView`, `FileConversionView`, `WindowLayoutPicker`, `MediaDownloadsView`, `SnippetsView`, `HomeAccessoryStrip`) + `FileConversionState` (596, pre-existing) — all Phase-5 split scope
- ~90 call sites retargeted (`state.session.*`, `state.settings.*`, `state.router.*`); two perl-migration corruptions recovered line-by-line (literal `$1`/`$2`, feature-state receivers misrouted); tests retargeted + `RecordingShellPort` helper added

### Phase 5.1 — design tokens ✅ (this commit)
- `FoundryTheme` rebuilt as the whole vocabulary: six-style text ramp (title 20/reg, body 13/med, bodySecondary 13/reg, caption 11/med, micro 11/semibold, mono 12 mono), `Glyph` scale + computed `glyph(_:)` for SF Symbols/emoji, semantic colours (textPrimary…Quaternary, fillSubtle/Hover/Tint/Selected/Emphasis, separator, stroke, destructive/success/warning/accent + accent tints, scrim/scrimStrong/shadow, onDark*, `dark(_:)/light(_:)/primary(_:)` computed-alpha helpers, `Alpha` named constants), spacing 4/8/12/16/24, radii 6/8/10/14/26, brand + confetti palette, `AgentSessionStatus.color` (dedupes two identical status switches)
- ~560 call sites migrated: `FoundryTheme.body/display/mono(size:weight:)` → ramp tokens by (size,weight,context); raw `.system(size:)` → ramp or `Glyph` by Image/Text receiver; `.primary.opacity(0.x)` → semantic bucket (15 ad-hoc values → 8 tuned fills); `.black/.white.opacity` → scrim/shadow/onDark; `Color(red:` → tokens incl. status palette
- `pointerCursor()` + every `NSCursor.*.set()` deleted (20 files)
- New gate `scripts/lint-design.sh`: fails on `.system(size:` / `Color(red:` / `opacity(0.` outside `FoundryTheme.swift` — passes
- Distinct text sizes: 6 (was 28). Manual fix-ups: ternary/computed sizes → `glyph(_:)`, `Alpha.half`, token ternaries

### Phase 4.5 — `@unchecked Sendable` audit ✅ (this commit)
- ~60 sites → **3 justified** (target ≤10). Compiler-driven method per handoff: flip to `Sendable`, let the compiler enumerate violations, consolidate mutable state into `OSAllocatedUnfairLock<State>`.
- `init(initialState:)` requires `State: Sendable`; SDK/non-Sendable state (`VNRequest`, `OpaquePointer` db handle, `CheckedContinuation`, `DispatchWorkItem`, `URLSession*` types, `NSColorSampler`, `NSObjectProtocol` observer, `ISO8601DateFormatter`) uses `init(uncheckedState:)` + `withLockUnchecked` — the lock still vouches, just not the type system.
- Conversions: all lock-guarded classes in FoundryServices (ProcessRunner helpers, OperationCoordinator, ProgressCollector, ArtifactStore/Reservations, KeepAwakeProcessOwner, ContinuationGate), Commands layer (scheduler/race, usage store, installed-app cache), config (`ConfigService`, `LocalStateStore`), feature caches/stores (snippets, calculator, currency, quicklinks, notes, scripts, shortcuts, browser caches, metrics sampler, agents monitor/socket, camera capture, OAuth callback server, keychain store, AI chat store/writer, clipboard SQLite store, media service/delegates/parser/throttle, running-apps snapshot, icon box, developer-tools formatter, window-manager observer)
- `SnippetExpansionService` → `@MainActor` (state was already main-confined; event tap callback crosses via `assumeIsolated` — `CGEvent` isn't Sendable so the hop collapses the result to `Bool` and rebuilds `Unmanaged.passUnretained` outside)
- `NativeWindowManager` observer + `deinit` now lock-boxed (replaces `nonisolated(unsafe)` var)
- 3 kept with justification: `AgentTool` (immutable `[String: Any]` JSON schema), `NSImage`/`FileManager` retroactive SDK backports
- All 18 test fakes converted the same way (`Sendable` + lock boxes / computed shims where tests mutate fakes)
- `nonisolated(unsafe)` locals: 3 remain, all commented (event-tap event, translation session, export session)

### Phase 4.6b — failure visibility (`try?` audit) ✅ (this commit)
- `try?` in `Sources/`: **204 → 78** (plus 6 inside the helper itself). Every remaining site classified intentional: ~40 cleanup (`removeItem`/`close()`/ROLLBACK), ~12 `Task.sleep` cancellation, ~22 Codable/JSON shape probes over external or protocol data, ~4 binary-capability / reachability probes
- New `BestEffort` in FoundryServices — `attempt(_:_:)` (sync + `@Sendable` async) keeps `try?` fallback semantics but logs failures at `.error`; `log(_:_:)` for catch sites that can't use it (non-Sendable captures). ~120 load/probe sites converted so corrupt user data is diagnosable instead of silently defaulting
- Non-throwing probe helpers: `URL.fileResourceValues`, `FileManager.attributesIfPresent`, `contentsOfDirectoryIfPresent` (URL + path variants) for scan-frequency attribute/existence checks
- Real behavior fixes found by the audit:
  - QR PNG save failure now alerts instead of silently no-oping (`ActionRunner`)
  - Corrupt `codex.json` no longer treated as empty and clobbered on write — `AgentIntegrationInstaller` now throws
  - Ollama request-body encode failure returns a real config error instead of sending an empty body (`AIAgentRuntime`)
  - `killall cfprefsd` prefs-flush failure logged (`OnboardingState`)
- Swift 6 notes: async `attempt` takes `@Sendable` closures; sites capturing `var`s use `[capture]` lists; `NSItemProvider` site uses explicit `do/catch` + `BestEffort.log`

### Verification evidence
- `swift build`: clean, 0 warnings
- `swift test`: 631 tests, 0 failures, 5 skipped (~57 s; FOUNDRY_SLOW_TESTS-gated Vision cases skipped; CoreData/contactsd noise is environmental)
- Focused: 143 tests across persistence/config/backup/onboarding/scripts pass
- `scripts/lint-lines.sh`: PASS
- `UserDefaults.standard` in `Sources/`: 1 site (ConfigService migration param)

### Workstream transferred (this commit)
- Full handoff to the Mac mini agent: repo cloned clean to `~/Honey/anvil` at `cea3608` and verified `swift build` on its Xcode 16.3 / Swift 6.1 toolchain. Handoff brief at `~/foundry-raycast-audit-handoff.md` (mini home dir); `docs/HANDOFF.md` (`61a3918`) repointed to this audit. The mini agent owns all remaining phases and the final sync-back of commits to this checkout.
- `cea3608` also restored Swift 6.1 compatibility broken by the try? audit: `import FoundryServices` hoisted out of `#if canImport(FoundationModels)` (OnboardingState), `@preconcurrency import Foundation` for `NSItemProvider.loadItem` (FileConversionView), and `SendableBackports.swift` — `NSImage: @retroactive @unchecked Sendable` under `#if compiler(<6.2)`. 95 errors on Xcode 16.3 → build complete.

## Remaining (owned by the Mac mini agent — see `~/foundry-raycast-audit-handoff.md` there)
- Phase 4: @unchecked Sendable audit (7 done in `31d6760`; ~53 sites → ≤10 justified), typed `ResultPayload` (79 prefix-check sites), `ResultAction` + ActionRunner generic executor, CommandPanelState split (~70 props), lint ratchet 240→160
- Phase 5: UI/UX — design tokens, row anatomy, alerts→in-panel forms, Settings window, Quick Look, materials/motion, copy, localization groundwork, accessibility
- Phase 6: platform — window tiling settle, Codex OAuth opt-in, CI snapshots
- Final: benchmark evidence, HANDOFF + report update, goalctl done

## Manual-only / environment-gated
- Accessibility-gated keystroke benchmarks, VoiceOver walkthrough, Liquid Glass cost check, notarization — documented in `docs/HANDOFF.md`, not falsely claimed
- Idle CPU/memory measured via `ps` (7–8% CPU, ~364 MB peak during audit)
