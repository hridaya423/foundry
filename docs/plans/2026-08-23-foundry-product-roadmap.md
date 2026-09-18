# Foundry Product Roadmap Implementation Plan

> **Superseded** by `docs/plans/2026-09-25-foundry-premium-plan.md` where they overlap (P4 core parity replaces the phase order below).

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Turn Foundry into a dependable native macOS launcher whose search, file, clipboard, snippet, browser, AI, and coding-agent workflows are fast enough for daily use.

**Architecture:** Keep `CommandRegistry` as the root-search composition boundary and add product capability through focused `CommandProvider` slices. Use native macOS services before custom infrastructure, keep local data local, and reuse `CommandAction` so every searchable item supports the same keyboard-first action flow. Do not start a later phase until the current phase passes its exit gate.

**Tech Stack:** Swift 6.2, SwiftUI, AppKit, Foundation, Core Spotlight or `NSMetadataQuery`, XCTest, Swift Package Manager, macOS 14 or later.

---

## Decision

Foundry will stop expanding its utility inventory until its launcher core is dependable. The next product milestone is **Find anything, act instantly**, led by native file search and a complete shared action flow.

The roadmap follows this order:

1. Stabilize the current product and establish release gates.
2. Ship file search and repair the shared search-and-actions loop.
3. Deepen clipboard, snippets, browser search, and Apple Notes.
4. Add Quicklinks and Script Commands as the first user-extensibility layer.
5. Turn coding-agent observation into an actionable command center.
6. Decide whether a third-party extension runtime has earned its cost.

Do not work on calendar, contacts, reminders, tasks, alarms, Launchpad, dictation, OCR, phone integration, new widgets, new media utilities, or additional AI providers before Phase 4 exits.

## Product position

Foundry is a native, local-first macOS launcher for people who want system tools, private AI, and coding-agent workflows in one keyboard-driven surface. It should not compete with Raycast by reproducing every extension internally. It should not compete with Tinycast only on binary size. It should make common Mac actions dependable, then use local AI and coding-agent control as its reason to switch.

## Product principles

- Search is the product. A feature that cannot be found and acted on from the keyboard is unfinished.
- Native services come first. Use Spotlight metadata for files, EventKit only if calendar work is later approved, and AppKit behavior where SwiftUI does not provide enough control.
- Local data stays local by default. Network use must be visible and tied to a feature that needs it.
- One result model and one action grammar serve apps, files, notes, browser records, snippets, and extensions.
- New capabilities must pass a manual end-to-end sweep, not only unit tests.
- A phase adds no speculative compatibility layer for later phases.
- A new dependency must remove more product or maintenance risk than it adds.

## Current baseline

The baseline on 2026-08-23 includes:

- Native app and command search.
- Immediate and deferred provider scheduling.
- Search scoring, usage ranking, aliases, favorites, and per-command hotkeys.
- Clipboard history for text, images, and files.
- Snippets with keyword expansion and Raycast import.
- Browser tabs, history, and bookmarks.
- Apple Notes search behind an explicit prefix.
- Window management, system commands, widgets, media downloads, file conversion, developer tools, and camera preview.
- AI provider profiles, local models, provider fallback, web search, and Keychain credentials.
- Coding-agent session observation and provider bridges.
- A 14 MB packaged app, about 32,000 lines of Swift source, and about 6,600 lines of tests.

Known product gaps:

- Root search has no file-search provider.
- Notes and most browser records require a prefix instead of participating naturally in root search.
- Clipboard retention is capped at 40 items and 16 MB.
- The `Command-K` action surface is not searchable.
- Foundry has no Quicklinks, Script Commands, or extension runtime.
- Packaging supports code signing checks, but the repository has no complete notarized release, update, or migration flow.
- Performance tests run workloads but do not enforce latency or memory budgets.

## Roadmap rules

Each phase follows the same delivery loop:

1. Write a feature-level implementation plan in `docs/plans/` before changing product code.
2. Add a failing test at the stable domain or use-case boundary.
3. Implement the smallest complete vertical slice.
4. Run the focused tests after each slice.
5. Run `swift test` before each phase exit.
6. Build and verify the packaged app with `./scripts/build-app.sh` and `./scripts/verify-packaging.sh` when packaging or runtime composition changes.
7. Run the phase's manual acceptance sweep in the packaged app.
8. Commit each independently passing slice. Do not combine unrelated features in one commit.

