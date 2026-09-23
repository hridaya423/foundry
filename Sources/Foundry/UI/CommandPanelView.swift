import AppKit
import SwiftUI
import UniformTypeIdentifiers
import FoundryDomain

struct CommandPanelView: View {
    @Bindable var state: CommandPanelState
    let dismiss: () -> Void

    private var fileShelf: FileShelfState
    private var agents: AgentMonitorState
    private var widgetBoard: WidgetBoardState

    @FocusState private var inputFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme
    @State private var isDropTargeted = false
    @State private var presented = false

    init(state: CommandPanelState, dismiss: @escaping () -> Void) {
        self.state = state
        self.dismiss = dismiss
        self.fileShelf = state.fileShelf
        self.agents = state.agents
        self.widgetBoard = state.widgetBoard
    }

    private var selectedCalculatorResult: CommandResult? {
        guard let selectedResult = state.selectedResult, selectedResult.id.hasPrefix("calculator.") else { return nil }
        return selectedResult
    }

    private var isHome: Bool {
        state.mode == .search
            && state.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && selectedCalculatorResult == nil
            && state.isShowingActions == false
    }

    private var nativeGlassEnabled: Bool {
        FoundryMaterialPolicy.currentRendering(reduceTransparency: reduceTransparency) == .nativeGlass
    }

    private var shouldShowHomeAccessory: Bool {
        guard state.mode == .search,
              state.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        return fileShelf.files.isEmpty == false
            || agents.visibleSessions.isEmpty == false
            || widgetBoard.homeWidgets.contains { $0 != .agents }
    }

