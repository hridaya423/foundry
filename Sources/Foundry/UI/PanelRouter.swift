import AppKit
import Foundation
import SwiftUI
import FoundryDomain
import FoundryServices

/// The panel's mode stack: which surface is up, and how it got there.
/// Push/pop semantics live here — feature openers, route dispatch, Esc
/// handling, and returning home.
@MainActor
@Observable
final class PanelRouter {
    var mode: CommandPanelState.Mode = .search {
        didSet {
            guard mode != oldValue else { return }
            let span = diagnostics.startSpan("mode.switch")
            DispatchQueue.main.async { [diagnostics] in
                diagnostics.endSpan(span)
            }
        }
    }

    let diagnostics: DiagnosticsService
    /// The composition root the router steers — feature states, session
    /// fields, services, and the shell port.
    weak var panel: CommandPanelState?

    init(diagnostics: DiagnosticsService) {
        self.diagnostics = diagnostics
    }

    func resetTransientFeatures() {
        guard let panel else { return }
        panel.emojiPicker.reset()
        panel.pendingSnippetArguments = nil
        panel.scriptOutput = nil
        let built = panel.builtFeatures
        if built.contains(.fileConversion) { panel.fileConversion.reset() }
        if built.contains(.camera) { panel.camera.stop() }
        if built.contains(.translator) { panel.translator.reset() }
        if built.contains(.developerTools) { panel.developerTools.reset() }
    }

    func stopTransientPolling() {
        panel?.widgetBoard.stop()
        panel?.agents.stopPolling()
    }

    func beginFeatureMode(_ nextMode: CommandPanelState.Mode) {
        guard let panel else { return }
        stopTransientPolling()
        panel.session.homeRefreshID = UUID()
        panel.session.isSearchLoading = false
        panel.session.isHomeLoading = false
        mode = nextMode
        panel.session.isShowingActions = false
        panel.session.selectedActionID = nil
        panel.searchCoordinator.cancel()
        panel.session.results = []
        panel.session.selectedResultID = nil
    }

    func open(_ route: CommandRoute) {
        switch route {
        case let .quickAI(initialPrompt):
            openQuickAI(initialPrompt: initialPrompt)
        case .emojiPicker:
            openEmojiPicker()
        case .fileShelf:
            openFileShelf()
        case .clipboardHistory:
            openClipboardHistory()
        case .snippets:
            openSnippets()
        case let .snippet(id, followUp):
            openSnippets()
            panel?.snippets.select(id: id)
            switch followUp {
            case .select: break
            case .insert: _ = panel?.insertOrCopySelectedSnippet()
            case .copy: _ = panel?.copySelectedSnippet()
            }
        case let .fileConversion(path):
            openFileConverter(path: path)
        case .camera:
            openCamera()
        case let .translator(text, language):
            openTranslator(text: text, language: language)
        case let .developerTools(tool):
            openDeveloperTools(tool: tool)
        case .settings:
            openSettings()
        case .home:
            showHome()
        case .mediaDownloads:
            openMediaDownloads()
        case .welcomeGuide:
            openWelcomeGuide()
        case let .query(text):
            panel?.session.query = text
        case let .scriptOutput(title, text):
            beginFeatureMode(.scriptOutput)
            panel?.scriptOutput = ScriptOutput(title: title, text: text)
        }
    }

    /// Settings lives in its own window — the launcher stays a launcher.
    func openSettings() {
        panel?.shell?.openSettings()
    }

    func openWelcomeGuide() {
        panel?.shell?.openWelcomeGuide()
    }

    func openMediaDownloads() {
        beginFeatureMode(.mediaDownloads)
    }

    func openAgents() {
        beginFeatureMode(.agents)
        panel?.agents.start()
    }

    func openEmojiPicker() {
        beginFeatureMode(.emojiPicker)
        panel?.emojiPicker.reset()
    }

    func openFileShelf() {
        beginFeatureMode(.fileShelf)
        panel?.fileShelf.selectFirst()
    }