Targets below are release gates, not estimates. Measure them on the oldest supported representative Mac before treating them as final. If a target is unrealistic on that hardware, record the measured baseline and approve a replacement before implementation continues.

---

## Phase 0: Stabilize and measure

**Outcome:** Foundry has a known-good baseline, repeatable release checks, and no active regression hidden by feature work.

### Task 0.1: Finish the current stabilization work

**Files:**

- Modify only the files already changed by the active search, ranking, clipboard, AI, browser, calculator, media, and UI stabilization work.
- Test the matching files under `Tests/FoundryTests/`.

**Steps:**

1. Review the active diff by subsystem and separate unrelated behavior changes.
2. Run the focused test files for each subsystem.
3. Fix failures at the shared boundary rather than in individual callers.
4. Run `swift test`.
5. Build the packaged app with `./scripts/build-app.sh`.
6. Run `./scripts/verify-packaging.sh`.
7. Commit stabilization separately from roadmap feature work.

### Task 0.2: Establish performance baselines

**Files:**

- Modify: `Tests/FoundryTests/PerformanceRegressionTests.swift`
- Modify: `Sources/FoundryServices/DiagnosticsService.swift` if existing spans cannot expose the required intervals.
- Modify: `Sources/Foundry/Shell/PanelController.swift` only if panel-open timing cannot be measured at the existing boundary.
- Modify: `Sources/Foundry/Commands/Search/CommandSearchCoordinator.swift` only if query-generation timing is missing.

**Measure:**

- Cold app launch to ready.
- Warm hotkey press to first panel frame.
- Keystroke to immediate results.
- Keystroke to complete results.
- Idle resident memory.
- Resident memory after opening and closing every feature surface three times.
- Search cancellation under rapid query replacement.
- Clipboard capture and persistence with the maximum supported archive.

**Provisional targets:**

- Warm panel first frame: p95 at or below 100 ms.
- Immediate app and command results: p95 at or below 50 ms after a keystroke.
- Complete local results: p95 at or below 250 ms after a keystroke.
- No stale result publication after a newer query starts.
- No ordinary feature change increases idle resident memory by more than 10 percent.

Do not make wall-clock XCTest assertions that fail under normal CI variance. Keep deterministic workload tests in XCTest and record user-perceived timings through existing diagnostic spans or a dedicated benchmark command.

### Task 0.3: Define the release path

**Files:**

- Modify: `scripts/build-app.sh`
- Modify: `scripts/verify-packaging.sh`
- Modify: `README.md`
- Test: `Tests/FoundryTests/ResourcePackagingTests.swift`

**Decisions required before implementation:**

- Stable bundle version source.
- Developer ID signing identity and notarization process.
- Release artifact format.
- Update mechanism and update channel ownership.
- Migration policy for `~/.config/foundry` and `~/.local/share/foundry`.

Use the existing scripts for staging and verification. Do not add an updater framework until the release host, signing process, and update manifest owner are known.

### Phase 0 exit gate

- `swift test` passes.
- Packaging verification passes.
- Search, clipboard, AI, and downloads survive the manual core sweep.
- Performance and memory baselines are recorded.
- The current stabilization diff is merged or otherwise removed from the next phase's scope.
- A clean install and upgrade preserve supported user data.

---

## Phase 1: Find anything, act instantly

**Outcome:** Users can find apps, files, commands, snippets, notes, and browser tabs from one stable root search and use a consistent action surface.

### Task 1.1: Add the file-search domain slice

**Files:**

- Create: `Sources/Foundry/Features/FileSearch/FileSearchModels.swift`
- Create: `Sources/Foundry/Features/FileSearch/FileSearchService.swift`
- Create: `Tests/FoundryTests/FileSearchTests.swift`

**Scope:**

- Parse a query into a trusted file-search request.
- Represent files and folders with a stable identity, display name, path, kind, modification date, and content type.
- Represent configured scopes and ignore rules directly instead of passing raw strings through the feature.
- Return an explicit success, permission failure, unavailable service, or cancelled result.

