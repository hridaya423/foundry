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
    @Environment(\.foundryIncreaseContrast) private var increaseContrast
    @Environment(\.colorScheme) private var colorScheme
    @State private var isDropTargeted = false
    @State private var showsLoadingHairline = false
    @State private var visibleResultIDs: Set<String> = []
    /// Replayed on every open: the content settles from 97% (1.1's entrance).

    init(state: CommandPanelState, dismiss: @escaping () -> Void) {
        self.state = state
        self.dismiss = dismiss
        self.fileShelf = state.fileShelf
        self.agents = state.agents
        self.widgetBoard = state.widgetBoard
    }

    private var selectedCalculatorResult: CommandResult? {
        guard let selectedResult = state.session.selectedResult,
              PanelSession.isPromotedCalculatorResult(selectedResult) else { return nil }
        return selectedResult
    }

    private var homeNotice: String? {
        if state.showsLoginNudge { return String(localized: "Foundry won’t open after a restart. Start it at login?") }
        return state.showsWhatsNew ? WhatsNew.summary : state.tip?.text
    }

    private var isHome: Bool {
        state.mode == .search
            && state.session.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && selectedCalculatorResult == nil
            && state.session.isShowingActions == false
    }

    private var nativeGlassEnabled: Bool {
        FoundryMaterialPolicy.currentRendering(reduceTransparency: reduceTransparency) == .nativeGlass
    }

    private var shouldShowHomeAccessory: Bool {
        guard state.mode == .search,
              state.session.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        return fileShelf.files.isEmpty == false
            || agents.visibleSessions.isEmpty == false
            || widgetBoard.homeWidgets.contains { $0 != .agents }
    }

    var body: some View {
        let base = VStack(spacing: 0) {
            FeatureHeader(
                showBack: state.mode != .search,
                onBack: state.showHome,
                showsHairline: nativeGlassEnabled == false,
                content: { surfaceHeader },
                trailing: { surfaceHeaderTrailing }
            )
            .overlay(alignment: .bottom) {
                if showsLoadingHairline {
                    LoadingHairline()
                }
            }
            .task(id: state.mode == .search && (state.session.isSearchLoading || state.session.isHomeLoading)) {
                showsLoadingHairline = false
                guard state.mode == .search, state.session.isSearchLoading || state.session.isHomeLoading else { return }
                try? await Task.sleep(for: .milliseconds(150))
                guard Task.isCancelled == false else { return }
                showsLoadingHairline = true
            }

            if state.compactCollapsed == false {
                surfaceContent
                    .id(surfaceSpec.id)

                if state.mode == .search && trimmedQuery.isEmpty, let notice = homeNotice {
                    HStack(alignment: .center, spacing: 6) {
                        if state.showsLoginNudge {
                            InlineNotice(level: .info, text: LocalizedStringResource(stringLiteral: notice), symbol: "power",
                                actionTitle: "Turn On") { state.answerLoginNudge(turnOn: true) }
                        } else {
                            InlineNotice(level: .info, text: LocalizedStringResource(stringLiteral: notice),
                                symbol: state.showsWhatsNew ? "sparkles" : "lightbulb")
                        }
                        FoundryIconButton(systemName: "xmark", accessibilityLabel: String(localized: "Dismiss")) {
                            if state.showsLoginNudge {
                                state.answerLoginNudge(turnOn: false)
                            } else if state.showsWhatsNew {
                                state.dismissWhatsNew()
                            } else {
                                state.dismissTip()
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 6)
                }
                if shouldShowHomeAccessory {
                    homeAccessoryStrip
                }

                panelFooter
            }
        }

        let decorated = base
            .background(FoundryBackdrop(intensity: state.settings.themeIntensity, isOpaque: reduceTransparency))
            .overlay(shellChrome)
            .clipShape(FoundrySmoothedRectangle(cornerRadius: FoundryTheme.Radius.panel, smoothing: 0.75))
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        let highlighted = decorated
            .environment(\.foundryHoverHighlightsArmed, state.session.hoverHighlightsArmed)
            .overlay(dropOverlay)

        let feedbackWrapped = highlighted.overlay(alignment: Alignment.bottom) {
            if let actionFeedback = state.actionFeedback {
                FoundryGlassSurface(role: .floatingOverlay, shape: Capsule()) {
                    Label {
                        Text(actionFeedback.message)
                    } icon: {
                        Image(systemName: actionFeedback.symbolName)
                    }
                        .font(FoundryTheme.body)
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
                Group {
                    if state.session.isShowingActions {
                        FoundryGlassSurface(role: .floatingOverlay, shape: RoundedRectangle(cornerRadius: FoundryTheme.Radius.popover, style: .continuous)) {
                            actionsSurface
                                .frame(width: 340)
                                .frame(maxHeight: 320)
                        }
                        .shadow(color: FoundryTheme.shadow, radius: 24, y: 10)
                        .padding(.trailing, 12)
                        .padding(.bottom, 46)
                        .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: FoundryTheme.Motion.enterScale, anchor: .bottomTrailing)))
                    }
                }
                .animation(overlayAnimation(state.session.isShowingActions), value: state.session.isShowingActions)
            }
            .overlay(alignment: .bottom) {
                Group {
                    if let prompt = state.pendingPrompt {
                        FoundryGlassSurface(role: .floatingOverlay, shape: RoundedRectangle(cornerRadius: FoundryTheme.Radius.popover, style: .continuous)) {
                            PanelPromptOverlay(spec: prompt.spec) { result in
                                state.resolvePrompt(result)
                            }
                        }
                        .shadow(color: FoundryTheme.shadow, radius: 24, y: 10)
                        .padding(.bottom, 46)
                        .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: FoundryTheme.Motion.enterScale, anchor: .bottom)))
                    }
                }
                .animation(overlayAnimation(state.pendingPrompt != nil), value: state.pendingPrompt != nil)
            }
            .overlay(alignment: .bottom) {
                Group {
                    if state.pendingDropURLs != nil {
                        FoundryGlassSurface(role: .floatingOverlay, shape: RoundedRectangle(cornerRadius: FoundryTheme.Radius.popover, style: .continuous)) {
                            dropChooserSurface
                                .frame(width: 340)
                        }
                        .shadow(color: FoundryTheme.shadow, radius: 24, y: 10)
                        .padding(.bottom, 46)
                        .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: FoundryTheme.Motion.enterScale, anchor: .bottom)))
                    }
                }
                .animation(overlayAnimation(state.pendingDropURLs != nil), value: state.pendingDropURLs != nil)
            }
            .overlay(ConfettiBurst(trigger: state.confettiBurstID))

        return animated
            .onChange(of: state.mode) { _, _ in
                inputFocused = true
            }
            .onChange(of: state.session.focusToken) { _, _ in
                inputFocused = true
            }
            .onChange(of: state.session.results) { _, _ in
                // Fires when the commit carrying the new rows reaches the
                // render server — the closest readable signal to first paint.
                CATransaction.setCompletionBlock { [state] in
                    state.diagnostics.mark("results.paintCommitted")
                }
            }
            .onChange(of: state.compactCollapsed) { _, collapsed in
                state.shell?.compactCollapseChanged(collapsed)
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
            if needsVisibleBorder {
                FoundrySmoothedRectangle(cornerRadius: FoundryTheme.Radius.panel, smoothing: 0.75)
                    .strokeBorder(borderStroke, lineWidth: 1)
            }
            FoundrySmoothedRectangle(cornerRadius: FoundryTheme.Radius.panel, smoothing: 0.75)
                .strokeBorder(innerHighlight, lineWidth: 0.5)
        }
        .allowsHitTesting(false)
    }

    private var needsVisibleBorder: Bool {
        nativeGlassEnabled == false || increaseContrast
    }

    private var borderStroke: AnyShapeStyle {
        if reduceTransparency || increaseContrast {
            AnyShapeStyle(Color(nsColor: .separatorColor))
        } else {
            AnyShapeStyle(LinearGradient(
                colors: [FoundryTheme.stroke, FoundryTheme.fillTint, FoundryTheme.fillSubtle],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ))
        }
    }

    private func overlayAnimation(_ shown: Bool) -> Animation? {
        reduceMotion ? nil : (shown ? FoundryTheme.Motion.overlayIn : FoundryTheme.Motion.overlayOut)
    }

    private var innerHighlight: Color {
        colorScheme == .dark ? FoundryTheme.onDarkFaint : FoundryTheme.dark(0.06)
    }

    /// Per-mode metadata that isn't a view: the transition identity and the
    /// footer's action hints.
    private var surfaceSpec: (id: String, actions: [FooterActionSpec]) {
        switch state.mode {
        case .agents:
            (id: "agents",
             actions: [.init(label: "Open", keys: "Click", emphasized: true), .home])
        case .quickAI:
            (id: "quickAI",
             actions: state.quickAI.isQuickAILoading
                ? [.init(label: "Stop", keys: "⌘.", emphasized: true), .init(label: "New Chat", keys: "⌘N"), .home]
                : [.init(label: "Send", keys: "↵", emphasized: true), .init(label: "New Chat", keys: "⌘N"), .home])
        case .emojiPicker:
            (id: "emoji",
             actions: [
                .init(label: "Copy", keys: "↵"),
                .init(label: "Skin Tone \(state.emojiPicker.skinTone)", keys: "⌘T"),
                .home,
             ])
        case .fileConversion:
            (id: "fileConversion",
             actions: [.init(label: "Convert", keys: "↵", emphasized: true), .home])
        case .camera:
            (id: "camera", actions: [.home])
        case .fileShelf:
            (id: "shelf",
             actions: [.init(label: "Open", keys: "↵", emphasized: true), .actions])
        case .clipboardHistory:
            (id: "clipboard",
             actions: [
                .init(label: "Paste", keys: "↵", emphasized: true),
                .init(label: "Copy", keys: "⌘↵"),
                .actions,
             ])
        case .snippets:
            (id: "snippets",
             actions: [.init(label: "Insert", keys: "↵", emphasized: true), .init(label: "Copy", keys: "⌘↵"), .actions])
        case .translator:
            (id: "translator",
             actions: [.init(label: "Replace", keys: "⌘↵", emphasized: true), .init(label: "Copy", keys: "⇧⌘C"),
                .init(label: "Swap", keys: "⌘S"), .home])
        case .developerTools:
            (id: "developerTools",
             actions: [.init(label: "Copy Value", keys: "Click"), .home])
        case .mediaDownloads:
            (id: "mediaDownloads", actions: [.home])
        case .scriptOutput:
            (id: "scriptOutput", actions: [.init(label: "Copy Output", keys: "⌘↵", emphasized: true), .home])
        case .search:
            (id: searchContentID, actions: state.searchFooterActions(isWindowLayoutQuery: isWindowLayoutQuery))
        }
    }

    @ViewBuilder
    private var surfaceHeader: some View {
        switch state.mode {
        case .agents:
            FeatureTitle(symbol: "sparkles.rectangle.stack", title: "Agents")
        case .quickAI:
            QuickAIHeaderControlsView(quickAI: state.quickAI, inputFocused: $inputFocused) {
                state.router.openQuickAI()
            }
        case .emojiPicker:
            HStack(spacing: 8) {
                featureSearchField("Search emoji and symbols…", text: emojiQueryBinding) {
                    if state.emojiPicker.copySelectedEmoji() { dismiss() }
                }
                EmojiSkinToneMenu(state: state.emojiPicker)
            }
        case .fileConversion:
            FeatureTitle(symbol: "arrow.triangle.2.circlepath",
                         title: state.fileConversion.sourceURLs.count > 1 ? "Convert Files" : "Convert File")
        case .camera:
            FeatureTitle(symbol: "camera", title: "Camera")
        case .fileShelf:
            FeatureTitle(symbol: "tray.full", title: "File Shelf")
        case .clipboardHistory:
            featureSearchField("Search clipboard history…", text: clipboardQueryBinding) {
                if state.directPasteSelectedClipboardItem() { dismiss() }
            }
        case .snippets:
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .font(FoundryTheme.Glyph.sm)
                    .foregroundStyle(FoundryTheme.textTertiary)
                featureSearchField("Search snippets…", text: snippetsQueryBinding) {
                    if state.insertOrCopySelectedSnippet() { dismiss() }
                }
            }
        case .translator:
            FeatureTitle(symbol: "globe", title: "Translate")
        case .developerTools:
            FeatureTitle(symbol: "hammer", title: LocalizedStringResource("\(state.developerTools.selectedTool.rawValue)"))
        case .mediaDownloads:
            FeatureTitle(symbol: "arrow.down.circle", title: "Downloads")
        case .scriptOutput:
            FeatureTitle(symbol: "terminal", title: LocalizedStringResource(stringLiteral: state.scriptOutput?.title ?? "Script Output"))
        case .search:
            searchField
        }
    }

    @ViewBuilder
    private var surfaceHeaderTrailing: some View {
        switch state.mode {
        case .search: searchHeaderControls
        default: EmptyView()
        }
    }

    @ViewBuilder
    private var surfaceContent: some View {
        switch state.mode {
        case .agents:
            AgentShelfView(agents: state.agents, dismiss: dismiss)
        case .quickAI:
            QuickAISurfaceView(quickAI: state.quickAI, aiSettings: state.aiSettings, onOpenAISettings: { state.presentSettings(.ai) })
        case .emojiPicker:
            EmojiPickerView(state: state.emojiPicker) {
                if state.emojiPicker.copySelectedEmoji() { dismiss() }
            }
        case .fileConversion:
            FileConversionView(state: state.fileConversion)
        case .camera:
            CameraPreviewView(state: state.camera)
        case .fileShelf:
            FileShelfView(state: state.fileShelf, convertSelected: { selectedFiles in
                guard selectedFiles.isEmpty == false else { return }
                state.fileConversion.setSources(urls: selectedFiles.map(\.url))
                state.mode = .fileConversion
            }, extractText: state.extractTextFromShelfFile, decodeBarcode: state.decodeBarcodeFromShelfFile)
        case .clipboardHistory:
            ClipboardHistoryView(state: state.clipboardHistory, fileShelf: state.fileShelf, directPaste: {
                let staged = state.directPasteSelectedClipboardItem()
                if staged { dismiss() }
                return staged
            }, pause: state.settings.setClipboardPaused,
                extractText: state.extractTextFromClipboardItem,
                decodeBarcode: state.decodeBarcodeFromClipboardItem)
        case .snippets:
            ZStack {
                SnippetsView(state: state.snippets, expansionEnabled: state.settings.snippetExpansion.isEnabled,
                    setExpansionEnabled: { state.settings.setSnippetExpansionEnabled($0) }, insert: {
                    guard state.insertOrCopySelectedSnippet() else { return false }
                    dismiss()
                    return true
                }, copy: state.copySelectedSnippet)
                if let request = state.pendingSnippetArguments {
                    SnippetArgumentPrompt(
                        names: request.names,
                        onCancel: state.cancelSnippetArguments,
                        onSubmit: { values in
                            if state.submitSnippetArguments(values) { dismiss() }
                        }
                    )
                }
            }
        case .translator:
            TranslatorView(state: state.translator, insert: {
                guard state.insertTranslation() else { return false }
                dismiss()
                return true
            })
        case .developerTools:
            DeveloperToolsView(state: state.developerTools)
        case .mediaDownloads:
            MediaDownloadsView(
                manager: state.mediaDownloads,
                start: state.startMediaDownloads,
                cancel: state.cancelDownload,
                retry: state.retryDownload,
                changeDestination: state.changeMediaDownloadFolder,
                performHaptic: { state.performHaptic(.levelChange) }
            )
        case .scriptOutput:
            ScrollView {
                Text(state.scriptOutput.map { $0.text.isEmpty ? String(localized: "The script printed nothing.") : $0.text } ?? "")
                    .font(FoundryTheme.mono)
                    .foregroundStyle(state.scriptOutput?.text.isEmpty == false ? FoundryTheme.textPrimary : FoundryTheme.textTertiary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
            }
        case .search:
            searchContent
        }
    }

    private func featureSearchField(_ placeholder: String, text: Binding<String>, onSubmit: @escaping () -> Void = {}) -> some View {
        TextField(placeholder, text: text)
            .textFieldStyle(.plain)
            .font(FoundryTheme.title)
            .foregroundStyle(FoundryTheme.textPrimary)
            .focused($inputFocused)
            .onSubmit {
                if state.runSelectedFeatureAction() == false { onSubmit() }
            }
    }

    private var searchField: some View {
        LauncherSearchField(
            text: state.session.isShowingActions ? $state.session.actionFilter : $state.session.query,
            placeholder: state.session.isShowingActions ? "Search actions…" : state.searchHint ?? "Search for apps and commands…",
            onTab: {
                guard state.session.isShowingActions == false else { return }
                state.router.openQuickAI(initialPrompt: state.session.query)
            },
            onReturn: {
                executeSelectedResult()
            },
            onJump: { state.moveSelection($0) }
        )
        .frame(maxWidth: .infinity, alignment: .leading)
        .focused($inputFocused)
    }

    private var searchHeaderControls: some View {
        HStack(spacing: 6) {
            if state.session.query.isEmpty == false {
                FoundryIconButton(
                    systemName: "xmark.circle.fill",
                    accessibilityLabel: "Clear search",
                    tint: FoundryTheme.textQuaternary
                ) {
                    state.session.query = ""
                    inputFocused = true
                }
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.7)))
            }

            Button {
                state.router.openQuickAI(initialPrompt: state.session.query)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(FoundryTheme.Glyph.xs)
                    Text("Ask AI")
                        .font(FoundryTheme.body)
                    Text("Tab")
                        .font(FoundryTheme.Glyph.xs)
                        .foregroundStyle(FoundryTheme.textQuaternary)
                }
                .foregroundStyle(FoundryTheme.textSecondary)
                .frame(height: 30)
                .padding(.horizontal, 8)
            }
            .buttonStyle(FoundryQuietButtonStyle())
            .accessibilityLabel("Ask AI")
            .help("Ask AI with Tab")

            if state.isActionInProgress {
                FoundryIconButton(
                    systemName: "xmark.circle.fill",
                    accessibilityLabel: "Cancel current action",
                    tint: FoundryTheme.textQuaternary,
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
        if state.session.isShowingActions { return "actions" }
        if state.session.results.isEmpty { return "empty" }
        return "results"
    }

    @ViewBuilder
    private var searchContent: some View {
        if isWindowLayoutQuery {
            windowLayoutSurface
        } else if state.session.results.isEmpty {
            searchEmptyState
        } else if FileSearchProvider.fileQuery(state.session.query) != nil, case let .file(url)? = state.session.selectedResult?.payload {
            SplitPreviewLayout {
                resultsSurface
            } preview: {
                FilePreview(path: url.path)
            }
        } else if case let .snippet(snippetID)? = state.session.selectedResult?.payload,
                  let snippet = state.snippets.items.first(where: { $0.id == snippetID }) {
            SplitPreviewLayout {
                resultsSurface
            } preview: {
                SnippetPreview(snippet: snippet)
            }
        } else {
            resultsSurface
        }
    }

    @ViewBuilder
    private var searchEmptyState: some View {
        let hasQuery = trimmedQuery.isEmpty == false
        if let fileQuery = FileSearchProvider.fileQuery(state.session.query) {
            if state.session.isSearchLoading {
                Color.clear
            } else if fileQuery.isEmpty {
                FoundryEmptyState(symbol: "doc.text.magnifyingglass", title: "Search files",
                    message: "Type a file name. Add kind:image or kind:pdf to narrow it.")
            } else if fileQuery.count < 2 {
                FoundryEmptyState(symbol: "doc.text.magnifyingglass", title: "Search files", message: "Keep typing a file name.")
            } else {
                FoundryEmptyState(symbol: "doc.text.magnifyingglass", title: "No files found",
                    message: "No file names contain \u{201C}\(fileQuery)\u{201D}. Folders are set in Settings › File Search.")
            }
        } else if state.session.isHomeLoading && hasQuery == false {
            HomeSkeleton()
        } else if state.session.isSearchLoading {
            Color.clear
        } else if hasQuery {
            FoundryEmptyState(symbol: "magnifyingglass", title: "No results",
                message: "Nothing matches \u{201C}\(trimmedQuery)\u{201D}. Turn on fallbacks in Settings to search the web or ask AI.")
        } else {
            FoundryEmptyState(symbol: "command", title: "Start typing", message: "Find apps, commands, emoji, system tools, and shelf actions.")
        }
    }

    private var homeAccessoryStrip: some View {
        HomeAccessoryStrip(
            board: widgetBoard,
            agents: agents,
            fileShelf: fileShelf,
            onAgentOpen: state.router.openAgents,
            onShelfOpen: state.router.openFileShelf,
            compactMaximum: 4,
            compactBackground: false,
            compactHeight: 44
        )
        .padding(.horizontal, 10)
        .frame(height: 54)
        .background(FoundryTheme.fillSubtle)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .animation(reduceMotion ? nil : FoundryTheme.Motion.state, value: fileShelf.files.count)
        .animation(reduceMotion ? nil : FoundryTheme.Motion.state, value: agents.sessions.count)
    }

    private var dropOverlay: some View {
        FoundrySmoothedRectangle(cornerRadius: FoundryTheme.Radius.panel, smoothing: 0.75)
            .fill(isDropTargeted ? FoundryTheme.fillSelected : Color.clear)
            .overlay(
            FoundrySmoothedRectangle(cornerRadius: FoundryTheme.Radius.panel, smoothing: 0.75)
                    .strokeBorder(isDropTargeted ? FoundryTheme.textQuaternary : Color.clear, style: StrokeStyle(lineWidth: 1.5, dash: [8, 7]))
            )
            .overlay {
                if isDropTargeted {
                    VStack(spacing: 10) {
                        Image(systemName: "tray.and.arrow.down.fill")
                            .font(FoundryTheme.Glyph.xl)
                        Text("Drop files to choose what to do")
                            .font(FoundryTheme.body)
                    }
                    .foregroundStyle(FoundryTheme.textPrimary)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 16)
                    .background(FoundryTheme.scrim)
                    .clipShape(FoundrySmoothedRectangle(cornerRadius: 18, smoothing: 0.75))
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: FoundryTheme.Motion.enterScale)))
                }
            }
            .allowsHitTesting(false)
    }

    private func actionFeedbackColor(_ feedback: ActionFeedback) -> Color {
        switch feedback {
        case .info:
            FoundryTheme.textSecondary
        case .success:
            FoundryTheme.success
        case .failure:
            FoundryTheme.destructive
        }
    }

    private var resultsSurface: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: isHome ? 2 : 3) {
                    if let selectedCalculatorResult {
                        CalculatorResultCard(result: selectedCalculatorResult, alternatives: calculatorAlternativeResults) { result in
                            state.session.select(resultID: result.id)
                        }
                        .padding(.bottom, 18)

                        if displayedResults.isEmpty == false {
                            CalculatorUseWithHeader(query: state.session.query)
                                .padding(.bottom, 4)
                        } else {
                            CalculatorUseWithHeader(query: state.session.query)
                                .padding(.bottom, 4)
                            ForEach(calculatorFallbackResults, id: \.id) { result in
                                resultRow(result, showKind: true)
                            }
                        }
                    }

                    if isHome {
                        if state.session.favoriteResults.isEmpty == false {
                            FavoritesRow(results: state.session.favoriteResults, showsShortcuts: state.session.isCommandHeld, onSelect: execute)
                                .padding(.bottom, 14)
                        }

                        if shouldShowLayoutRow {
                            WindowLayoutPicker(
                                results: homeLayoutResults,
                                onSelect: execute,
                                onMore: {
                                    state.session.query = "window"
                                    inputFocused = true
                                }
                            )
                            .padding(.bottom, 14)
                        }

                        if suggestionResults.isEmpty == false {
                            HomeSectionHeader(title: "Recent")
                            ForEach(Array(suggestionResults.prefix(5)), id: \.id) { result in
                                resultRow(result, showKind: true)
                            }
                        }

                        if commandResults.isEmpty == false {
                            HomeSectionHeader(title: "Commands")
                                .padding(.top, suggestionResults.isEmpty ? 0 : 12)
                            ForEach(Array(commandResults.prefix(5)), id: \.id) { result in
                                resultRow(result, showKind: true)
                            }
                        }

                    } else {
                        // One ranked list — Raycast's root search is flat;
                        // kind is carried on the row, not by section headers
                        // that reorder whole buckets past better matches.
                        ForEach(displayedResults, id: \.id) { result in
                            resultRow(result, showKind: true)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, selectedCalculatorResult == nil ? 8 : 12)
            }
            .scrollIndicators(.never)
            .background(Color.clear)
            .onChange(of: state.session.selectionScrollToken) { _, _ in
                guard let resultID = state.session.selectedResultID else { return }
                // Minimal scroll: only move when the target left the
                // viewport, and only far enough to reveal it — not a
                // re-center on every arrow press.
                guard visibleResultIDs.contains(resultID) == false else { return }
                let order = state.session.navigableResults.map(\.id)
                let lastVisibleIndex = order.lastIndex(where: { visibleResultIDs.contains($0) }) ?? -1
                let targetIndex = order.firstIndex(of: resultID) ?? 0
                proxy.scrollTo(resultID, anchor: targetIndex > lastVisibleIndex ? .bottom : .top)
            }
        }
    }

    private var displayedResults: [CommandResult] {
        state.session.searchListResults
    }

    private var calculatorAlternativeResults: [CommandResult] {
        guard let selectedCalculatorResult else { return [] }
        return state.session.results.filter { result in
            result.payload.isCalculatorConversion && result.id != selectedCalculatorResult.id
        }
    }

    private var calculatorFallbackResults: [CommandResult] {
        PanelSession.calculatorFallbackResults
    }

    private var isWindowLayoutQuery: Bool {
        state.mode == .search && FoundryDomain.WindowLayoutQuery.isOverview(state.session.query)
    }

    private var windowLayoutSurface: some View {
        WindowLayoutManager(
            results: windowLayoutResults,
            selectedResultID: state.session.selectedResultID,
            isLoading: state.session.isSearchLoading,
            onSelect: execute,
            onHover: { result in
                state.session.select(resultID: result.id)
            }
        )
    }

    private var shouldExpandMediaResult: Bool {
        displayedResults.count == 1 && displayedResults.first.map(isMediaDownload) == true
    }

    private var suggestionResults: [CommandResult] {
        state.session.homeSections.suggestions
    }

    private var commandResults: [CommandResult] {
        state.session.homeSections.commands
    }

    private var homeLayoutResults: [CommandResult] {
        let order: [FoundryDomain.WindowPlacement] = [.leftHalf, .rightHalf, .maximize, .center]
        return order.compactMap { placement in
            displayedResults.first { result in
                guard let action = result.primaryAction.behavior as? TileWindowAction else { return false }
                return action.placement == placement
            }
        }
    }

    private var shouldShowLayoutRow: Bool {
        homeLayoutResults.count > 1
            && homeLayoutResults.contains { state.session.hasUsage(for: $0.id) }
    }

    private var windowLayoutResults: [CommandResult] {
        let order: [FoundryDomain.WindowPlacement] = isWindowLayoutQuery
            ? FoundryDomain.WindowLayoutGroup.allCases.flatMap(\.placements)
            : FoundryDomain.WindowPlacement.homeDefaults
        return order.compactMap { placement in
            displayedResults.first { result in
                guard let action = result.primaryAction.behavior as? TileWindowAction else { return false }
                return action.placement == placement
            }
        }
    }

    private func isMediaDownload(_ result: CommandResult) -> Bool {
        result.primaryAction.behavior is DownloadMediaAction
    }

    @ViewBuilder
    private func resultRow(_ result: CommandResult, showKind: Bool = false) -> some View {
        if isMediaDownload(result) {
            MediaResultRow(result: result, isSelected: state.session.selectedResultID == result.id, isExpanded: shouldExpandMediaResult)
                .id(result.id)
                .trackVisible(result.id, into: $visibleResultIDs)
                .rowActivation(isSelected: state.session.selectedResultID == result.id) { execute(result) }
        } else {
            let preference = state.settings.commandPreferences[result.id]
            ResultRow(
                result: result,
                isSelected: state.session.selectedResultID == result.id,
                alias: preference?.aliases.first,
                hotkey: preference?.globalHotkey?.displayName,
                isRunning: HomeSuggestionRules.appBundleIdentifier(payload: result.payload).map(state.session.runningAppBundleIDs.contains) ?? false,
                kindLabel: showKind ? resultKindLabel(for: result) : nil,
                compact: state.settings.windowMode == .compact
            )
                .id(result.id)
                .trackVisible(result.id, into: $visibleResultIDs)
                .rowActivation(isSelected: state.session.selectedResultID == result.id) { execute(result) }
        }
    }

    private func execute(_ result: CommandResult) {
        state.session.select(resultID: result.id)
        executeSelectedResult()
    }

    func executeSelectedResult() {
        // A pending prompt owns Return — the field's onSubmit or the
        // Confirm button's .defaultAction resolves it.
        guard state.pendingPrompt == nil else { return }
        Task { @MainActor in
            if await state.executeSelectedResult() {
                dismiss()
            }
        }
    }

    private func resultKindLabel(for result: CommandResult) -> String {
        // Kind labels describe what the result *is* (Raycast: "Application",
        // "File"), not what the default action does — the action title lives
        // in the footer.
        switch result.payload {
        case .quicklink: return "Quicklink"
        case .file: return "File"
        default: break
        }
        switch result.route {
        case .calculator: return "Calculation"
        case .translation: return "Translation"
        case .mediaDownload: return "Download"
        case .notesSearch: return "Note"
        case .aiResponse: return "AI"
        case .macUtility: return "System"
        case .browserTab: return "Tab"
        case .browserBookmark: return "Bookmark"
        case .browserHistory: return "History"
        case .developerTool: return "Developer Tool"
        case nil: break
        }
        return switch ResultSection.of(result) {
        case .applications: "Application"
        case .files: "File"
        case .notes: "Note"
        case .snippets: "Snippet"
        case .browser: "Browser"
        case .commands, .fallback: "Command"
        }
    }

    private var panelFooter: some View {
        PanelFooter(
            actions: surfaceSpec.actions,
            leadingAccessory: state.mode == .quickAI ? AnyView(QuickAIModelMenu(quickAI: state.quickAI, aiSettings: state.aiSettings,
                openAISettings: { state.presentSettings(.ai) })) : nil,
            openSettings: state.router.openSettings,
            openWelcomeGuide: state.router.openWelcomeGuide
        )
    }
}