    var body: some View {
        let surface = self.surface
        let base = VStack(spacing: 0) {
            FeatureHeader(
                showBack: state.mode != .search,
                onBack: state.showHome,
                showsHairline: nativeGlassEnabled == false,
                content: { surface.header },
                trailing: { surface.headerTrailing }
            )

            if state.compactCollapsed == false {
                if shouldShowHomeAccessory {
                    homeAccessoryStrip
                        .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
                }

                surface.content
                    .id(surface.id)
                    .transition(.opacity)

                panelFooter
            }
        }

        let decorated = base
            .background(FoundryBackdrop(intensity: state.themeIntensity, isOpaque: reduceTransparency))
            .overlay(shellChrome)
            .clipShape(FoundrySmoothedRectangle(cornerRadius: FoundryTheme.Radius.panel, smoothing: 0.75))
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        let highlighted = decorated
            .environment(\.foundryHoverHighlightsArmed, state.hoverHighlightsArmed)
            .overlay(dropOverlay)

        let feedbackWrapped = highlighted.overlay(alignment: Alignment.bottom) {
            if let actionFeedback = state.actionFeedback {
                FoundryGlassSurface(role: .floatingOverlay, shape: Capsule()) {
                    Label(actionFeedback.message, systemImage: actionFeedback.symbolName)
                        .font(FoundryTheme.body(size: 12, weight: .semibold))
                        .foregroundStyle(actionFeedbackColor(actionFeedback))
                        .padding(.horizontal, 12)
                        .frame(minHeight: 30)
                }
                    .padding(.bottom, 50)
                    .padding(.horizontal, 18)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .bottom)))
            }
        }

        let animated = feedbackWrapped
            .overlay(alignment: .bottomTrailing) {
                if state.isShowingActions {
                    FoundryGlassSurface(role: .floatingOverlay, shape: RoundedRectangle(cornerRadius: 16, style: .continuous)) {
                        actionsSurface
                            .frame(width: 340)
                            .frame(maxHeight: 320)
                    }
                    .shadow(color: .black.opacity(0.35), radius: 24, y: 10)
                    .padding(.trailing, 12)
                    .padding(.bottom, 46)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.96, anchor: .bottomTrailing)))
                }
            }
            .animation(reduceMotion ? nil : Animation.easeOut(duration: 0.14), value: state.isShowingActions)
            .animation(reduceMotion ? nil : Animation.easeInOut(duration: 0.12), value: state.mode)
            .animation(reduceMotion ? nil : Animation.easeOut(duration: 0.14), value: fileShelf.files.count)
            .animation(reduceMotion ? nil : Animation.easeOut(duration: 0.14), value: agents.sessions.count)

        return animated
            .scaleEffect(reduceMotion || presented ? 1 : 0.97)
            .opacity(presented ? 1 : 0)
            .onChange(of: state.mode) { _, _ in
                inputFocused = true
            }
            .onChange(of: state.focusToken) { _, _ in
                inputFocused = true
            }
            .onChange(of: state.presentationToken) { _, _ in
                replayPresentation()
            }
            .onChange(of: state.compactCollapsed) { _, collapsed in
                state.onCompactCollapseChanged?(collapsed)
            }
            .onDrop(of: [UTType.fileURL], isTargeted: $isDropTargeted, perform: handleFileDrop)
            .onDeleteCommand {
                if state.mode == .fileShelf {
                    state.fileShelf.removeSelected()
                }
                if state.mode == .clipboardHistory {
                    state.clipboardHistory.removeSelected()
                }
            }
            .onAppear {
                inputFocused = true
                replayPresentation()
            }
            .onMoveCommand { direction in
                switch direction {
                case .down:
                    state.moveSelectionDown()
                case .up:
                    state.moveSelectionUp()
                case .left:
                    if state.mode == .emojiPicker { state.emojiPicker.moveLeft() }
                case .right:
                    if state.mode == .emojiPicker { state.emojiPicker.moveRight() }
                default:
                    break
                }
            }
            .onExitCommand {
                if state.handleEscape() == false {
                    dismiss()
                }
            }
    }

    private var shellChrome: some View {
        ZStack {
            if nativeGlassEnabled == false {
                FoundrySmoothedRectangle(cornerRadius: FoundryTheme.Radius.panel, smoothing: 0.75)
                    .strokeBorder(
                        LinearGradient(
                            colors: [Color.primary.opacity(0.20), Color.primary.opacity(0.08), Color.primary.opacity(0.03)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
            FoundrySmoothedRectangle(cornerRadius: FoundryTheme.Radius.panel, smoothing: 0.75)
                .strokeBorder(innerHighlight, lineWidth: 0.5)
        }
        .allowsHitTesting(false)
    }

    private var innerHighlight: Color {
        colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.06)
    }

    private func replayPresentation() {
        presented = false
        DispatchQueue.main.async {
            withAnimation(.spring(response: 0.22, dampingFraction: 0.9)) {
                presented = true
            }
        }
    }

    private var surface: FeatureSurface {
        switch state.mode {
        case .agents:
            FeatureSurface(
                id: "agents",
                header: { FeatureTitle(symbol: "sparkles.rectangle.stack", title: "Agents") },
                content: { AgentShelfView(agents: state.agents, dismiss: dismiss) },
                footerActions: [.init(label: "Open", keys: "Click", emphasized: true), .home]
            )
        case .quickAI:
            FeatureSurface(
                id: "quickAI",
                header: {
                    QuickAIHeaderControlsView(quickAI: state.quickAI, inputFocused: $inputFocused) {
                        state.openQuickAI()
                    }
                },
                content: { QuickAISurfaceView(quickAI: state.quickAI, onOpenAISettings: state.openSettings) },
                footerActions: state.quickAI.isQuickAILoading
                    ? [.init(label: "Stop", keys: "⌘.", emphasized: true), .init(label: "New Chat", keys: "⌘N"), .home]
                    : [.init(label: "Send", keys: "↵", emphasized: true), .init(label: "New Chat", keys: "⌘N"), .home]
            )
        case .emojiPicker:
            FeatureSurface(
                id: "emoji",
                header: {
                    featureSearchField("Search emoji and symbols…", text: emojiQueryBinding) {
                        if state.emojiPicker.copySelectedEmoji() { dismiss() }
                    }
                },
                content: {
                    EmojiPickerView(state: state.emojiPicker) {
                        if state.emojiPicker.copySelectedEmoji() { dismiss() }
                    }
                },
                footerActions: [
                    .init(label: "Copy", keys: "↵"),
                    .init(label: "Tone \(state.emojiPicker.skinTone.isEmpty ? "·" : state.emojiPicker.skinTone)", keys: "⌘T"),
                    .home
                ]
            )
        case .fileConversion:
            FeatureSurface(
                id: "fileConversion",
                header: {
                    FeatureTitle(symbol: "arrow.triangle.2.circlepath",
                                 title: state.fileConversion.sourceURLs.count > 1 ? "Convert Files" : "Convert File")
                },
                content: { FileConversionView(state: state.fileConversion) },
                footerActions: [.init(label: "Convert", keys: "↵", emphasized: true), .home]
            )
        case .camera:
            FeatureSurface(
                id: "camera",
                header: { FeatureTitle(symbol: "camera", title: "Camera") },
                content: { CameraPreviewView(state: state.camera) },
                footerActions: [.home]
            )
        case .fileShelf:
            FeatureSurface(
                id: "shelf",
                header: { FeatureTitle(symbol: "tray.full", title: "File Shelf") },
                content: {
                    FileShelfView(state: state.fileShelf) { selectedFiles in
                        guard selectedFiles.isEmpty == false else { return }
                        state.fileConversion.setSources(urls: selectedFiles.map(\.url))
                        state.mode = .fileConversion
                    }
                },
                footerActions: [.init(label: "Remove", keys: "⌫"), .home]
            )
        case .clipboardHistory:
            FeatureSurface(
                id: "clipboard",
                header: {
                    featureSearchField("Search clipboard history…", text: clipboardQueryBinding) {
                        state.pasteOrCopySelectedClipboardItem()
                        dismiss()
                    }
                },
                content: {
                    ClipboardHistoryView(state: state.clipboardHistory, fileShelf: state.fileShelf, directPaste: {
                        let staged = state.directPasteSelectedClipboardItem()
                        if staged { dismiss() }
                        return staged
                    }, pause: state.setClipboardPaused)
                },
                footerActions: [.init(label: "Paste", keys: "↵", emphasized: true), .init(label: "Copy", keys: "⌘↵"), .init(label: "Pin", keys: "⌘P"), .home]
            )
        case .snippets:
            FeatureSurface(
                id: "snippets",
                header: {
                    HStack(spacing: 12) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(FoundryTheme.mutedText)
                        featureSearchField("Search snippets…", text: snippetsQueryBinding) {
                            if state.insertOrCopySelectedSnippet() { dismiss() }
                        }
                    }
                },
                content: {
                    ZStack {
                        SnippetsView(state: state.snippets, insert: {
                            guard state.insertOrCopySelectedSnippet() else { return false }
                            dismiss()
                            return true
                        })
                        if let names = state.pendingSnippetArguments {
                            SnippetArgumentPrompt(
                                names: names,
                                onCancel: state.cancelSnippetArguments,
                                onSubmit: { values in
                                    if state.submitSnippetArguments(values) { dismiss() }
                                }
                            )
                        }
                    }
                },
                footerActions: [.init(label: "Insert", keys: "↵", emphasized: true), .init(label: "Copy", keys: "⌘↵"), .home]
            )
        case .translator:
            FeatureSurface(
                id: "translator",
                header: { FeatureTitle(symbol: "globe", title: "Translate") },
                content: {
                    TranslatorView(state: state.translator, insert: {
                        guard state.insertTranslation() else { return false }
                        dismiss()
                        return true
                    })
                },
                footerActions: [.home]
            )
        case .developerTools:
            FeatureSurface(
                id: "developerTools",
                header: { FeatureTitle(symbol: "hammer", title: state.developerTools.selectedTool.rawValue) },
                content: { DeveloperToolsView(state: state.developerTools) },
                footerActions: [.init(label: "Copy Value", keys: "Click"), .home]
            )
        case .mediaDownloads:
            FeatureSurface(
                id: "mediaDownloads",
                header: { FeatureTitle(symbol: "arrow.down.circle", title: "Downloads") },
                content: {
                    MediaDownloadsView(
                        manager: state.mediaDownloads,
                        start: state.startMediaDownloads,
                        cancel: state.cancelDownload,
                        retry: state.retryDownload,
                        changeDestination: state.changeMediaDownloadFolder
                    )
                },
                footerActions: [.home]
            )
        case .settings:
            FeatureSurface(
                id: "settings",
                header: { FeatureTitle(symbol: "gearshape", title: "Settings") },
                content: { SettingsView(state: state) },
                footerActions: [.home]
            )
        case .search:
            FeatureSurface(
                id: searchContentID,
                header: { searchField },
                headerTrailing: { searchHeaderControls },
                content: { searchContent },
                footerActions: searchFooterActions
            )
        }
    }

    private func featureSearchField(_ placeholder: String, text: Binding<String>, onSubmit: @escaping () -> Void = {}) -> some View {
        TextField(placeholder, text: text)
            .textFieldStyle(.plain)
            .font(FoundryTheme.searchFont)
            .foregroundStyle(FoundryTheme.primaryText)
            .focused($inputFocused)
            .onSubmit(onSubmit)
    }

    private var searchField: some View {
        LauncherSearchField(
            text: state.isShowingActions ? $state.actionFilter : $state.query,
            placeholder: state.isShowingActions ? "Search actions…" : "Search for apps and commands…",
            onTab: {
                guard state.isShowingActions == false else { return }
                state.openQuickAI(initialPrompt: state.query)
            },
            onReturn: {
                executeSelectedResult()
            }
        )
        .frame(maxWidth: .infinity, alignment: .leading)
        .focused($inputFocused)
    }

    private var searchHeaderControls: some View {
        HStack(spacing: 6) {
            if state.query.isEmpty == false {
                FoundryIconButton(
                    systemName: "xmark.circle.fill",
                    accessibilityLabel: "Clear search",
                    tint: FoundryTheme.faintText
                ) {
                    state.query = ""
                    inputFocused = true
                }
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.7)))
            }

            Button {
                state.openQuickAI(initialPrompt: state.query)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 11, weight: .semibold))
                    Text("Ask AI")
                        .font(FoundryTheme.body(size: 12, weight: .semibold))
                    Text("Tab")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(FoundryTheme.faintText)
                }
                .foregroundStyle(FoundryTheme.secondaryText)
                .frame(height: 30)
                .padding(.horizontal, 8)
            }
            .buttonStyle(FoundryQuietButtonStyle())
            .pointerCursor()
            .accessibilityLabel("Ask AI")
            .help("Ask AI with Tab")

            if state.isActionInProgress {
                FoundryIconButton(
                    systemName: "xmark.circle.fill",
                    accessibilityLabel: "Cancel current action",
                    tint: FoundryTheme.faintText,
                    action: state.cancelCurrentAction
                )
                .help("Cancel current action")
            }
        }
        .zIndex(1)
        .padding(.leading, 6)
        .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .trailing)))
    }

    private var searchContentID: String {
        if state.isShowingActions { return "actions" }
        if state.results.isEmpty { return "empty" }
        return "results"
    }

    @ViewBuilder
    private var searchContent: some View {
        if isWindowLayoutQuery {
            windowLayoutSurface
        } else if state.results.isEmpty {
            searchEmptyState
        } else if FileSearchProvider.fileQuery(state.query) != nil, let id = state.selectedResult?.id, id.hasPrefix("file.") {
            SplitPreviewLayout {
                resultsSurface
            } preview: {
                FilePreview(path: String(id.dropFirst("file.".count)))
            }
        } else {
            resultsSurface
        }
    }

    @ViewBuilder
    private var searchEmptyState: some View {
        let hasQuery = trimmedQuery.isEmpty == false
        if let fileQuery = FileSearchProvider.fileQuery(state.query) {
            if fileQuery.count < 2 {
                EmptyState(title: "Search Files", message: "Type a file name to search your home folder.", symbol: "doc.text.magnifyingglass")
            } else if state.isSearchLoading {
                EmptyState(title: "Searching files", message: "Looking through your home folder with Spotlight.", isLoading: true)
            } else {
                EmptyState(title: "No files found", message: "No file names contain \u{201C}\(fileQuery)\u{201D}.", symbol: "doc.text.magnifyingglass")
            }
        } else if state.isHomeLoading && hasQuery == false {
            EmptyState(title: "Loading Home", message: "Preparing your recent apps and commands.", isLoading: true)
        } else if state.isSearchLoading {
            EmptyState(title: "Searching", message: "Looking through apps, commands, and files.", isLoading: true)
        } else {
            EmptyState(
                title: hasQuery ? "No results" : "Start typing",
                message: hasQuery
                    ? "Nothing matches \u{201C}\(trimmedQuery)\u{201D}."
                    : "Find apps, commands, emoji, system tools, and shelf actions.",
                symbol: hasQuery ? "magnifyingglass" : "command"
            )
        }
    }

    private var homeAccessoryStrip: some View {
        HomeAccessoryStrip(
            board: widgetBoard,
            agents: agents,
            fileShelf: fileShelf,
            onAgentOpen: state.openAgents,
            onShelfOpen: state.openFileShelf,
            compactMaximum: 4,
            compactBackground: false,
            compactHeight: 44
        )
        .padding(.horizontal, 10)
        .frame(height: 54)
        .background(Color.primary.opacity(0.032))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.horizontal, 16)
        .padding(.bottom, 4)
    }

    private var dropOverlay: some View {
        FoundrySmoothedRectangle(cornerRadius: FoundryTheme.Radius.panel, smoothing: 0.75)
            .fill(isDropTargeted ? Color.primary.opacity(0.10) : Color.clear)
            .overlay(
            FoundrySmoothedRectangle(cornerRadius: FoundryTheme.Radius.panel, smoothing: 0.75)
                    .strokeBorder(isDropTargeted ? Color.primary.opacity(0.45) : Color.clear, style: StrokeStyle(lineWidth: 1.5, dash: [8, 7]))
            )
            .overlay {
                if isDropTargeted {
                    VStack(spacing: 10) {
                        Image(systemName: "tray.and.arrow.down.fill")
                            .font(.system(size: 30, weight: .semibold))
                        Text("Drop to add to File Shelf")
                            .font(FoundryTheme.body(size: 15, weight: .semibold))
                    }
                    .foregroundStyle(FoundryTheme.primaryText)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 16)
                    .background(Color.black.opacity(0.18))
                    .clipShape(FoundrySmoothedRectangle(cornerRadius: 18, smoothing: 0.75))
                     .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.96)))
                }
            }
            .allowsHitTesting(false)
    }

    private func actionFeedbackColor(_ feedback: ActionFeedback) -> Color {
        switch feedback {
        case .info:
            FoundryTheme.secondaryText
        case .success:
            FoundryTheme.success
        case .failure:
            FoundryTheme.error
        }
    }

    private var resultsSurface: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: isHome ? 2 : 3) {
                    if let selectedCalculatorResult {
                        CalculatorResultCard(result: selectedCalculatorResult, alternatives: calculatorAlternativeResults) { result in
                            state.select(resultID: result.id)
                        }
                        .padding(.bottom, 18)

                        if displayedResults.isEmpty == false {
                            CalculatorUseWithHeader(query: state.query)
                                .padding(.bottom, 4)
                        } else {
                            CalculatorUseWithHeader(query: state.query)
                                .padding(.bottom, 4)
                            ForEach(calculatorFallbackResults, id: \.id) { result in
                                HomeResultRow(result: result, isSelected: false, label: resultKindLabel(for: result))
                                    .rowActivation(isSelected: false) { execute(result) }
                            }
                        }
                    }

                    if isHome {
                        if state.favoriteResults.isEmpty == false {
                            FavoritesRow(results: state.favoriteResults, onSelect: execute)
                                .padding(.bottom, 14)
                        }

                        if shouldShowLayoutRow {
                            WindowLayoutPicker(
                                results: homeLayoutResults,
                                onSelect: execute,
                                onMore: {
                                    state.query = "window"
                                    inputFocused = true
                                }
                            )
                            .padding(.bottom, 14)
                        }

                        if suggestionResults.isEmpty == false {
                            HomeSectionHeader(title: "Recent")
                            ForEach(Array(suggestionResults.prefix(5)), id: \.id) { result in
                                HomeResultRow(result: result, isSelected: state.selectedResultID == result.id, label: resultKindLabel(for: result))
                                    .id(result.id)
                                    .rowActivation(isSelected: state.selectedResultID == result.id) { execute(result) }
                            }
                        }

                        if commandResults.isEmpty == false {
                            HomeSectionHeader(title: "Commands")
                                .padding(.top, suggestionResults.isEmpty ? 0 : 12)
                            ForEach(Array(commandResults.prefix(5)), id: \.id) { result in
                                HomeResultRow(result: result, isSelected: state.selectedResultID == result.id, label: resultKindLabel(for: result))
                                    .id(result.id)
                                    .rowActivation(isSelected: state.selectedResultID == result.id) { execute(result) }
                            }
                        }

                    } else {
                        let sections = ResultSection.group(displayedResults)
                        ForEach(sections, id: \.section) { group in
                            if sections.count > 1 {
                                HomeSectionHeader(title: group.section.rawValue)
                                    .padding(.top, group.section == sections.first?.section ? 0 : 6)
                            }
                            ForEach(group.results, id: \.id) { result in
                                resultRow(result, showKind: sections.count > 1)
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, selectedCalculatorResult == nil ? 8 : 12)
            }
            .scrollIndicators(.never)
            .background(Color.clear)
            .onChange(of: state.selectionScrollToken) { _, _ in
                guard let resultID = state.selectedResultID else { return }
                proxy.scrollTo(resultID, anchor: .center)
            }
        }
    }

    private var displayedResults: [CommandResult] {
        var results = state.results
        if selectedCalculatorResult != nil {
            results = results.filter { $0.id != selectedCalculatorResult?.id && $0.id.hasPrefix("calculator.convert.") == false }
        }
        if state.mode == .search, state.fileShelf.files.isEmpty == false, state.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            results = results.filter { $0.id != "foundry.file-shelf" }
        }
        return results
    }

    private var calculatorAlternativeResults: [CommandResult] {
        guard let selectedCalculatorResult else { return [] }
        return state.results.filter { result in
            result.id.hasPrefix("calculator.convert.") && result.id != selectedCalculatorResult.id
        }
    }

    private var calculatorFallbackResults: [CommandResult] {
        [
            CommandResult(
                id: "calculator.fallback.clipboard",
                title: "Clipboard History",
                subtitle: "Search copied text, files, and images",
                icon: CommandIcon(fallback: "CB", systemName: "doc.on.clipboard"),
                primaryAction: CommandAction(id: "calculator.fallback.clipboard.open", title: "Open", kind: .openClipboardHistory),
                secondaryActions: []
            ),
            CommandResult(
                id: "calculator.fallback.fileshelf",
                title: "File Shelf",
                subtitle: "Hold files for quick actions",
                icon: CommandIcon(fallback: "FS", systemName: "tray.full"),
                primaryAction: CommandAction(id: "calculator.fallback.fileshelf.open", title: "Open", kind: .openFileShelf),
                secondaryActions: []
            ),
            CommandResult(
                id: "calculator.fallback.settings",
                title: "Open Foundry Settings",
                 subtitle: "Customize Home, commands, and Foundry preferences",
                icon: CommandIcon(fallback: "ST", systemName: "slider.horizontal.3"),
                primaryAction: CommandAction(id: "calculator.fallback.settings.open", title: "Open", kind: .openSettings),
                secondaryActions: []
            )
        ]
    }

    private var isWindowLayoutQuery: Bool {
        state.mode == .search && FoundryDomain.WindowLayoutQuery.isOverview(state.query)
    }

    private var windowLayoutSurface: some View {
        WindowLayoutManager(
            results: windowLayoutResults,
            selectedResultID: state.selectedResultID,
            isLoading: state.isSearchLoading,
            onSelect: execute,
            onHover: { result in
                state.select(resultID: result.id)
            }
        )
    }

    private var shouldExpandMediaResult: Bool {
        displayedResults.count == 1 && displayedResults.first.map(isMediaDownload) == true
    }

    private var suggestionResults: [CommandResult] {
        displayedResults.filter { result in
            if case .openApp = result.primaryAction.kind {
                return state.isSuggestibleApp(result)
            }
            return false
        }
    }

    private var commandResults: [CommandResult] {
        displayedResults.filter { result in
            if case .openApp = result.primaryAction.kind { return false }
            return isPrimaryWindowLayout(result) == false
        }
    }

    private var homeLayoutResults: [CommandResult] {
        let order: [FoundryDomain.WindowPlacement] = [.leftHalf, .rightHalf, .maximize, .center]
        return order.compactMap { placement in
            displayedResults.first { result in
                guard case let .tileWindow(resultPlacement) = result.primaryAction.kind else { return false }
                return resultPlacement == placement
            }
        }
    }

    private var shouldShowLayoutRow: Bool {
        homeLayoutResults.count > 1
            && homeLayoutResults.contains { state.hasUsage(for: $0.id) }
    }

    private var windowLayoutResults: [CommandResult] {
        let order: [FoundryDomain.WindowPlacement] = isWindowLayoutQuery
            ? FoundryDomain.WindowLayoutGroup.allCases.flatMap(\.placements)
            : FoundryDomain.WindowPlacement.homeDefaults
        return order.compactMap { placement in
            displayedResults.first { result in
                guard case let .tileWindow(resultPlacement) = result.primaryAction.kind else { return false }
                return resultPlacement == placement
            }
        }
    }

    private func isPrimaryWindowLayout(_ result: CommandResult) -> Bool {
        guard case let .tileWindow(placement) = result.primaryAction.kind else { return false }
        return [FoundryDomain.WindowPlacement.leftHalf, .rightHalf, .topHalf, .bottomHalf, .maximize, .restore].contains(placement)
    }

    private func isMediaDownload(_ result: CommandResult) -> Bool {
        if case .downloadMedia = result.primaryAction.kind { return true }
        return false
    }

    @ViewBuilder
    private func resultRow(_ result: CommandResult, showKind: Bool = false) -> some View {
        if isMediaDownload(result) {
            MediaResultRow(result: result, isSelected: state.selectedResultID == result.id, isExpanded: shouldExpandMediaResult)
                .id(result.id)
                .rowActivation(isSelected: state.selectedResultID == result.id) { execute(result) }
        } else {
            let preference = state.commandPreferences[result.id]
            ResultRow(
                result: result,
                isSelected: state.selectedResultID == result.id,
                alias: preference?.aliases.first,
                hotkey: preference?.globalHotkey?.displayName,
                isRunning: HomeSuggestionRules.appBundleIdentifier(resultID: result.id).map(state.runningAppBundleIDs.contains) ?? false,
                kindLabel: showKind ? resultKindLabel(for: result) : nil,
                compact: state.windowMode == .compact
            )
                .id(result.id)
                .rowActivation(isSelected: state.selectedResultID == result.id) { execute(result) }
        }
    }

    private func execute(_ result: CommandResult) {
        state.select(resultID: result.id)
        executeSelectedResult()
    }

    private func executeSelectedResult() {
        Task { @MainActor in
            if await state.executeSelectedResult() {
                dismiss()
            }
        }
    }

    private func resultKindLabel(for result: CommandResult) -> String {
        switch result.primaryAction.kind {
        case .openQuickAI:
            "AI"
        case .openApp:
            "Application"
        case .openEmojiPicker, .openFileShelf, .openClipboardHistory, .openSnippets, .openFileConverter, .openCamera, .openTranslator, .openDeveloperTools, .openConfigFolder, .openSettings, .openCommandSettings, .openWelcomeGuide, .openHome, .openMediaDownloads, .quit:
            "Command"
        case .openFileWithApp:
            "Application"
        case .copyToClipboard, .copySnippet, .copyFile:
            "Copy"
        case .deleteSnippet, .deleteQuicklink:
            "Delete"
        case .addToFileShelf:
            "File Shelf"
        case .pasteText, .pasteSnippet:
            "Insert"
        case .createSnippetFromClipboard, .importSnippets:
            "Snippet"
        case .downloadMedia, .downloadMediaBatch:
            "Download"
        case .chooseMediaDownloadFolder:
            "Folder"
        case .openURL, .openURLWithApp:
            result.id.hasPrefix("quicklink.") ? "Quicklink" : "URL"
        case .fillQuery:
            "Quicklink"
        case .terminateProcess, .quitApplication, .forceQuitApplication, .hideApplication, .quitAllApplications, .terminatePort, .toggleKeepAwake, .setAudioDevice, .rebuildApp:
            "Utility"
        case .resetRanking, .toggleFavorite:
            "Command"
        case .runProcess, .runScript:
            "Script"
        case .tileWindow:
            "Window"
        case .log:
            "Action"
        }
    }

    private var searchFooterActions: [FooterActionSpec] {
        if state.isShowingActions {
            return [.init(label: state.selectedAction?.title ?? "Run", keys: "↵", emphasized: true), .init(label: "Back", keys: "esc")]
        }
        let primary = FooterActionSpec(
            label: isWindowLayoutQuery ? "Apply" : (selectedCalculatorResult == nil ? "Open" : "Copy Answer"),
            keys: "↵",
            emphasized: true
        )
        return [primary, .actions]
    }

    private var actionsSurface: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("Actions")
                    .font(FoundryTheme.sectionHeaderFont)
                    .foregroundStyle(FoundryTheme.faintText)
                    .textCase(.uppercase)
                    .tracking(0.4)

                if let selectedResult = state.selectedResult {
                    Text(selectedResult.title)
                        .font(FoundryTheme.body(size: 12, weight: .regular))
                        .foregroundStyle(FoundryTheme.mutedText)
                        .lineLimit(1)
                }

                Spacer()
            }
            .padding(.horizontal, 20)
            .frame(height: 40)
            .background(Color.clear)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 2) {
                        if state.visibleActions.isEmpty {
                            Text("No actions match \u{201C}\(state.actionFilter)\u{201D}")
                                .font(FoundryTheme.body(size: 12, weight: .regular))
                                .foregroundStyle(FoundryTheme.mutedText)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 24)
                        }
                        ForEach(state.visibleActions, id: \.id) { action in
                            ActionRow(
                                action: action,
                                shortcut: action.id == state.selectedActions.first?.id ? "↵" : state.actionShortcuts[action.id]?.display,
                                isSelected: state.selectedActionID == action.id
                            )
                            .id(action.id)
                            .rowActivation(isSelected: state.selectedActionID == action.id) {
                                state.select(actionID: action.id)
                                executeSelectedResult()
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 8)
                }
                .scrollIndicators(.never)
                .background(Color.clear)
                .onChange(of: state.selectedActionID) { _, actionID in
                    guard let actionID else { return }
                    proxy.scrollTo(actionID, anchor: .center)
                }
            }
        }
    }

    private var trimmedQuery: String {
        state.query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @ViewBuilder
    private var panelFooter: some View {
        let actions = surface.footerActions
        if state.mode == .search, state.isSearchLoading {
            PanelFooter(actions: actions, openSettings: state.openSettings, openWelcomeGuide: state.openWelcomeGuide) {
                Text("Searching…")
                    .font(FoundryTheme.metaFont)
                    .foregroundStyle(FoundryTheme.mutedText)
            }
        } else if isWindowLayoutQuery {
            PanelFooter(actions: actions, openSettings: state.openSettings, openWelcomeGuide: state.openWelcomeGuide) {
                Text("\(windowLayoutResults.count) layouts")
                    .font(FoundryTheme.metaFont.monospacedDigit())
                    .foregroundStyle(FoundryTheme.faintText)
            }
        } else {
            PanelFooter(
                actions: actions,
                showsQuickAIChip: state.mode == .quickAI,
                openSettings: state.openSettings,
                openWelcomeGuide: state.openWelcomeGuide
            )
        }
    }

    private var emojiQueryBinding: Binding<String> {
        Binding(
            get: { state.emojiPicker.query },
            set: { state.emojiPicker.query = $0 }
        )
    }

    private var clipboardQueryBinding: Binding<String> {
        Binding(
            get: { state.clipboardHistory.query },
            set: { state.clipboardHistory.query = $0 }
        )
    }

    private var snippetsQueryBinding: Binding<String> {
        Binding(
            get: { state.snippets.query },
            set: { state.snippets.query = $0 }
        )
    }

    private func handleFileDrop(_ providers: [NSItemProvider]) -> Bool {
        let fileProviders = providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }
        guard fileProviders.isEmpty == false else { return false }

        Task { @MainActor in
            var urls: [URL] = []
            for provider in fileProviders {
                if let url = await loadFileURL(from: provider) {
                    urls.append(url)
                }
            }
            state.handleDroppedFiles(urls)
        }
        return true
    }

    private func loadFileURL(from provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                if let data = item as? Data {
                    continuation.resume(returning: URL(dataRepresentation: data, relativeTo: nil))
                } else {
                    continuation.resume(returning: item as? URL)
                }
            }
        }
    }

}