Use Spotlight metadata through the smallest native API that supports cancellation and scoped queries. Do not build a custom filesystem index.

**Test first:**

- Empty queries do no work.
- A cleared scope list returns no results rather than silently searching the home directory.
- Results outside configured scopes are rejected.
- Hidden and ignored paths follow the configured policy.
- Files and folders remain distinguishable.
- Cancellation prevents publication.

### Task 1.2: Add the file-search provider

**Files:**

- Create: `Sources/Foundry/Features/FileSearch/FileSearchProvider.swift`
- Modify: `Sources/Foundry/Commands/Search/CommandRegistry.swift`
- Modify: `Sources/Foundry/Commands/Search/CommandModels.swift` only if file metadata cannot fit the current result contract.
- Test: `Tests/FoundryTests/CommandSearchCoordinatorTests.swift`
- Test: `Tests/FoundryTests/CommandRankingTests.swift`

**Behavior:**

- Provide a dedicated `Search Files` command.
- Add deferred root-search results after three meaningful query characters when root file search is enabled.
- Limit root results so files cannot drown out exact apps or commands.
- Publish only results from the latest query generation.
- Keep a dedicated file-search surface available when broad exploration is needed.

Do not add a generic provider framework. `CommandProvider` already supplies the required boundary.

### Task 1.3: Add the dedicated file-search surface

**Files:**

- Create: `Sources/Foundry/UI/FileSearchState.swift`
- Create: `Sources/Foundry/UI/FileSearchView.swift`
- Modify: `Sources/Foundry/UI/CommandPanelState.swift`
- Modify: `Sources/Foundry/UI/CommandPanelView.swift`
- Test: `Tests/FoundryTests/CommandPanelStateTests.swift`

**Behavior:**

- Show recent files when the surface opens without a query.
- Search only after meaningful input.
- Preserve keyboard selection while results update.
- Show loading, no-results, permission, and service-failure states.
- Support Quick Look without closing the panel.
- Let users drag a result out of Foundry.

### Task 1.4: Complete file actions

**Files:**

- Modify: `Sources/FoundryDomain/CommandModels.swift`
- Modify: `Sources/Foundry/Commands/Execution/ActionRunner.swift`
- Modify: `Sources/Foundry/UI/ActionFeedbackPresentation.swift`
- Test: `Tests/FoundryTests/ActionRunnerTests.swift`
- Test: `Tests/FoundryTests/CommandContractsTests.swift`

**Actions:**

- Open.
- Quick Look.
- Reveal in Finder.
- Copy the file.
- Copy the path.
- Open With.
- Add to File Shelf.
- Convert with the existing conversion flow.

Defer delete, move, rename, and bulk filesystem mutation. Those actions need separate recovery and conflict designs.

### Task 1.5: Make `Command-K` searchable

**Files:**

- Modify: `Sources/Foundry/UI/CommandPanelState.swift`
- Modify: `Sources/Foundry/UI/CommandPanelView.swift`
- Modify: `Sources/Foundry/UI/PanelRowViews.swift` only for shared row presentation.
- Test: `Tests/FoundryTests/CommandPanelStateTests.swift`

**Behavior:**

- Opening actions preserves the selected result.
- Typing filters actions without changing the root query.
- Arrow keys move action selection.
- Return executes the selected action.
- Escape returns to the same result and query.
- Visible shortcut hints match actual bindings.
- The preferred primary action stays first unless the filter excludes it.

### Task 1.6: Make cached local records participate in root search

**Files:**

- Modify: `Sources/Foundry/Features/Browser/BrowserProvider.swift`
- Modify: `Sources/Foundry/Features/Notes/AppleNotesProvider.swift`
- Modify: `Sources/Foundry/Features/Snippets/LibraryProvider.swift`
- Modify: `Sources/Foundry/Commands/Search/CommandRanker.swift`
- Test: `Tests/FoundryTests/BrowserProviderTests.swift`
- Create: `Tests/FoundryTests/AppleNotesProviderTests.swift`
- Modify: `Tests/FoundryTests/LibraryPersistenceTests.swift`

**Rules:**

- Browser tabs may participate from an in-memory cache.
- Browser bookmarks may participate after their local cache is ready.
- Snippet titles, keywords, and tags may participate directly.
- Apple Notes may participate only after a local cache removes the current multi-second AppleScript call from the query path.
- Browser history remains behind explicit intent until measurements prove that ordinary root search stays quiet and fast.

