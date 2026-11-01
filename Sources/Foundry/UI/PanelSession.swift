import AppKit
import Foundation
import SwiftUI
import FoundryDomain
import FoundryServices

/// The root search surface: query, result list, selection, the actions
/// overlay, favorites, and the immediate→complete result pipeline. Feature
/// modes own their own state — this is `.search` only.
@MainActor
@Observable
final class PanelSession {
    var query = "" {
        didSet { refreshResults() }
    }
    var results: [CommandResult] = [] {
        didSet {
            // Warm the icon cache for the visible head of the list so rows
            // render the real icon on their first frame, not a placeholder.
            let head = results.prefix(12)
            CommandIconRepository.shared.prewarm(
                paths: head.compactMap(\.icon.filePath),
                remoteURLs: head.compactMap(\.icon.remoteIconURL)
            )
        }
    }
    var selectedResultID: String? {
        didSet {
            if selectedResultID != oldValue { onSelectionDidChange?() }
        }
    }
    /// Notifies after the selected row changes — Quick Look follows it.
    @ObservationIgnored var onSelectionDidChange: (() -> Void)?
    private(set) var selectionScrollToken = UUID()
    var isShowingActions = false {
        didSet {
            if isShowingActions { prepareOpenWithActions() }
            else { openWithTask?.cancel(); openWithActions = [] }
        }
    }
    var actionFilter = "" {
        didSet { if isShowingActions { selectedActionID = visibleActions.first?.id } }
    }
    private var openWithActions: [CommandAction] = []
    var openWithTask: Task<Void, Never>?
    var selectedActionID: String?
    var focusToken = UUID()
    var isSearchLoading = false
    /// Immediate-phase head results, so the complete phase can merge under
    /// them instead of reordering rows the user may already be reading.
    private var immediatePrefixIDs: [String] = []
    private var immediateAppliedAt: ContinuousClock.Instant?
    private var selectionAfterImmediate: String?
    var isHomeLoading = false
    var hoverHighlightsArmed = true
    var homeRefreshID = UUID()
    private var searchKeySpan: DiagnosticsService.Span?
    var favoriteResults: [CommandResult] = []
    var isCommandHeld = false
    @ObservationIgnored var announce: (String) -> Void = { message in
        guard NSWorkspace.shared.isVoiceOverEnabled else { return }
        NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
            userInfo: [.announcement: message, .priority: NSAccessibilityPriorityLevel.high.rawValue])
    }
    private(set) var runningAppBundleIDs: Set<String> = []

    let registry: CommandRegistry
    let searchCoordinator: CommandSearchCoordinator
    let configService: ConfigService
    let diagnostics: DiagnosticsService
    /// Composition root — mode (router), the file shelf, and settings the
    /// search pipeline reads through.
    weak var panel: CommandPanelState?

    private var mode: CommandPanelState.Mode { panel?.mode ?? .search }
    private var fileShelf: FileShelfState? { panel?.fileShelf }
    private var commandPreferences: [String: CommandPreference] { panel?.settings.commandPreferences ?? [:] }

    init(registry: CommandRegistry, searchCoordinator: CommandSearchCoordinator, configService: ConfigService, diagnostics: DiagnosticsService) {
        self.registry = registry
        self.searchCoordinator = searchCoordinator
        self.configService = configService
        self.diagnostics = diagnostics
    }

    var selectedResult: CommandResult? {
        navigableResults.first { $0.id == selectedResultID } ?? results.first { $0.id == selectedResultID }
    }

    /// The flat list the view renders in search mode, in render order.
    /// Arrow-key navigation must walk this — never raw `results`, or rows the
    /// view filtered out (non-suggestible apps, hidden window layouts,
    /// suppressed file-shelf entry) steal the selection invisibly.
    var navigableResults: [CommandResult] {
        guard mode == .search else { return [] }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            let sections = homeSections
            return sections.suggestions + sections.commands
        }
        var list = searchListResults
        if selectedPromotedCalculatorResult != nil {
            list += Self.calculatorFallbackResults
        }
        return list
    }

    /// `results` minus rows the view does not paint when a calculator answer
    /// is promoted to its card, or when the shelf holds files.
    var searchListResults: [CommandResult] {
        var list = results
        if let selected = selectedPromotedCalculatorResult {
            list = list.filter { $0.id != selected.id && $0.payload.isCalculatorConversion == false }
        }
        if mode == .search, fileShelf?.files.isEmpty == false, query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            list = list.filter { $0.id != "foundry.file-shelf" }
        }
        return list
    }

    struct HomeSections {
        var suggestions: [CommandResult] = []
        var commands: [CommandResult] = []
    }

    var homeSections: HomeSections {
        var sections = HomeSections()
        for result in searchListResults {
            if case .app = result.payload {
                if isSuggestibleApp(result), sections.suggestions.count < 5 {
                    sections.suggestions.append(result)
                }
            } else if isPrimaryWindowLayoutResult(result) == false, sections.commands.count < 5 {
                sections.commands.append(result)
            }
            if sections.suggestions.count >= 5, sections.commands.count >= 5 { break }
        }
        return sections
    }

    private func isPrimaryWindowLayoutResult(_ result: CommandResult) -> Bool {
        guard let action = result.primaryAction.behavior as? TileWindowAction else { return false }
        return [FoundryDomain.WindowPlacement.leftHalf, .rightHalf, .topHalf, .bottomHalf, .maximize, .restore].contains(action.placement)
    }

    /// `calculator.*` rows promote to the answer card; the `calculator.fallback.*`
    /// rows offered under it are ordinary list rows, not promotions.
    static func isPromotedCalculatorResult(_ result: CommandResult) -> Bool {
        switch result.payload {
        case .calculation, .calculationConversion: return true
        default: return false
        }
    }

    /// The selected result when it promotes to a calculator card. Reads
    /// `results` directly — `selectedResult` itself resolves through
    /// `navigableResults`, which consults this property.
    private var selectedPromotedCalculatorResult: CommandResult? {
        guard let selectedResultID,
              let selected = results.first(where: { $0.id == selectedResultID }),
              PanelSession.isPromotedCalculatorResult(selected) else { return nil }
        return selected
    }

    /// Static rows offered under a promoted calculator answer. Real
    /// CommandResults so arrow keys reach them like anything else.
    static let calculatorFallbackResults: [CommandResult] = [
        CommandResult(
            id: "calculator.fallback.clipboard",
            title: "Clipboard History",
            subtitle: "Search copied text, files, and images",
            icon: CommandIcon(fallback: "CB", systemName: "doc.on.clipboard"),
            payload: .calculatorFallback,
            primaryAction: CommandAction(id: "calculator.fallback.clipboard.open", title: "Open", behavior: OpenClipboardHistoryAction()),
            secondaryActions: []
        ),
        CommandResult(
            id: "calculator.fallback.fileshelf",
            title: "File Shelf",
            subtitle: "Hold files for quick actions",
            icon: CommandIcon(fallback: "FS", systemName: "tray.full"),
            payload: .calculatorFallback,
            primaryAction: CommandAction(id: "calculator.fallback.fileshelf.open", title: "Open", behavior: OpenFileShelfAction()),
            secondaryActions: []
        ),
        CommandResult(
            id: "calculator.fallback.settings",
            title: "Open Foundry Settings",
            subtitle: "Customize Home, commands, and Foundry preferences",
            icon: CommandIcon(fallback: "ST", systemName: "slider.horizontal.3"),
            payload: .calculatorFallback,
            primaryAction: CommandAction(id: "calculator.fallback.settings.open", title: "Open", behavior: OpenSettingsAction()),
            secondaryActions: []
        ),
    ]

    /// Favorites/Reset Ranking/Configure only make sense on durable commands
    /// and apps — not on ephemeral rows like files, clipboard items,
    /// calculator answers, or one-shot Ask-AI prompts.
    private func supportsMetaActions(_ result: CommandResult) -> Bool {
        switch result.payload {
        case .file, .calculation, .calculationConversion, .calculatorFallback, .aiPrompt:
            return false
        default:
            return true
        }
    }

    var selectedActions: [CommandAction] {
        guard let selectedResult else { return [] }
        let isFavorite = commandPreferences[selectedResult.id]?.favoriteRank != nil
        let metaActions = supportsMetaActions(selectedResult)
            ? [CommandAction(
                id: "favorite.toggle.\(selectedResult.id)",
                title: isFavorite ? "Remove from Favorites" : "Add to Favorites",
                behavior: ToggleFavoriteAction(commandID: selectedResult.id)
            ), CommandAction(
                id: "ranking.reset.\(selectedResult.id)",
                title: "Reset Ranking",
                behavior: ResetRankingAction(commandID: selectedResult.id)
            ), CommandAction(
                id: "settings.configure.\(selectedResult.id)",
                title: "Set Hotkey or Alias…",
                behavior: OpenCommandSettingsAction(SettingsDeepLink(result: selectedResult))
            )]
            : [CommandAction]()
        let actions = orderedActions(for: selectedResult) + openWithActions + metaActions
        guard let primary = actions.first else { return actions }
        let rest = actions.dropFirst()
        return [primary] + rest.filter { $0.isDestructive == false } + rest.filter(\.isDestructive)
    }

    var selectedAction: CommandAction? {
        selectedActions.first { $0.id == selectedActionID }
    }

    private func prepareOpenWithActions() {
        guard let result = selectedResult, case let .file(url) = result.payload else { return }
        let path = url.path
        let resultID = result.id
        openWithTask = Task { [weak self] in
            let (apps, defaultApp) = await Task.detached { () -> ([URL], URL?) in
                let apps = NSWorkspace.shared.urlsForApplications(toOpen: url)
                return (apps, NSWorkspace.shared.urlForApplication(toOpen: url))
            }.value
            guard Task.isCancelled == false else { return }
            let selfBundleID = Bundle.main.bundleIdentifier
            var actions: [CommandAction] = []
            for appURL in apps.prefix(12) {
                let bundle = Bundle(url: appURL)
                if bundle?.bundleIdentifier == selfBundleID { continue }
                let name = bundle?.localizedInfoDictionary?["CFBundleName"] as? String
                    ?? bundle?.infoDictionary?["CFBundleName"] as? String
                    ?? appURL.deletingPathExtension().lastPathComponent
                let isDefault = appURL == defaultApp
                actions.append(CommandAction(
                    id: "openwith.\(resultID).\(bundle?.bundleIdentifier ?? appURL.path)",
                    title: "Open with \(name)\(isDefault ? " — Default" : "")",
                    behavior: OpenFileWithAppAction(path: path, appPath: appURL.path)
                ))
            }
            guard let self, Task.isCancelled == false else { return }
            self.openWithActions = actions
        }
    }

    var visibleActions: [CommandAction] {
        let tokens = actionFilter.lowercased().split(separator: " ")
        guard tokens.isEmpty == false else { return selectedActions }
        return selectedActions.filter { action in
            let title = action.title.lowercased()
            return tokens.allSatisfy { title.contains($0) }
        }
    }

    var actionShortcuts: [String: ActionShortcut] {
        ActionShortcut.assign(to: selectedActions)
    }

    func orderedActions(for result: CommandResult) -> [CommandAction] {
        let actions = [result.primaryAction] + result.secondaryActions
        guard let preferredID = configService.current.commandPreferences[result.id]?.preferredPrimaryActionID,
              let preferredIndex = actions.firstIndex(where: { $0.id == preferredID }) else {
            return actions
        }
        let preferred = actions[preferredIndex]
        return [preferred] + actions.enumerated().compactMap { index, action in
            index == preferredIndex ? nil : action
        }
    }

    func preferredAction(for result: CommandResult) -> CommandAction {
        orderedActions(for: result).first ?? result.primaryAction
    }

    /// What ↵ will actually do to the selection — the footer's label must
    /// come from here, not from a typed-in string that can drift.
    var preferredActionTitle: String? {
        selectedResult.map { preferredAction(for: $0).title }
    }

    func select(resultID: String) {
        selectedResultID = resultID
        if isShowingActions {
            selectedActionID = selectedActions.first?.id
        }
    }

    func select(actionID: String) {
        selectedActionID = actionID
    }

    func toggleActions() {
        guard selectedResult != nil else {
            diagnostics.log("No selected result for actions")
            return
        }
        actionFilter = ""
        isShowingActions.toggle()
        selectedActionID = isShowingActions ? selectedActions.first?.id : nil
    }

    /// Arrow-key move inside the search list or the open actions overlay.
    /// Feature-mode selection lives on `PanelFeature.handleMove`.
    func moveSelection(offset: Int) {
        if isShowingActions {
            let actions = visibleActions
            guard actions.isEmpty == false else { return }
            let currentIndex = selectedActionID.flatMap { id in actions.firstIndex { $0.id == id } } ?? 0
            let nextIndex = min(max(currentIndex + offset, 0), actions.count - 1)
            selectedActionID = actions[nextIndex].id
            return
        }

        let list = navigableResults
        guard list.isEmpty == false else { return }
        let currentIndex = selectedResultID.flatMap { id in list.firstIndex { $0.id == id } } ?? 0
        let nextIndex = min(max(currentIndex + offset, 0), list.count - 1)
        selectedResultID = list[nextIndex].id
        selectionScrollToken = UUID()
        announce("\(list[nextIndex].title), \(nextIndex + 1) of \(list.count)")
    }

    func refreshResults() {
        guard mode == .search else { return }
        searchCoordinator.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        isShowingActions = false
        selectedActionID = nil
        guard trimmed.isEmpty == false else {
            isSearchLoading = false
            results = []
            selectedResultID = nil
            refreshHomeResults()
            return
        }

        isHomeLoading = false
        isSearchLoading = true
        if let span = searchKeySpan { diagnostics.discardSpan(span) }
        searchKeySpan = diagnostics.startSpan("search.keyToResults")

        if AIProvider.request(from: trimmed) != nil {
            isSearchLoading = false
            results = []
            selectedResultID = nil
            return
        }

        let leading = String(query.drop(while: \.isWhitespace))
        searchCoordinator.search(
            query: FileSearchProvider.fileQuery(leading) == nil ? trimmed : leading,
            onImmediate: { [weak self] immediateResults in
                guard let self else { return }
                self.selectedResultID = nil
                self.applySearchResults(immediateResults, preserving: nil)
                self.immediatePrefixIDs = Array(immediateResults.map(\.id).prefix(8))
                self.immediateAppliedAt = ContinuousClock.now
                self.selectionAfterImmediate = self.selectedResultID
            },
            onComplete: { [weak self] completeResults in
                guard let self else { return }
                self.isSearchLoading = false
                // Reordering the head after the user has seen (or touched) it
                // reads as rows jumping. Reorder only while the completion
                // lands inside the glance window and the selection is
                // untouched; otherwise the immediate head stays put and the
                // deferred results merge below it.
                let glanceWindowOpen = self.immediateAppliedAt.map {
                    ContinuousClock.now - $0 < .milliseconds(120)
                } ?? true
                let selectionUntouched = self.selectedResultID == self.selectionAfterImmediate
                let stablePrefix = (glanceWindowOpen && selectionUntouched) ? [] : self.immediatePrefixIDs
                self.applySearchResults(completeResults, preserving: self.selectedResultID, stablePrefixIDs: stablePrefix)
            }
        )
    }

    private func applySearchResults(_ rankedResults: [CommandResult], preserving preferredID: String?, stablePrefixIDs: [String] = []) {
        if let span = searchKeySpan {
            diagnostics.endSpan(span)
            searchKeySpan = nil
            diagnostics.mark("results.committed")
        }
        var nextResults = rankedResults
        if stablePrefixIDs.isEmpty == false {
            let head = stablePrefixIDs.compactMap { id in rankedResults.first { $0.id == id } }
            let headIDs = Set(head.map(\.id))
            nextResults = head + rankedResults.filter { headIDs.contains($0.id) == false }
        }
        results = nextResults
        if MediaDownloadProvider.mediaURLs(in: query).isEmpty == false,
           let mediaResult = nextResults.first(where: { $0.route == .mediaDownload }) {
            selectedResultID = mediaResult.id
        } else if let preferredID, nextResults.contains(where: { $0.id == preferredID }) {
            selectedResultID = preferredID
        } else if selectedResultID == nil || nextResults.contains(where: { $0.id == selectedResultID }) == false {
            selectedResultID = nextResults.first?.id
        }
        selectionScrollToken = UUID()
    }

    func refreshHomeResults() {
        // Paint the previous snapshot synchronously — opening to an empty or
        // spinner frame is a miss the user can see. The async load then
        // reconciles; it only replaces the list while we're still at home.
        if let snapshot = searchCoordinator.cachedHome() {
            applyHomeResults(snapshot)
            isHomeLoading = false
        } else {
            isHomeLoading = true
        }
        let refreshID = UUID()
        homeRefreshID = refreshID
        searchCoordinator.loadHome { [weak self] loadedResults in
            guard let self,
                  self.homeRefreshID == refreshID,
                  self.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            self.applyHomeResults(loadedResults)
        }
    }

    private func applyHomeResults(_ loadedResults: [CommandResult]) {
        var homeResults = loadedResults
        if fileShelf?.files.isEmpty == false {
            homeResults.removeAll { $0.id == "foundry.file-shelf" }
        }
        runningAppBundleIDs = PanelRouter.regularRunningAppBundleIDs()
        results = homeResults
        diagnostics.mark("results.committed")
        // Home hides some loaded rows; select the first one it paints.
        selectedResultID = navigableResults.first?.id
        selectionScrollToken = UUID()
        isHomeLoading = false
        refreshFavorites()
    }

    func isSuggestibleApp(_ result: CommandResult) -> Bool {
        HomeSuggestionRules.isSuggestible(
            payload: result.payload,
            runningBundleIDs: runningAppBundleIDs,
            hasUsage: registry.hasUsage(for: result.id)
        )
    }

    func hasUsage(for resultID: String) -> Bool {
        registry.hasUsage(for: resultID)
    }

    func refreshFavorites() {
        let favoriteIDs = commandPreferences
            .filter { $0.value.favoriteRank != nil }
            .sorted { ($0.value.favoriteRank ?? 0) < ($1.value.favoriteRank ?? 0) }
            .map(\.key)
        guard favoriteIDs.isEmpty == false else {
            favoriteResults = []
            return
        }
        let registry = registry
        Task { @MainActor [weak self] in
            var resolved: [CommandResult] = []
            for commandID in favoriteIDs.prefix(8) {
                guard let result = await registry.commandResult(for: commandID) else { continue }
                resolved.append(result)
            }
            self?.favoriteResults = resolved
        }
    }
}