struct FoundrySmoothedRectangle: InsettableShape {
    var cornerRadius: CGFloat
    var smoothing: CGFloat = 0.75
    var insetAmount: CGFloat = 0

    func inset(by amount: CGFloat) -> some InsettableShape {
        var copy = self
        copy.insetAmount += amount
        return copy
    }

    func path(in rect: CGRect) -> Path {
        let rect = rect.insetBy(dx: insetAmount, dy: insetAmount)
        let radius = min(max(cornerRadius, 0), min(rect.width, rect.height) / 2)
        guard radius > 0 else { return Path(rect) }

        var path = Path()
        let exponent = 2 + (min(max(smoothing, 0), 1) * 2.5)
        let segments = 48

        path.move(to: CGPoint(x: rect.minX + radius, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
        addSuperellipseCorner(to: &path, center: CGPoint(x: rect.maxX - radius, y: rect.minY + radius), startAngle: -.pi / 2, exponent: exponent, radius: radius, segments: segments)
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
        addSuperellipseCorner(to: &path, center: CGPoint(x: rect.maxX - radius, y: rect.maxY - radius), startAngle: 0, exponent: exponent, radius: radius, segments: segments)
        path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
        addSuperellipseCorner(to: &path, center: CGPoint(x: rect.minX + radius, y: rect.maxY - radius), startAngle: .pi / 2, exponent: exponent, radius: radius, segments: segments)
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + radius))
        addSuperellipseCorner(to: &path, center: CGPoint(x: rect.minX + radius, y: rect.minY + radius), startAngle: .pi, exponent: exponent, radius: radius, segments: segments)
        path.closeSubpath()
        return path
    }