### Phase 1 manual acceptance sweep

- Search an exact app, a fuzzy app, a command alias, a file, a folder, a snippet, a note, and an open browser tab.
- Type quickly enough to replace at least five in-flight file queries. Only the final query may publish.
- Open `Command-K`, filter actions, execute one, return, and confirm that the root query and selection did not move.
- Quick Look a file, copy its path, add it to File Shelf, then convert it.
- Deny metadata or Full Disk Access where applicable and confirm that Foundry explains how to recover.
- Sleep and wake the Mac, then repeat file and app search without restarting Foundry.

### Phase 1 exit gate

- File search meets the approved latency target.
- Root search ordering is stable under immediate and deferred publication.
- No stale query replaces newer results.
- All file actions report success or a recoverable failure.
- `swift test` and packaging verification pass.
- No deferred feature from the roadmap freeze entered the phase.

---

## Phase 2: Deepen daily-use surfaces

**Outcome:** Clipboard, snippets, browser records, and Notes can replace standalone utilities for ordinary use.

### Task 2.1: Replace the clipboard archive bottleneck

**Files:**

- Modify: `Sources/Foundry/Features/Clipboard/ClipboardHistoryPersistence.swift`
- Modify: `Sources/Foundry/Features/Clipboard/ClipboardHistoryModels.swift`
- Modify: `Sources/Foundry/UI/ClipboardHistoryState.swift`
- Modify: `Sources/Foundry/Configuration/ConfigService.swift`
- Test: `Tests/FoundryTests/ClipboardHistoryTests.swift`

The current implementation rewrites one JSON archive on every mutation. Keep it only if measurements show that it remains safe at the new retention target. If it does not, move metadata to a local SQLite store and large image payloads to separately owned files. Preserve the existing archive through a one-time, idempotent migration.

**Required behavior:**

- Retention by age, item count, and disk budget.
- At least 1,000 text-heavy entries without UI or persistence stalls.
- Pinned entries survive ordinary retention cleanup.
- Password-manager and transient pasteboard records stay excluded.
- Corruption cannot destroy the last known-good archive during migration.

### Task 2.2: Complete clipboard interaction

**Files:**

- Modify: `Sources/Foundry/UI/ClipboardHistoryView.swift`
- Modify: `Sources/Foundry/UI/ClipboardHistoryState.swift`
- Modify: `Sources/Foundry/Shell/DirectPasteService.swift`
- Test: `Tests/FoundryTests/DirectPasteServiceTests.swift`
- Test: `Tests/FoundryTests/ClipboardHistoryTests.swift`

**Behavior:**

- Pin and unpin from the keyboard.
- Filter by text, image, file, link, and color when represented.
- Paste, paste as plain text, copy without pasting, and delete.
- Drag clipboard items out where macOS supports the payload.
- Show full metadata and a useful preview without decoding full-size images in the scrolling path.
- Keep excluded-app and pause controls understandable from the clipboard surface.

### Task 2.3: Finish snippets

**Files:**

- Modify: `Sources/Foundry/Features/Snippets/SnippetRenderer.swift`
- Modify: `Sources/Foundry/Features/Snippets/LibraryPersistence.swift`
- Modify: `Sources/Foundry/Shell/SnippetExpansionService.swift`
- Modify: `Sources/Foundry/UI/SnippetState.swift`
- Modify: `Sources/Foundry/UI/SnippetsView.swift`
- Test: `Tests/FoundryTests/SnippetRendererTests.swift`
- Test: `Tests/FoundryTests/SnippetExpansionServiceTests.swift`

**Behavior:**

- Make insertion distinct from copying. The current Snippets view routes both toolbar actions to `copySelected`.
- Support cursor placement, clipboard, date, and time placeholders consistently.
- Prompt for explicit arguments before insertion.
- Detect duplicate expansion keywords before saving or enabling expansion.
- Import and export Foundry snippets without requiring the Raycast format.
- Keep expansion disabled until the user grants Accessibility access and enables it.

### Task 2.4: Make browser and Notes caching explicit

**Files:**

