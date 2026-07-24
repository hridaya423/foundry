import AppKit
import Foundation
import SwiftUI

@MainActor
final class CommandPanelState: ObservableObject {
    enum Mode {
        case search
        case quickAI
        case activityMonitor
        case emojiPicker
        case fileShelf
        case clipboardHistory
        case snippets
        case fileConversion
        case camera
        case translator
        case developerTools
        case settings
    }

    @Published var query = "" {
        didSet { refreshResults() }
    }
    @Published var quickAIQuery = ""
    @Published var quickAIResponse = ""
    @Published var quickAIStatus = ""
    @Published var isQuickAILoading = false
    @Published var quickAILastFailedPrompt: String?
    @Published var quickAIThreads: [AIChatThread]
    @Published var activeQuickAIThreadID: UUID?
    @Published var results: [CommandResult] = []
    @Published var selectedResultID: String?
    @Published var isShowingActions = false
    @Published var selectedActionID: String?
    @Published var diagnosticsSummary = "IDLE"
    @Published var mode: Mode = .search
    @Published var isAgentShelfVisible: Bool
    @Published var hotkey: FoundryHotkey
    @Published var themeIntensity: Double
    @Published var isOllamaEnabled: Bool
    var onHotkeyChanged: ((FoundryHotkey) -> Void)?

    let activityMonitor = ActivityMonitorState()
    let emojiPicker = EmojiPickerState()
    let fileShelf = FileShelfState()
    let agents = AgentMonitorState()
    let clipboardHistory = ClipboardHistoryState()
    let snippets = SnippetState()
    let fileConversion = FileConversionState()
    let camera = CameraPreviewState()
    let translator = TranslatorState()
    let developerTools = DeveloperToolsState()
    let widgetBoard: WidgetBoardState
    private let configService: ConfigService

    private let registry: CommandRegistry
    private let actionRunner: ActionRunner
    private let diagnostics: DiagnosticsService
    private let aiProvider: AIProvider
    private let aiChatStore = AIChatStore()
    private var statusTimer: Timer?
    private var searchTask: Task<Void, Never>?
    private var quickAITask: Task<Void, Never>?
    private var quickAIRequestID: UUID?
    private var searchGeneration = 0
    private var isMediaDownloadActive = false

    var selectedResult: CommandResult? {
        results.first { $0.id == selectedResultID }
    }

    var selectedActions: [CommandAction] {
        guard let selectedResult else { return [] }
        return [selectedResult.primaryAction] + selectedResult.secondaryActions
    }

    var selectedAction: CommandAction? {
        selectedActions.first { $0.id == selectedActionID }
    }