    private func addSuperellipseCorner(to path: inout Path, center: CGPoint, startAngle: CGFloat, exponent: CGFloat, radius: CGFloat, segments: Int) {
        for index in 1...segments {
            let angle = startAngle + (CGFloat(index) / CGFloat(segments) * .pi / 2)
            let x = copysign(pow(abs(cos(angle)), 2 / exponent), cos(angle)) * radius
            let y = copysign(pow(abs(sin(angle)), 2 / exponent), sin(angle)) * radius
            path.addLine(to: CGPoint(x: center.x + x, y: center.y + y))
        }
    }
}

private struct ActionRow: View {
    let action: CommandAction
    let shortcut: String?
    let isSelected: Bool

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.primary.opacity(0.07))
                .overlay(
                    Image(systemName: iconName)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(FoundryTheme.secondaryText)
                )
                .frame(width: 28, height: 28)
                .scaleEffect(isSelected ? 1.04 : 1)

            Text(action.title)
                .font(FoundryTheme.rowTitleFont)
                .foregroundStyle(FoundryTheme.primaryText)

            Spacer()

            if let shortcut {
                KeycapHint(text: shortcut)
                    .accessibilityLabel("Shortcut \(shortcut)")
            }
        }
        .padding(.horizontal, FoundryTheme.Spacing.sm)
        .frame(height: 40)
        .background(RowBackground(isSelected: isSelected, isHovering: isHovering))
        .onHover { hovering in
            isHovering = hovering
            if hovering { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
        }
    }

    private var iconName: String {
        switch action.kind {
        case .openQuickAI:
            "sparkles"
        case .openApp, .openURL, .openURLWithApp, .openConfigFolder:
            "arrow.up.right.square"
        case .openSettings, .openCommandSettings:
            "slider.horizontal.3"
        case .openFileWithApp:
            "arrow.up.right.square"
        case .openWelcomeGuide:
            "sparkles.rectangle.stack"
        case .fillQuery:
            "text.cursor"
        case .runScript:
            "terminal"
        case .openHome:
            "house"
        case .openMediaDownloads:
            "arrow.down.circle"
        case .copyToClipboard, .copySnippet, .copyFile:
            "doc.on.doc"
        case .deleteSnippet, .deleteQuicklink:
            "trash"
        case .addToFileShelf:
            "tray.and.arrow.down"
        case .pasteText, .pasteSnippet:
            "text.insert"
        case .createSnippetFromClipboard:
            "plus.rectangle.on.rectangle"
        case .importSnippets:
            "square.and.arrow.down"
        case .downloadMedia, .downloadMediaBatch:
            "arrow.down.circle"
        case .chooseMediaDownloadFolder:
            "folder.badge.gearshape"
        case .openEmojiPicker:
            "face.smiling"
        case .openFileShelf:
            "tray.full"
        case .openClipboardHistory:
            "doc.on.clipboard"
        case .openSnippets:
            "curlybraces"
        case .openFileConverter:
            "arrow.triangle.2.circlepath"
        case .openCamera:
            "camera"
        case .openTranslator:
            "globe"
        case .openDeveloperTools:
            "hammer"
        case .terminateProcess:
            "xmark.circle"
        case .quitApplication, .quitAllApplications:
            "app.badge.xmark"
        case .forceQuitApplication:
            "exclamationmark.octagon"
        case .hideApplication:
            "eye.slash"
        case .toggleKeepAwake:
            "cup.and.saucer.fill"
        case .terminatePort:
            "network"
        case .setAudioDevice:
            "speaker.wave.2.fill"
        case .resetRanking:
            "arrow.counterclockwise"
        case .toggleFavorite:
            "star"
        case .rebuildApp:
            "hammer.fill"
        case .runProcess:
            "terminal"
        case .tileWindow:
            "rectangle.split.2x1"
        case .quit:
            "power"
        case .log:
            "text.bubble"
        }
    }
}