- Modify: `Sources/Foundry/Features/Browser/BrowserProvider.swift`
- Modify: `Sources/Foundry/Features/Notes/AppleNotesProvider.swift`
- Modify: `Sources/Foundry/Commands/Search/CommandProviderScheduler.swift` only if cache refresh needs an existing provider lifecycle hook.
- Test: `Tests/FoundryTests/BrowserProviderTests.swift`
- Test: `Tests/FoundryTests/AppleNotesProviderTests.swift`

**Behavior:**

- Refresh local caches away from the keystroke path.
- Mark stale data where the user needs to know.
- Keep the previous good cache when refresh fails.
- Avoid repeated Automation prompts.
- Expose browser and Notes actions through the same searchable `Command-K` surface.

### Task 2.5: Add onboarding and permission health

**Files:**

- Create: `Sources/Foundry/UI/OnboardingView.swift`
- Create: `Sources/Foundry/UI/PermissionHealthState.swift`
- Modify: `Sources/Foundry/Application/AppDelegate.swift`
- Modify: `Sources/Foundry/UI/WidgetSettingsView.swift`
- Modify: `Sources/Foundry/Configuration/ConfigService.swift`
- Test: `Tests/FoundryTests/ConfigServiceTests.swift`
- Create: `Tests/FoundryTests/PermissionHealthTests.swift`

Request permissions only when the user enables or invokes the feature that needs them. Explain what each permission enables before macOS shows its prompt. Never ask for camera, Accessibility, Automation, or broader file access at first launch without a user action tied to that feature.

### Phase 2 exit gate

- Clipboard handles the approved retention target without blocking typing or scrolling.
- Snippet insertion, expansion, import, and export pass their manual flows.
- Browser and Notes results no longer perform slow work on each keystroke.
- A clean install reaches a useful launcher before any optional permission is granted.
- Every denied permission has a recovery path.
- `swift test` and packaging verification pass.

---

## Phase 3: User-owned workflows

**Outcome:** Users can add useful commands without waiting for Foundry to ship a built-in integration.

### Task 3.1: Add Quicklinks

**Files:**

- Create: `Sources/Foundry/Features/Quicklinks/QuicklinkModels.swift`
- Create: `Sources/Foundry/Features/Quicklinks/QuicklinkStore.swift`
- Create: `Sources/Foundry/Features/Quicklinks/QuicklinkProvider.swift`
- Create: `Sources/Foundry/UI/QuicklinksView.swift`
- Modify: `Sources/Foundry/Commands/Search/CommandRegistry.swift`
- Modify: `Sources/Foundry/UI/CommandPanelState.swift`
- Modify: `Sources/Foundry/UI/CommandPanelView.swift`
- Test: `Tests/FoundryTests/QuicklinkTests.swift`

**Initial scope:**

- Named URL, file, or folder destinations.
- Optional query arguments in URL templates.
- Optional selected-text input after the user grants Accessibility access.
- Per-item aliases, favorites, and global hotkeys through existing command preferences.
- Create, edit, duplicate, delete, import, and export.

Do not add team sharing or cloud sync.

### Task 3.2: Add Script Commands

**Files:**

- Create: `Sources/Foundry/Features/Scripts/ScriptCommandModels.swift`
- Create: `Sources/Foundry/Features/Scripts/ScriptCommandParser.swift`
- Create: `Sources/Foundry/Features/Scripts/ScriptCommandProvider.swift`
- Create: `Sources/Foundry/UI/ScriptCommandOutputView.swift`
- Modify: `Sources/Foundry/Commands/Search/CommandRegistry.swift`
- Modify: `Sources/Foundry/Commands/Execution/ActionRunner.swift`
- Test: `Tests/FoundryTests/ScriptCommandTests.swift`
- Test: `Tests/FoundryTests/ActionRunnerTests.swift`

**Initial scope:**

- Scan user-configured directories for executable text files.
- Parse a small documented directive set for title, description, arguments, timeout, and output mode.
- Support silent, copied-output, notification, and full-output modes.
- Stream bounded output into a native Foundry surface.
- Require confirmation for imported executable commands until the user trusts their directory.
- Use `ProcessRunner` for execution, cancellation, timeout, and output limits.

