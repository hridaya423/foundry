import AppKit
import Foundation
import ServiceManagement
import SwiftUI
import FoundryDomain
import FoundryServices

// Feature-mode navigation: downloads, agents, shelf, clipboard,
// snippets, converter, camera, translator, devtools, Quick AI.
extension CommandPanelState {

    func resetTransientFeatures() {
        emojiPicker.reset()
        pendingSnippetArguments = nil
        fileConversion.reset()
        camera.stop()
        translator.reset()
        developerTools.reset()
    }

    func openSettings() {
        if isPanelOpen == false { onOpenSettings?() }
        beginFeatureMode(.settings)
    }

    func openWelcomeGuide() {
        onOpenWelcomeGuide?()
    }

    func openMediaDownloads() {
        beginFeatureMode(.mediaDownloads)
    }

    func cancelDownload(_ id: UUID) {
        actionRunner.cancel(id)
    }

    func retryDownload(_ item: MediaDownloadItem) {
        guard item.status != .active else { return }
        let action = CommandAction(
            id: "media.download.retry.\(UUID().uuidString)",
            title: "Retry Download",
            kind: .downloadMedia(url: item.sourceURL)
        )
        openMediaDownloads()
        Task { @MainActor [weak self] in
            guard let self else { return }
            _ = await execute(action, commandID: "media.download.retry")
        }
    }

    func changeMediaDownloadFolder() {
        let action = CommandAction(
            id: "media.download.choose-folder.\(UUID().uuidString)",
            title: "Change Download Folder",
            kind: .chooseMediaDownloadFolder
        )
        Task { @MainActor [weak self] in
            guard let self else { return }
            _ = await execute(action, commandID: "media.download.choose-folder")
        }
    }

    @discardableResult
    func startMediaDownloads(from value: String) -> Int {
        let urls = MediaDownloadProvider.mediaURLs(in: value)
        Task { @MainActor [weak self] in
            guard let self else { return }
            await withTaskGroup(of: Void.self) { group in
                var pending = urls[...]
                for _ in 0..<min(3, pending.count) {
                    let url = pending.removeFirst()
                    group.addTask { [weak self] in
                        _ = await self?.execute(Self.mediaDownloadAction(for: url), commandID: "media.download.batch")
                    }
                }
                while await group.next() != nil, pending.isEmpty == false {
                    let url = pending.removeFirst()
                    group.addTask { [weak self] in
                        _ = await self?.execute(Self.mediaDownloadAction(for: url), commandID: "media.download.batch")
                    }
                }
            }
        }
        return urls.count
    }

    static func mediaDownloadAction(for url: URL) -> CommandAction {
        CommandAction(
            id: "media.download.batch.\(UUID().uuidString)",
            title: "Download",
            kind: .downloadMedia(url: url.absoluteString)
        )
    }

    func openAgents() {
        beginFeatureMode(.agents)
        agents.start()
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
            query = text
        }
    }

    static func regularRunningAppBundleIDs() -> Set<String> {
        RunningAppsSnapshot.bundleIDs(regularOnly: true)
    }

    func stopTransientPolling() {
        widgetBoard.stop()
        agents.stopPolling()
    }

    func beginFeatureMode(_ nextMode: Mode) {
        stopTransientPolling()
        homeRefreshID = UUID()
        isSearchLoading = false
        isHomeLoading = false
        mode = nextMode
        isShowingActions = false
        selectedActionID = nil
        searchCoordinator.cancel()
        results = []
        selectedResultID = nil
    }

    func openEmojiPicker() {
        beginFeatureMode(.emojiPicker)
        emojiPicker.reset()
    }

    func openFileShelf() {
        beginFeatureMode(.fileShelf)
        fileShelf.selectFirst()
    }

    func openClipboardHistory() {
        beginFeatureMode(.clipboardHistory)
        clipboardHistory.reset()
    }

    func openSnippets() {
        beginFeatureMode(.snippets)
        snippets.reset()
        pendingSnippetArguments = nil
    }

    func openFileConverter(path: String? = nil) {
        openFileConverter(paths: path.map { [$0] } ?? [])
    }

    /// Public entry for launch arguments and Finder "Open With"/dock drops.
    func openFileConverter(paths: [String]) {
        beginFeatureMode(.fileConversion)
        fileConversion.reset()
        if paths.isEmpty == false {
            fileConversion.setSources(urls: paths.map { URL(fileURLWithPath: $0) })
        } else if fileShelf.selectedFiles.isEmpty == false {
            fileConversion.setSources(urls: fileShelf.selectedFiles.map(\.url))
        }
    }

    func openCamera() {
        beginFeatureMode(.camera)
        camera.start()
    }

    func openTranslator(text: String? = nil, language: String? = nil) {
        beginFeatureMode(.translator)
        translator.reset()
        if let text { translator.sourceText = text }
        if let language { translator.targetLanguage = language.capitalized }
    }

    func openDeveloperTools(tool: String? = nil) {
        beginFeatureMode(.developerTools)
        developerTools.reset()
        if let tool, let selectedTool = DeveloperToolsState.Tool(commandID: tool) {
            developerTools.selectedTool = selectedTool
        }
    }

    func openQuickAI(initialPrompt: String = "") {
        beginFeatureMode(.quickAI)
        quickAI.startNewThread(initialPrompt: initialPrompt, selectedAIProfileID: aiSettings.defaultAIProfileID)
    }
}