private struct LauncherSearchField: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let onTab: () -> Void
    let onReturn: () -> Void

    func makeNSView(context: Context) -> LauncherSearchTextField {
        let field = LauncherSearchTextField()
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = NSFont.systemFont(ofSize: LauncherSearchTextField.maximumPointSize, weight: .regular)
        field.textColor = .labelColor
        field.placeholderString = placeholder
        field.cell?.usesSingleLineMode = true
        field.cell?.isScrollable = true
        field.delegate = context.coordinator
        field.onTab = onTab
        field.onReturn = onReturn
        return field
    }

    func updateNSView(_ nsView: LauncherSearchTextField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
        nsView.placeholderString = placeholder
        nsView.toolTip = text.isEmpty ? nil : text
        nsView.onTab = onTab
        nsView.onReturn = onReturn
        nsView.delegate = context.coordinator
        context.coordinator.text = $text
        context.coordinator.onTab = onTab
        context.coordinator.onReturn = onReturn
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onTab: onTab, onReturn: onReturn)
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var text: Binding<String>
        var onTab: (() -> Void)?
        var onReturn: (() -> Void)?

        init(text: Binding<String>, onTab: (() -> Void)? = nil, onReturn: (() -> Void)? = nil) {
            self.text = text
            self.onTab = onTab
            self.onReturn = onReturn
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            text.wrappedValue = field.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            switch commandSelector {
            case #selector(NSResponder.insertTab(_:)), #selector(NSResponder.insertBacktab(_:)):
                onTab?()
                return true
            case #selector(NSResponder.insertNewline(_:)), #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)):
                onReturn?()
                return true
            default:
                return false
            }
        }
    }
}