Prefer compatibility with the simplest Raycast and Vicinae script directives where their semantics match Foundry. Do not preserve incompatible behavior behind translation layers.

### Phase 3 exit gate

- A user can create a Quicklink and a Script Command without editing Foundry source.
- Both appear in root search and use aliases, favorites, hotkeys, ranking, and `Command-K` actions.
- Script execution has bounded runtime and output.
- Imported scripts cannot execute before an explicit trust decision.
- Export and re-import preserve supported user-owned workflows.
- `swift test` and packaging verification pass.

---

## Phase 4: Actionable coding-agent command center

**Outcome:** Foundry moves from observing coding agents to helping users control active sessions from one surface.

### Task 4.1: Define provider capabilities

**Files:**

- Modify: `Sources/Foundry/Features/Agents/AgentSessionIntegration.swift`
- Modify: `Sources/Foundry/Features/Agents/AgentMonitorService.swift`
- Modify: `Sources/Foundry/UI/AgentMonitorState.swift`
- Test: `Tests/FoundryTests/AgentIntegrationTests.swift`
- Test: `Tests/FoundryTests/AgentMonitorTests.swift`

Model observation, open-session, reply, answer-question, approve, deny, cancel, and notification support as explicit capabilities. Do not represent unsupported actions as buttons that fail after selection.

### Task 4.2: Add response channels one provider at a time

**Files:**

- Modify the existing adapter for the first provider that exposes a documented, stable response mechanism.
- Modify: `Sources/Foundry/Features/Agents/AgentEventSocketServer.swift`
- Modify: `Sources/Foundry/UI/AgentShelfView.swift`
- Test the matching provider adapter and integration tests.

Start with one provider. Add a shared response abstraction only after the second provider proves that the semantics are actually shared.

### Task 4.3: Add completion and attention notifications

**Files:**

- Create: `Sources/Foundry/Features/Agents/AgentNotificationService.swift`
- Modify: `Sources/Foundry/UI/AgentMonitorState.swift`
- Modify: `Sources/Foundry/UI/AgentShelfView.swift`
- Test: `Tests/FoundryTests/AgentMonitorTests.swift`

Notify only for transitions that need attention: completion, failure, permission request, or user question. Deduplicate repeated provider events and route notification actions back to the exact session.

### Task 4.4: Add agent session search and actions

**Files:**

- Create: `Sources/Foundry/Features/Agents/AgentCommandProvider.swift`
- Modify: `Sources/Foundry/Commands/Search/CommandRegistry.swift`
- Modify: `Sources/Foundry/UI/AgentShelfView.swift`
- Test: `Tests/FoundryTests/AgentMonitorTests.swift`
- Test: `Tests/FoundryTests/CommandRankingTests.swift`

Active and recent sessions should be searchable by title, provider, repository, and status. Actions must reflect provider capabilities and use the shared `Command-K` flow.

### Phase 4 exit gate

- At least one provider supports a complete observe, notify, open, and respond flow.
- Unsupported provider actions never appear.
- Duplicate events do not create duplicate sessions or notifications.
- Session actions target the correct provider session after restart.
- Sensitive prompts and responses remain local unless the provider itself requires network transport.
- `swift test` and packaging verification pass.

---

## Phase 5: Extension runtime decision gate

**Outcome:** Foundry either commits to a sustainable extension runtime or explicitly stays with Quicklinks and Script Commands.

Do not start by implementing an extension API. First collect evidence from released usage:

- Number of active Quicklinks and Script Commands per user.
- Most requested integrations that scripts cannot serve.
- Demand for existing Raycast extensions.
- Maintenance capacity for runtime compatibility, review, distribution, permissions, and security fixes.
- Product value that cannot be delivered through built-in providers or scripts.

Proceed only if the evidence supports all of these conditions:

- Users repeatedly need interactive list, detail, form, or grid extensions.
- Script Commands cannot provide the required interaction.
- The team can maintain a versioned API and compatibility tests.
- Extension installation and execution have an acceptable trust model.
- The runtime does not compromise the launcher latency and memory budgets.

If the gate passes, write a separate architecture and implementation plan that compares at least two runtime designs. One candidate may use JavaScriptCore with a serialized native view tree. Another may use an out-of-process runtime. Do not select a design in this roadmap.