    func openClipboardHistory() {
        beginFeatureMode(.clipboardHistory)
        panel?.clipboardHistory.reset()
    }

    func openSnippets() {
        beginFeatureMode(.snippets)
        panel?.snippets.reset()
        panel?.pendingSnippetArguments = nil
    }

    func openFileConverter(path: String? = nil) {
        openFileConverter(paths: path.map { [$0] } ?? [])
    }

    /// Public entry for launch arguments and Finder "Open With"/dock drops.
    func openFileConverter(paths: [String]) {
        guard let panel else { return }
        beginFeatureMode(.fileConversion)
        panel.fileConversion.reset()
        if paths.isEmpty == false {
            panel.fileConversion.setSources(urls: paths.map { URL(fileURLWithPath: $0) })
        } else if panel.fileShelf.selectedFiles.isEmpty == false {
            panel.fileConversion.setSources(urls: panel.fileShelf.selectedFiles.map(\.url))
        }
    }

    func openCamera() {
        beginFeatureMode(.camera)
        panel?.camera.start()
    }

    func openTranslator(text: String? = nil, language: String? = nil) {
        guard let panel else { return }
        beginFeatureMode(.translator)
        panel.translator.reset()
        if let text { panel.translator.sourceText = text }
        if let language { panel.translator.targetLanguage = language.capitalized }
    }

    func openDeveloperTools(tool: String? = nil) {
        guard let panel else { return }
        beginFeatureMode(.developerTools)
        panel.developerTools.reset()
        if let tool, let selectedTool = DeveloperToolsState.Tool(commandID: tool) {
            panel.developerTools.selectedTool = selectedTool
        }
    }

    func openQuickAI(initialPrompt: String = "") {
        guard let panel else { return }
        beginFeatureMode(.quickAI)
        panel.quickAI.startNewThread(initialPrompt: initialPrompt, selectedAIProfileID: panel.aiSettings.defaultAIProfileID)
    }

    /// Esc: pending prompt → pending drop choice → actions overlay → clear
    /// query → mode back to search → false lets the caller dismiss the panel.
    func handleEscape() -> Bool {
        guard let panel else { return false }
        if panel.pendingPrompt != nil {
            panel.cancelPrompt()
            return true
        }
        if panel.pendingSnippetArguments != nil {
            panel.cancelSnippetArguments()
            return true
        }
        if panel.shell?.isQuickLookShowing == true {
            panel.shell?.closeQuickLook()
            return true
        }
        if panel.pendingDropURLs != nil {
            panel.pendingDropURLs = nil
            return true
        }
        if panel.session.isShowingActions {
            if panel.session.actionFilter.isEmpty {
                panel.session.isShowingActions = false
                panel.session.selectedActionID = nil
            } else {
                panel.session.actionFilter = ""
            }
            return true
        }
        if mode == .search {
            // Raycast semantics: Esc clears the query first, then a second
            // Esc dismisses the panel.
            guard panel.session.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
                return false
            }
            panel.session.query = ""
            return true
        }
        if panel.feature(for: mode)?.clearFilter() == true {
            return true
        }
        showHome()
        return true
    }

    func showHome() {
        guard let panel else { return }
        panel.detachActiveAction()
        stopTransientPolling()
        panel.searchCoordinator.cancel()
        panel.session.homeRefreshID = UUID()
        mode = .search
        panel.session.isSearchLoading = false
        panel.session.isHomeLoading = false
        resetTransientFeatures()
        panel.session.query = ""
        panel.quickAI.resetTransientState()
        panel.session.selectedResultID = nil
        panel.session.isShowingActions = false
        panel.session.selectedActionID = nil
        panel.session.refreshHomeResults()
        panel.widgetBoard.start()
        if panel.settings.isAgentShelfVisible {
            panel.agents.start()
        }
    }

    static func regularRunningAppBundleIDs() -> Set<String> {
        RunningAppsSnapshot.bundleIDs(regularOnly: true)
    }
}