private final class LauncherSearchTextField: NSTextField {
    static let maximumPointSize: CGFloat = 20

    var onTab: (() -> Void)?
    var onReturn: (() -> Void)?

    override func layout() {
        super.layout()
        fitTextToWidth()
    }

    private func fitTextToWidth() {
        let maximumPointSize = LauncherSearchTextField.maximumPointSize
        let minimumPointSize: CGFloat = 12
        guard bounds.width > 0, stringValue.isEmpty == false else {
            if font?.pointSize != maximumPointSize {
                font = NSFont.systemFont(ofSize: maximumPointSize, weight: .regular)
            }
            return
        }

        let baseFont = NSFont.systemFont(ofSize: maximumPointSize, weight: .regular)
        let textWidth = (stringValue as NSString).size(withAttributes: [.font: baseFont]).width
        let pointSize = textWidth > bounds.width
            ? max(minimumPointSize, maximumPointSize * bounds.width / textWidth)
            : maximumPointSize
        guard abs((font?.pointSize ?? 0) - pointSize) > 0.1 else { return }
        font = NSFont.systemFont(ofSize: pointSize, weight: .regular)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.keyCode == 48 {
            onTab?()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 48:
            onTab?()
        case 36:
            onReturn?()
        default:
            super.keyDown(with: event)
        }
    }
}