If the gate fails, invest in richer Script Command output and more built-in provider actions instead.

---

## Phase 6: Reconsider deferred product areas

Only reconsider deferred areas after Phases 0 through 4 pass their exit gates and the extension decision is recorded.

Use this priority test for every proposal:

1. Does the feature solve a frequent launcher task for the target user?
2. Can existing Quicklinks, Script Commands, or extensions solve it?
3. Does it strengthen local AI or coding-agent control?
4. Can the team support its permissions, storage, error recovery, and manual regression matrix?
5. What current capability will receive less work if this ships?

Reject proposals that cannot answer all five questions.

Likely candidates, in order of fit, are calendar meeting actions, selected-text AI commands, on-device dictation, and OCR for clipboard images. This order is not approval to build them.

## Quality gates shared by every phase

### Search

- Exact matches beat fuzzy matches.
- User aliases beat incidental title matches.
- Learned usage can reorder comparable matches but cannot bury an exact match.
- Deferred results do not move the selected row unexpectedly.
- A cancelled query never publishes.
- Empty root search stays useful and quiet.

### Keyboard and focus

- The global hotkey opens and closes the panel.
- Escape backs out one surface before dismissing the panel.
- Arrow keys move the visible selection.
- Return executes the action described in the footer.
- `Command-K` opens actions for the selected result.
- Direct paste returns focus to the originating application.
- Mouse movement does not overwrite keyboard selection unless the pointer actually moves onto another row.

### Persistence

- Writes are atomic or transactional.
- Migration is idempotent.
- A failed write keeps the previous good data.
- Corrupt persisted data produces an actionable error instead of a crash.
- Clean install works with every storage file absent.

### Permissions and privacy

- Foundry asks only after a user enables or invokes the related feature.
- Foundry explains the permission before macOS prompts.
- Denial leaves unrelated launcher functions usable.
- Settings show current permission health and the recovery route.
- Password-manager clipboard entries remain excluded.
- Credentials remain in Keychain.

### Performance

- New root providers meet their search tier deadline.
- Slow IO stays off the main actor and outside the keystroke path.
- Scrolling does not decode full-size media repeatedly.
- Closing a feature releases temporary work and caches that do not serve later searches.
- Each phase records before-and-after latency and memory measurements.

### Release

- `swift test` passes.
- `./scripts/build-app.sh` passes.
- `./scripts/verify-packaging.sh` passes.
- The packaged app passes the phase manual sweep.
- The release notes name user-visible behavior and known limitations.
- Supported persisted data survives upgrade.

## Commit sequence

Use one passing commit for each vertical slice. A typical phase should read like this in history:

1. `test: define file search behavior`
2. `feat: add Spotlight file search`
3. `feat: expose file results in Foundry search`
4. `feat: add file search actions`
5. `feat: make command actions searchable`
6. `test: add file search regression sweep`
7. `docs: document Foundry file search`

Do not commit generated build output or modify unrelated dirty files.

## Research basis

This roadmap uses first-party product pages, documentation, repositories, and release records reviewed on 2026-08-23:

- Raycast product and pricing: <https://www.raycast.com/> and <https://www.raycast.com/pricing>
- Raycast File Search: <https://www.raycast.com/core-features/file-search>
- Raycast Quicklinks: <https://www.raycast.com/core-features/quicklinks>
- Raycast AI: <https://www.raycast.com/core-features/ai>
- Raycast developer documentation: <https://developers.raycast.com/>
- Vicinae repository: <https://github.com/vicinaehq/vicinae>
- Vicinae extensions: <https://docs.vicinae.com/extensions/introduction>
- Vicinae Script Commands: <https://docs.vicinae.com/scripts/getting-started>
- Vicinae File Search: <https://docs.vicinae.com/file-search>
- Tinycast repository: <https://github.com/abue-ammar/tinycast>
- Tinycast contribution quality gates: <https://github.com/abue-ammar/tinycast/blob/main/CONTRIBUTING.md>
- Supermac feature map and changelog: <https://supermac.io/features> and <https://supermac.io/changelog>

## Roadmap completion

The roadmap is complete when Phases 0 through 4 pass their exit gates and Phase 5 records a supported extension-runtime decision. Phase 6 is a new planning cycle, not part of the current commitment.