    init(registry: CommandRegistry, actionRunner: ActionRunner, diagnostics: DiagnosticsService, config: ConfigService) {
        self.registry = registry
        self.actionRunner = actionRunner
        self.diagnostics = diagnostics
        self.configService = config
        self.aiProvider = AIProvider(config: config, diagnostics: diagnostics)
        let loadedThreads = aiChatStore.load()
        self.quickAIThreads = loadedThreads
        self.activeQuickAIThreadID = loadedThreads.first?.id
        self.isAgentShelfVisible = config.current.showAgentShelf
        self.hotkey = config.current.hotkey
        self.themeIntensity = config.current.themeIntensity
        self.isOllamaEnabled = config.current.ai.isOllamaEnabled
        self.widgetBoard = WidgetBoardState(configService: config)
        actionRunner.mediaStatusHandler = { [weak self] message in
            let normalized = message.lowercased()
            self?.isMediaDownloadActive = normalized.hasPrefix("downloaded") == false && normalized.contains("failed") == false
            self?.diagnosticsSummary = message
        }
        clipboardHistory.start()
        agents.start()
        self.statusTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshStatusSummary()
            }
        }
    }

    private func persistAIThreads() {
        aiChatStore.save(quickAIThreads)
    }

    func setAgentShelfVisible(_ isVisible: Bool) {
        guard isAgentShelfVisible != isVisible else { return }
        isAgentShelfVisible = isVisible
        configService.updateAgentShelfVisibility(isVisible)
    }

    func setHotkey(_ hotkey: FoundryHotkey) {
        guard self.hotkey != hotkey else { return }
        self.hotkey = hotkey
        configService.updateHotkey(hotkey)
        onHotkeyChanged?(hotkey)
    }

    func setThemeIntensity(_ intensity: Double) {
        themeIntensity = intensity
        configService.updateThemeIntensity(intensity)
    }

    func setOllamaEnabled(_ isEnabled: Bool) {
        isOllamaEnabled = isEnabled
        var ai = configService.current.ai
        ai.isOllamaEnabled = isEnabled
        configService.updateAIConfig(ai)
    }

    func resetForOpen() {
        mode = .search
        widgetBoard.start()
        agents.start()
        activityMonitor.stop()
        emojiPicker.reset()
        clipboardHistory.reset()
        snippets.reset()
        fileConversion.reset()
        camera.stop()
        translator.reset()
        developerTools.reset()
        query = ""
        quickAIQuery = ""
        quickAIResponse = ""
        quickAIStatus = ""
        isQuickAILoading = false
        quickAILastFailedPrompt = nil
        quickAITask?.cancel()
        quickAITask = nil
        quickAIRequestID = nil
        results = []
        selectedResultID = nil
        isShowingActions = false
        selectedActionID = nil
        isMediaDownloadActive = false
        refreshStatusSummary()
    }

    func panelWillClose() {
        widgetBoard.stop()
        agents.stop()
        activityMonitor.stop()
        emojiPicker.reset()
        clipboardHistory.reset()
        snippets.reset()
        fileConversion.reset()
        camera.stop()
        translator.reset()
        developerTools.reset()
    }

    func openSettings() {
        withAnimation(.easeOut(duration: 0.14)) {
            mode = .settings
        }
        widgetBoard.start()
        isShowingActions = false
        selectedActionID = nil
        searchTask?.cancel()
        results = []
        selectedResultID = nil
        diagnosticsSummary = "settings"
    }

    func handleEscape() -> Bool {
        if mode != .search || isShowingActions {
            backToSearch()
            return true
        }
        return false
    }

    func backToSearch() {
        withAnimation(.easeOut(duration: 0.14)) {
            mode = .search
        }
        widgetBoard.stop()
        activityMonitor.stop()
        emojiPicker.reset()
        camera.stop()
        fileConversion.reset()
        translator.reset()
        developerTools.reset()
        query = ""
        quickAIQuery = ""
        quickAIResponse = ""
        quickAIStatus = ""
        isQuickAILoading = false
        quickAILastFailedPrompt = nil
        quickAITask?.cancel()
        quickAITask = nil
        quickAIRequestID = nil
        results = []
        selectedResultID = nil
        isShowingActions = false
        selectedActionID = nil
        refreshStatusSummary()
    }

    @discardableResult
    func executeSelectedResult() -> Bool {
        guard let selectedResult else {
            if let request = AIProvider.request(from: query) {
                openQuickAI(initialPrompt: request.prompt)
            }
            return false
        }
        if isShowingActions, let selectedAction {
            diagnostics.log("Executing action: \(selectedAction.id)")
            registry.recordExecution(resultID: selectedResult.id)
            if case let .openQuickAI(prompt) = selectedAction.kind {
                openQuickAI(initialPrompt: prompt)
                return false
            }
            if case .downloadMedia = selectedAction.kind {
                isMediaDownloadActive = true
                diagnosticsSummary = "Starting download"
                actionRunner.perform(selectedAction)
                return false
            }
            if selectedAction.kind == .chooseMediaDownloadFolder {
                actionRunner.perform(selectedAction)
                refreshResults()
                return false
            }
            actionRunner.perform(selectedAction)
            return true
        }

        diagnostics.log("Executing result: \(selectedResult.id)")
        registry.recordExecution(resultID: selectedResult.id)
        if case let .openQuickAI(prompt) = selectedResult.primaryAction.kind {
            openQuickAI(initialPrompt: prompt)
            return false
        }
        if selectedResult.primaryAction.kind == .openActivityMonitor {
            openActivityMonitor()
            return false
        }
        if selectedResult.primaryAction.kind == .openEmojiPicker {
            openEmojiPicker()
            return false
        }
        if selectedResult.primaryAction.kind == .openFileShelf {
            openFileShelf()
            return false
        }
        if selectedResult.primaryAction.kind == .openClipboardHistory {
            openClipboardHistory()
            return false
        }
        if selectedResult.primaryAction.kind == .openSnippets {
            openSnippets()
            return false
        }
        if case let .openFileConverter(path) = selectedResult.primaryAction.kind {
            openFileConverter(path: path)
            return false
        }
        if selectedResult.primaryAction.kind == .openCamera {
            openCamera()
            return false
        }
        if case let .openTranslator(text, language) = selectedResult.primaryAction.kind {
            openTranslator(text: text, language: language)
            return false
        }
        if case let .openDeveloperTools(tool) = selectedResult.primaryAction.kind {
            openDeveloperTools(tool: tool)
            return false
        }
        if selectedResult.primaryAction.kind == .openSettings {
            openSettings()
            return false
        }
        if case .downloadMedia = selectedResult.primaryAction.kind {
            isMediaDownloadActive = true
            diagnosticsSummary = "Starting download"
            actionRunner.perform(selectedResult.primaryAction)
            return false
        }
        if selectedResult.primaryAction.kind == .chooseMediaDownloadFolder {
            actionRunner.perform(selectedResult.primaryAction)
            refreshResults()
            return false
        }
        actionRunner.perform(selectedResult.primaryAction)
        return true
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
        isShowingActions.toggle()
        selectedActionID = isShowingActions ? selectedActions.first?.id : nil
    }

    func pasteFromClipboard() -> Bool {
        guard let text = NSPasteboard.general.string(forType: .string), text.isEmpty == false else { return false }
        switch mode {
        case .search:
            query += text
        case .activityMonitor:
            activityMonitor.query += text
        case .emojiPicker:
            emojiPicker.query += text
        case .clipboardHistory:
            clipboardHistory.query += text
        case .snippets:
            snippets.query += text
        case .translator:
            translator.sourceText += text
        case .camera, .fileConversion, .fileShelf, .settings, .developerTools, .quickAI:
            return false
        }
        return true
    }

    func showFileShelf() {
        openFileShelf()
    }

    func moveSelectionDown() {
        moveSelection(offset: 1)
    }

    func moveSelectionUp() {
        moveSelection(offset: -1)
    }

    private func moveSelection(offset: Int) {
        if mode == .activityMonitor {
            activityMonitor.moveSelection(offset: offset)
            return
        }

        if mode == .emojiPicker {
            offset > 0 ? emojiPicker.moveDown() : emojiPicker.moveUp()
            return
        }

        if mode == .fileShelf {
            fileShelf.moveSelection(offset: offset)
            return
        }

        if mode == .fileConversion {
            return
        }

        if mode == .snippets {
            snippets.moveSelection(offset: offset)
            return
        }

        if mode == .clipboardHistory {
            clipboardHistory.moveSelection(offset: offset)
            return
        }

        if mode == .camera {
            return
        }

        if mode == .translator {
            return
        }

        if isShowingActions {
            let actions = selectedActions
            guard actions.isEmpty == false else { return }
            let currentIndex = selectedActionID.flatMap { id in actions.firstIndex { $0.id == id } } ?? 0
            let nextIndex = min(max(currentIndex + offset, 0), actions.count - 1)
            selectedActionID = actions[nextIndex].id
            return
        }

        guard results.isEmpty == false else { return }
        let currentIndex = selectedResultID.flatMap { id in results.firstIndex { $0.id == id } } ?? 0
        let nextIndex = min(max(currentIndex + offset, 0), results.count - 1)
        selectedResultID = results[nextIndex].id
    }

    private func refreshResults() {
        guard mode == .search else { return }
        searchTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        isShowingActions = false
        selectedActionID = nil
        guard trimmed.isEmpty == false else {
            results = []
            selectedResultID = nil
            refreshStatusSummary()
            refreshHomeResults()
            return
        }

        if AIProvider.request(from: trimmed) != nil {
            results = []
            selectedResultID = nil
            refreshStatusSummary(fallback: "Press Tab or Return to ask AI")
            return
        }

        searchGeneration += 1
        let generation = searchGeneration
        let registry = registry
        let diagnostics = diagnostics
        let span = diagnostics.startSpan("search.async")

        searchTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(80))
            } catch {
                diagnostics.endSpan(span)
                return
            }

            guard Task.isCancelled == false else {
                diagnostics.endSpan(span)
                return
            }

            let foundResults = await registry.results(matching: trimmed)
            guard let self,
                  Task.isCancelled == false,
                  self.searchGeneration == generation,
                  self.query.trimmingCharacters(in: .whitespacesAndNewlines) == trimmed else {
                diagnostics.endSpan(span)
                return
            }

            self.results = foundResults
            self.selectedResultID = foundResults.first?.id
            self.refreshStatusSummary()
            diagnostics.endSpan(span)
        }
    }

    private func refreshStatusSummary(fallback: String = "") {
        guard isMediaDownloadActive == false else { return }
        diagnosticsSummary = registry.statusSummary(resultCount: results.count, fallback: fallback)
    }

    private func refreshHomeResults() {
        searchGeneration += 1
        let generation = searchGeneration
        let registry = registry
        searchTask?.cancel()
        searchTask = Task { [weak self] in
            var homeResults = await registry.homeResults()
            guard let self,
                  Task.isCancelled == false,
                  self.searchGeneration == generation,
                  self.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            if self.fileShelf.files.isEmpty == false {
                homeResults.removeAll { $0.id == "foundry.file-shelf" }
            }
            self.results = homeResults
            self.selectedResultID = homeResults.first?.id
            self.refreshStatusSummary()
        }
    }

    private func openActivityMonitor() {
        withAnimation(.easeOut(duration: 0.14)) {
            mode = .activityMonitor
        }
        isShowingActions = false
        selectedActionID = nil
        searchTask?.cancel()
        results = []
        selectedResultID = nil
        activityMonitor.reset()
        activityMonitor.start()
        diagnosticsSummary = "activity monitor"
    }

    private func openEmojiPicker() {
        withAnimation(.easeOut(duration: 0.14)) {
            mode = .emojiPicker
        }
        isShowingActions = false
        selectedActionID = nil
        searchTask?.cancel()
        results = []
        selectedResultID = nil
        emojiPicker.reset()
        diagnosticsSummary = "emoji & symbols"
    }

    private func openFileShelf() {
        withAnimation(.easeOut(duration: 0.14)) {
            mode = .fileShelf
        }
        isShowingActions = false
        selectedActionID = nil
        searchTask?.cancel()
        results = []
        selectedResultID = nil
        fileShelf.selectFirst()
        diagnosticsSummary = "file shelf"
    }

    private func openClipboardHistory() {
        withAnimation(.easeOut(duration: 0.14)) {
            mode = .clipboardHistory
        }
        isShowingActions = false
        selectedActionID = nil
        searchTask?.cancel()
        results = []
        selectedResultID = nil
        clipboardHistory.reset()
        diagnosticsSummary = "clipboard history"
    }

    private func openSnippets() {
        withAnimation(.easeOut(duration: 0.14)) {
            mode = .snippets
        }
        isShowingActions = false
        selectedActionID = nil
        searchTask?.cancel()
        results = []
        selectedResultID = nil
        snippets.reset()
        diagnosticsSummary = "snippets"
    }

    private func openFileConverter(path: String? = nil) {
        withAnimation(.easeOut(duration: 0.14)) {
            mode = .fileConversion
        }
        isShowingActions = false
        selectedActionID = nil
        searchTask?.cancel()
        results = []
        selectedResultID = nil
        fileConversion.reset()
        if let path {
            fileConversion.setSource(url: URL(fileURLWithPath: path))
        } else if let selectedFile = fileShelf.selectedFile {
            fileConversion.setSource(url: selectedFile.url)
        }
        diagnosticsSummary = "file converter"
    }

    private func openCamera() {
        withAnimation(.easeOut(duration: 0.14)) {
            mode = .camera
        }
        isShowingActions = false
        selectedActionID = nil
        searchTask?.cancel()
        results = []
        selectedResultID = nil
        camera.start()
        diagnosticsSummary = "camera"
    }

    private func openTranslator(text: String? = nil, language: String? = nil) {
        withAnimation(.easeOut(duration: 0.14)) {
            mode = .translator
        }
        isShowingActions = false
        selectedActionID = nil
        searchTask?.cancel()
        results = []
        selectedResultID = nil
        translator.reset()
        if let text { translator.sourceText = text }
        if let language { translator.targetLanguage = language.capitalized }
        diagnosticsSummary = "translator"
    }

    private func openDeveloperTools(tool: String? = nil) {
        withAnimation(.easeOut(duration: 0.14)) {
            mode = .developerTools
        }
        isShowingActions = false
        selectedActionID = nil
        searchTask?.cancel()
        results = []
        selectedResultID = nil
        developerTools.reset()
        if let tool, let selectedTool = DeveloperToolsState.Tool(commandID: tool) {
            developerTools.selectedTool = selectedTool
        }
        diagnosticsSummary = "developer tools"
    }

    func openQuickAI(initialPrompt: String = "") {
        quickAITask?.cancel()
        quickAITask = nil
        quickAIRequestID = nil
        let prompt = AIProvider.request(from: initialPrompt)?.prompt ?? initialPrompt
        withAnimation(.easeOut(duration: 0.14)) {
            mode = .quickAI
        }
        searchTask?.cancel()
        results = []
        selectedResultID = nil
        isShowingActions = false
        selectedActionID = nil
        quickAIQuery = prompt
        quickAIResponse = ""
        quickAIStatus = prompt.isEmpty ? "Ask anything" : "Ready"
        isQuickAILoading = false
        quickAILastFailedPrompt = nil
        let thread = AIChatThread(title: prompt.isEmpty ? "New Chat" : prompt)
        quickAIThreads.insert(thread, at: 0)
        activeQuickAIThreadID = thread.id
        persistAIThreads()
        if prompt.isEmpty == false {
            Task { await submitQuickAI() }
        }
    }

    func submitQuickAI() async {
        let prompt = quickAIQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard prompt.isEmpty == false else {
            quickAIStatus = "Type a question first"
            return
        }
        quickAIQuery = ""
        quickAITask?.cancel()
        quickAIRequestID = nil
        guard let threadID = activeQuickAIThreadID else {
            quickAIStatus = "Start a chat first"
            return
        }
        let requestID = UUID()
        quickAIRequestID = requestID
        quickAITask = Task { [weak self] in
            await self?.performQuickAI(prompt: prompt, threadID: threadID, requestID: requestID)
        }
        await quickAITask?.value
    }

    func retryQuickAI() {
        guard let prompt = quickAILastFailedPrompt, isQuickAILoading == false else { return }
        quickAILastFailedPrompt = nil
        quickAITask?.cancel()
        guard let threadID = activeQuickAIThreadID else { return }
        let requestID = UUID()
        quickAIRequestID = requestID
        quickAITask = Task { [weak self] in
            await self?.performQuickAI(prompt: prompt, persistUserMessage: false, threadID: threadID, requestID: requestID)
        }
    }

    private func performQuickAI(prompt: String, persistUserMessage: Bool = true, threadID: UUID, requestID: UUID) async {
        guard isCurrentQuickAIRequest(requestID, threadID: threadID) else { return }
        isQuickAILoading = true
        quickAIStatus = "Thinking"
        quickAIResponse = ""
        var didFail = false
        var response = ""
        let priorMessages = quickAIThreads.first(where: { $0.id == threadID })
            .map { Array($0.messages.filter { $0.role == .user || $0.role == .assistant }.suffix(10)) } ?? []
        let conversationContext = AIConversationContext.build(from: priorMessages)
        if persistUserMessage, let index = quickAIThreads.firstIndex(where: { $0.id == threadID }) {
            quickAIThreads[index].messages.append(AIChatMessage(role: .user, content: prompt))
            quickAIThreads[index].updatedAt = .now
            if quickAIThreads[index].title == "New Chat" {
                quickAIThreads[index].title = prompt.prefix(48).description
            }
            persistAIThreads()
        }

        for await event in aiProvider.stream(prompt: prompt, context: conversationContext) {
            guard Task.isCancelled == false else {
                guard isCurrentQuickAIRequest(requestID, threadID: threadID) else { return }
                isQuickAILoading = false
                quickAIStatus = "Cancelled"
                quickAILastFailedPrompt = prompt
                return
            }
            guard isCurrentQuickAIRequest(requestID, threadID: threadID) else { return }
            switch event {
            case let .status(status):
                quickAIStatus = status
            case let .textDelta(delta):
                response += delta
                quickAIResponse = response
            case let .toolCallStarted(name):
                quickAIStatus = "Using \(name.replacingOccurrences(of: "_", with: " "))"
                recordToolStarted(name, threadID: threadID)
            case let .toolResult(name, result):
                quickAIStatus = "Finished \(name.replacingOccurrences(of: "_", with: " "))"
                recordToolFinished(name, result: result, threadID: threadID)
            case .completed:
                quickAIStatus = "Done"
            case let .failed(message):
                didFail = true
                quickAILastFailedPrompt = prompt
                quickAIStatus = message
                response = message
                quickAIResponse = message
            }
        }

        guard Task.isCancelled == false else {
            guard isCurrentQuickAIRequest(requestID, threadID: threadID) else { return }
            isQuickAILoading = false
            quickAIStatus = "Cancelled"
            quickAILastFailedPrompt = prompt
            return
        }
        guard isCurrentQuickAIRequest(requestID, threadID: threadID) else { return }
        quickAIStatus = didFail ? "Failed" : response.isEmpty ? "No response" : "Done"
        isQuickAILoading = false
        if let index = quickAIThreads.firstIndex(where: { $0.id == threadID }) {
            if response.isEmpty == false, didFail == false {
                quickAIThreads[index].messages.append(AIChatMessage(role: .assistant, content: response))
            }
            quickAIThreads[index].updatedAt = .now
            persistAIThreads()
        }
    }

    private func recordToolStarted(_ name: String, threadID: UUID) {
        guard let index = quickAIThreads.firstIndex(where: { $0.id == threadID }) else { return }
        quickAIThreads[index].messages.append(AIChatMessage(role: .tool, content: "running:\(name)"))
        quickAIThreads[index].updatedAt = .now
        persistAIThreads()
    }

    private func recordToolFinished(_ name: String, result: String, threadID: UUID) {
        guard let threadIndex = quickAIThreads.firstIndex(where: { $0.id == threadID }),
              let messageIndex = quickAIThreads[threadIndex].messages.lastIndex(where: { $0.role == .tool && $0.content == "running:\(name)" }) else { return }
        quickAIThreads[threadIndex].messages[messageIndex].content = "complete:\(name)\n\(String(result.prefix(1800)))"
        quickAIThreads[threadIndex].updatedAt = .now
        persistAIThreads()
    }

    func selectQuickAIThread(_ thread: AIChatThread) {
        quickAITask?.cancel()
        quickAITask = nil
        quickAIRequestID = nil
        activeQuickAIThreadID = thread.id
        quickAIQuery = ""
        quickAIResponse = thread.messages.last(where: { $0.role == .assistant })?.content ?? ""
        quickAIStatus = thread.messages.isEmpty ? "Ask anything" : "Loaded"
        quickAILastFailedPrompt = nil
        mode = .quickAI
    }

    private func isCurrentQuickAIRequest(_ requestID: UUID, threadID: UUID) -> Bool {
        requestID == quickAIRequestID && threadID == activeQuickAIThreadID
    }

}
