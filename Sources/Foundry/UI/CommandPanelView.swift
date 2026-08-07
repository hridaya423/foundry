import AppKit
import SwiftUI
import UniformTypeIdentifiers
import FoundryDomain

struct CommandPanelView: View {
    @ObservedObject var state: CommandPanelState
    let dismiss: () -> Void

    @FocusState private var inputFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var isDropTargeted = false

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
        return state.agents.visibleSessions.isEmpty == false || state.widgetBoard.homeWidgets.contains { $0 != .agents }
    }

    var body: some View {
        let base = VStack(spacing: 0) {
            header

            if shouldShowHomeAccessory {
                homeAccessoryStrip
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            contentSurface

            footer
        }

        let decorated = base
            .background(FoundryBackdrop(intensity: state.themeIntensity, isOpaque: reduceTransparency))
            .overlay(shellChrome)
            .clipShape(FoundrySmoothedRectangle(cornerRadius: 28, smoothing: 0.75))
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
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }

        let animated = feedbackWrapped
            .animation(reduceMotion ? nil : Animation.easeOut(duration: 0.14), value: state.mode)
            .animation(reduceMotion ? nil : Animation.easeOut(duration: 0.14), value: state.fileShelf.files.count)
            .animation(reduceMotion ? nil : Animation.easeOut(duration: 0.14), value: state.agents.sessions.count)

        return animated
            .onChange(of: state.mode) { _, _ in
                inputFocused = true
            }
            .onChange(of: state.focusToken) { _, _ in
                inputFocused = true
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
                    if state.mode == .clipboardHistory {
                        state.clipboardHistory.moveSelection(offset: 3)
                    } else {
                        state.moveSelectionDown()
                    }
                case .up:
                    if state.mode == .clipboardHistory {
                        state.clipboardHistory.moveSelection(offset: -3)
                    } else {
                        state.moveSelectionUp()
                    }
                case .left:
                    if state.mode == .emojiPicker { state.emojiPicker.moveLeft() }
                    if state.mode == .clipboardHistory { state.clipboardHistory.moveSelection(offset: -1) }
                case .right:
                    if state.mode == .emojiPicker { state.emojiPicker.moveRight() }
                    if state.mode == .clipboardHistory { state.clipboardHistory.moveSelection(offset: 1) }
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

    @ViewBuilder
    private var shellChrome: some View {
        if nativeGlassEnabled == false {
            FoundrySmoothedRectangle(cornerRadius: 28, smoothing: 0.75)
                .strokeBorder(
                    LinearGradient(
                        colors: [Color.white.opacity(0.20), Color.white.opacity(0.08), Color.white.opacity(0.03)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        }
    }

    @ViewBuilder
    private var contentSurface: some View {
        Group {
            if state.mode == .dashboard {
                dashboardSurface
            } else if state.mode == .agents {
                AgentShelfView(agents: state.agents, dismiss: dismiss)
            } else if state.mode == .settings {
                WidgetSettingsView(state: state)
            } else if state.mode == .quickAI {
                QuickAISurfaceView(quickAI: state.quickAI)
            } else if state.mode == .emojiPicker {
                EmojiPickerView(state: state.emojiPicker) {
                    if state.emojiPicker.copySelectedEmoji() {
                        dismiss()
                    }
                }
            } else if state.mode == .fileConversion {
                FileConversionView(state: state.fileConversion)
            } else if state.mode == .camera {
                CameraPreviewView(state: state.camera)
            } else if state.mode == .fileShelf {
                FileShelfView(state: state.fileShelf) { selectedFiles in
                    guard selectedFiles.isEmpty == false else { return }
                    state.fileConversion.setSources(urls: selectedFiles.map(\.url))
                    state.mode = .fileConversion
                }
            } else if state.mode == .clipboardHistory {
                ClipboardHistoryView(state: state.clipboardHistory, fileShelf: state.fileShelf)
            } else if state.mode == .snippets {
                SnippetsView(state: state.snippets)
            } else if state.mode == .translator {
                TranslatorView(state: state.translator)
            } else if state.mode == .developerTools {
                DeveloperToolsView(state: state.developerTools)
            } else if state.mode == .mediaDownloads {
                MediaDownloadsView(
                    manager: state.mediaDownloads,
                    start: state.startMediaDownloads,
                    cancel: state.cancelDownload,
                    retry: state.retryDownload
                )
            } else if state.isShowingActions {
                actionsSurface
            } else if state.results.isEmpty {
                emptyState
            } else {
                resultsSurface
            }
        }
        .id(contentID)
        .transition(.opacity.combined(with: .scale(scale: 0.985, anchor: .center)))
    }

    private var dashboardSurface: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Dashboard")
                        .font(FoundryTheme.body(size: 13, weight: .semibold))
                        .foregroundStyle(FoundryTheme.primaryText.opacity(0.72))

                    Spacer()

                    Button("Back to launcher") {
                        state.backToSearch()
                    }
                    .font(FoundryTheme.body(size: 12, weight: .medium))
                    .foregroundStyle(FoundryTheme.secondaryText)
                    .buttonStyle(FoundryQuietButtonStyle())
                    .pointerCursor()
                }
                .padding(.horizontal, 16)

                if state.fileShelf.files.isEmpty == false {
                    shelfStrip
                }

                if state.widgetBoard.homeWidgets.contains(where: { $0 != .agents }) || state.agents.sessions.isEmpty == false {
                    WidgetBoardView(board: state.widgetBoard, agents: state.agents)
                        .padding(.horizontal, 16)
                } else {
                    Text("Choose widgets in Settings to build your dashboard.")
                        .font(FoundryTheme.body(size: 12, weight: .regular))
                        .foregroundStyle(FoundryTheme.mutedText)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                }
            }
            .padding(.vertical, 12)
        }
        .scrollIndicators(.never)
    }

    private var homeAccessoryStrip: some View {
        WidgetBoardView(
            board: state.widgetBoard,
            agents: state.agents,
            onAgentOpen: state.openAgents,
            compact: true,
            compactMaximum: 4,
            compactBackground: false,
            compactHeight: 44
        )
        .padding(.horizontal, 10)
        .frame(height: 54)
        .background(Color.white.opacity(0.032))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.horizontal, 16)
        .padding(.bottom, 4)
    }

    private var shelfStrip: some View {
        Button {
            state.showFileShelf()
        } label: {
            HStack(spacing: 14) {
                ShelfIconStack(files: Array(state.fileShelf.files.prefix(3)))

                VStack(alignment: .leading, spacing: 4) {
                    Text("File Shelf")
                        .font(FoundryTheme.body(size: 16, weight: .semibold))
                        .foregroundStyle(FoundryTheme.primaryText)
                    Text(state.fileShelf.summary)
                        .font(FoundryTheme.body(size: 12, weight: .regular))
                        .foregroundStyle(FoundryTheme.secondaryText)
                }

                Spacer()

                HStack(spacing: 6) {
                    Text("Open")
                    Image(systemName: "arrow.right")
                        .font(.system(size: 11, weight: .semibold))
                }
                    .font(FoundryTheme.body(size: 12, weight: .semibold))
                    .foregroundStyle(FoundryTheme.secondaryText)
            }
            .padding(.horizontal, 18)
            .frame(height: 66)
            .background(Color.white.opacity(0.075))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
            .padding(.horizontal, 20)
            .padding(.top, 12)
        }
        .buttonStyle(PressableButtonStyle())
        .pointerCursor()
    }

    private var contentID: String {
        if state.mode == .settings { return "settings" }
        if state.mode == .agents { return "agents" }
        if state.mode == .dashboard { return "dashboard" }
        if state.mode == .quickAI { return "quickAI" }
        if state.mode == .emojiPicker { return "emoji" }
        if state.mode == .fileConversion { return "fileConversion" }
        if state.mode == .camera { return "camera" }
        if state.mode == .fileShelf { return "shelf" }
        if state.mode == .clipboardHistory { return "clipboard" }
        if state.mode == .snippets { return "snippets" }
        if state.mode == .translator { return "translator" }
         if state.mode == .developerTools { return "developerTools" }
        if state.mode == .mediaDownloads { return "mediaDownloads" }
        if state.isShowingActions { return "actions" }
        if state.results.isEmpty { return "empty" }
        return "results"
    }

    private var dropOverlay: some View {
        FoundrySmoothedRectangle(cornerRadius: 28, smoothing: 0.75)
            .fill(isDropTargeted ? Color.white.opacity(0.10) : Color.clear)
            .overlay(
            FoundrySmoothedRectangle(cornerRadius: 28, smoothing: 0.75)
                    .strokeBorder(isDropTargeted ? Color.white.opacity(0.45) : Color.clear, style: StrokeStyle(lineWidth: 1.5, dash: [8, 7]))
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
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
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

    private var header: some View {
        HStack(spacing: 12) {
            if state.mode != .search {
                FoundryIconButton(
                    systemName: "chevron.left",
                    accessibilityLabel: "Back to search",
                    action: state.backToSearch
                )
            }

            if state.mode == .quickAI {
                QuickAIHeaderControlsView(quickAI: state.quickAI, inputFocused: $inputFocused) {
                    state.openQuickAI(initialPrompt: state.query)
                }
              } else if state.mode == .settings {
                  Text("Settings")
                      .font(FoundryTheme.body(size: 18, weight: .semibold))
                      .foregroundStyle(FoundryTheme.primaryText)
             } else if state.mode == .dashboard {
                 Image(systemName: "rectangle.3.group")
                     .font(.system(size: 16, weight: .regular))
                     .foregroundStyle(FoundryTheme.mutedText)

                 Text("Dashboard")
                     .font(FoundryTheme.body(size: 21, weight: .regular))
                     .foregroundStyle(FoundryTheme.primaryText)
             } else if state.mode == .emojiPicker {
                TextField("Search emoji and symbols...", text: emojiQueryBinding)
                    .textFieldStyle(.plain)
                    .font(FoundryTheme.body(size: 21, weight: .regular))
                    .foregroundStyle(FoundryTheme.primaryText)
                    .focused($inputFocused)
                    .onSubmit {
                        if state.emojiPicker.copySelectedEmoji() {
                            dismiss()
                        }
                    }
            } else if state.mode == .fileConversion {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(FoundryTheme.mutedText)

                Text(state.fileConversion.sourceURLs.count > 1 ? "Convert Files" : "Convert File")
                    .font(FoundryTheme.body(size: 21, weight: .regular))
                    .foregroundStyle(FoundryTheme.primaryText)
            } else if state.mode == .camera {
                Image(systemName: "camera")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(FoundryTheme.mutedText)

                Text("Camera")
                    .font(FoundryTheme.body(size: 21, weight: .regular))
                    .foregroundStyle(FoundryTheme.primaryText)
            } else if state.mode == .fileShelf {
                Image(systemName: "tray.full")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(FoundryTheme.mutedText)

                Text("File Shelf")
                    .font(FoundryTheme.body(size: 21, weight: .regular))
                    .foregroundStyle(FoundryTheme.primaryText)
            } else if state.mode == .clipboardHistory {
                TextField("Search clipboard history...", text: clipboardQueryBinding)
                    .textFieldStyle(.plain)
                    .font(FoundryTheme.body(size: 21, weight: .regular))
                    .foregroundStyle(FoundryTheme.primaryText)
                    .focused($inputFocused)
                    .onSubmit {
                        state.clipboardHistory.copySelected()
                        dismiss()
                    }
            } else if state.mode == .snippets {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(FoundryTheme.mutedText)

                TextField("Search snippets...", text: snippetsQueryBinding)
                    .textFieldStyle(.plain)
                    .font(FoundryTheme.body(size: 21, weight: .regular))
                    .foregroundStyle(FoundryTheme.primaryText)
                    .focused($inputFocused)
            } else if state.mode == .translator {
                Image(systemName: "globe")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(FoundryTheme.mutedText)

                Text("Translate")
                    .font(FoundryTheme.body(size: 21, weight: .regular))
                    .foregroundStyle(FoundryTheme.primaryText)
             } else if state.mode == .developerTools {
                 Image(systemName: "hammer")
                     .font(.system(size: 16, weight: .regular))
                     .foregroundStyle(FoundryTheme.mutedText)

                 Text(state.developerTools.selectedTool.rawValue)
                     .font(FoundryTheme.body(size: 21, weight: .regular))
                     .foregroundStyle(FoundryTheme.primaryText)
            } else if state.mode == .mediaDownloads {
                Image(systemName: "arrow.down.circle")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(FoundryTheme.mutedText)

                Text("Downloads")
                    .font(FoundryTheme.body(size: 21, weight: .regular))
                    .foregroundStyle(FoundryTheme.primaryText)
            } else {
                LauncherSearchField(
                    text: $state.query,
                    placeholder: "Search for apps and commands...",
                    onTab: {
                        state.openQuickAI(initialPrompt: state.query)
                    },
                    onReturn: {
                        executeSelectedResult()
                    }
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                .focused($inputFocused)

                if state.mode == .search {
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
                            .transition(.opacity.combined(with: .scale(scale: 0.7)))
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

                    }
                    .zIndex(1)
                    .padding(.leading, 6)
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
                }

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
        }
        .animation(.easeOut(duration: 0.12), value: state.query.isEmpty)
        .padding(.horizontal, 22)
        .frame(height: state.mode == .settings ? 52 : 60)
        .background(Color.clear)
        .overlay(alignment: .bottom) {
            if nativeGlassEnabled == false {
                Rectangle()
                    .fill(Color.white.opacity(0.07))
                    .frame(height: 1)
            }
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
                                    .contentShape(Rectangle())
                                    .onTapGesture { execute(result) }
                            }
                        }
                    }

                    if isHome {
                        if suggestionResults.isEmpty == false {
                            HomeSectionHeader(title: "Suggestions")
                            ForEach(Array(suggestionResults.prefix(5)), id: \.id) { result in
                                HomeResultRow(result: result, isSelected: state.selectedResultID == result.id, label: resultKindLabel(for: result))
                                    .id(result.id)
                                    .contentShape(Rectangle())
                                    .onTapGesture { execute(result) }
                            }
                        }

                        if commandResults.isEmpty == false {
                            HomeSectionHeader(title: "Commands")
                                .padding(.top, suggestionResults.isEmpty ? 0 : 12)
                            ForEach(Array(commandResults.prefix(5)), id: \.id) { result in
                                HomeResultRow(result: result, isSelected: state.selectedResultID == result.id, label: resultKindLabel(for: result))
                                    .id(result.id)
                                    .contentShape(Rectangle())
                                    .onTapGesture { execute(result) }
                            }
                        }

                    } else {
                        ForEach(Array(displayedResults.enumerated()), id: \.element.id) { index, result in
                            resultRow(result, index: index)
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
                withAnimation(.easeOut(duration: 0.12)) {
                    proxy.scrollTo(resultID, anchor: .center)
                }
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
                subtitle: "Customize widgets and Foundry preferences",
                icon: CommandIcon(fallback: "ST", systemName: "slider.horizontal.3"),
                primaryAction: CommandAction(id: "calculator.fallback.settings.open", title: "Open", kind: .openSettings),
                secondaryActions: []
            )
        ]
    }

    private var shouldExpandMediaResult: Bool {
        displayedResults.count == 1 && displayedResults.first.map(isMediaDownload) == true
    }

    private var suggestionResults: [CommandResult] {
        displayedResults.filter { result in
            if case .openApp = result.primaryAction.kind { return true }
            return false
        }
    }

    private var commandResults: [CommandResult] {
        displayedResults.filter { result in
            if case .openApp = result.primaryAction.kind { return false }
            return true
        }
    }

    private func isMediaDownload(_ result: CommandResult) -> Bool {
        if case .downloadMedia = result.primaryAction.kind { return true }
        return false
    }

    @ViewBuilder
    private func resultRow(_ result: CommandResult, index: Int) -> some View {
        if isMediaDownload(result) {
            MediaResultRow(result: result, isSelected: state.selectedResultID == result.id, isExpanded: shouldExpandMediaResult)
                .id(result.id)
                .contentShape(Rectangle())
                .onTapGesture { execute(result) }
        } else {
            ResultRow(result: result, isSelected: state.selectedResultID == result.id, index: index)
                .id(result.id)
                .contentShape(Rectangle())
                .onTapGesture { execute(result) }
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
        case .openEmojiPicker, .openFileShelf, .openClipboardHistory, .openSnippets, .openFileConverter, .openCamera, .openTranslator, .openDeveloperTools, .openConfigFolder, .openSettings, .openDashboard, .openMediaDownloads, .quit:
            "Command"
        case .revealInFinder:
            "Finder"
        case .copyToClipboard:
            "Copy"
        case .pasteText:
            "Insert"
        case .createSnippetFromClipboard, .importSnippets:
            "Snippet"
        case .downloadMedia, .downloadMediaBatch:
            "Download"
        case .chooseMediaDownloadFolder:
            "Folder"
        case .openURL:
            "URL"
        case .terminateProcess, .quitApplication, .terminatePort, .toggleKeepAwake, .setAudioDevice, .rebuildApp:
            "Utility"
        case .resetRanking:
            "Command"
        case .runProcess:
            "Script"
        case .log:
            "Action"
        }
    }

    private var actionsSurface: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("Actions")
                    .font(FoundryTheme.body(size: 11, weight: .semibold))
                    .foregroundStyle(FoundryTheme.faintText)
                    .textCase(.uppercase)
                    .tracking(0.5)

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
                        ForEach(state.selectedActions, id: \.id) { action in
                            ActionRow(
                                action: action,
                                isSelected: state.selectedActionID == action.id
                            )
                            .id(action.id)
                            .contentShape(Rectangle())
                            .onTapGesture {
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
                    withAnimation(.easeOut(duration: 0.12)) {
                        proxy.scrollTo(actionID, anchor: .center)
                    }
                }
            }
        }
    }

    private var trimmedQuery: String {
        state.query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var emptyState: some View {
        let hasQuery = trimmedQuery.isEmpty == false
        return VStack(spacing: 14) {
            Spacer()

            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white.opacity(0.075))
                    .frame(width: 68, height: 68)

                Image(systemName: hasQuery ? "magnifyingglass" : "command")
                    .font(.system(size: 28, weight: .regular))
                    .foregroundStyle(FoundryTheme.secondaryText)
            }

            Text(hasQuery ? "No results" : "Start typing")
                .font(FoundryTheme.body(size: 17, weight: .medium))
                .foregroundStyle(FoundryTheme.primaryText)

            Text(hasQuery
                ? "Nothing matches \u{201C}\(trimmedQuery)\u{201D}."
                : "Find apps, commands, emoji, system tools, and shelf actions.")
                .font(FoundryTheme.body(size: 13, weight: .regular))
                .foregroundStyle(FoundryTheme.secondaryText)
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.horizontal, 40)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.clear)
    }

    private var footer: some View {
        HStack(spacing: 0) {
            if state.mode == .quickAI {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 11, weight: .semibold))
                    Text("Quick AI")
                        .font(FoundryTheme.body(size: 12, weight: .semibold))
                }
                .foregroundStyle(FoundryTheme.secondaryText)
                .padding(.horizontal, 8)
            } else if state.mode != .settings {
                settingsButton
            }

            if state.mode == .search, state.diagnosticsSummary.contains("result") {
                Text(state.diagnosticsSummary)
                    .font(FoundryTheme.body(size: 11, weight: .medium))
                    .foregroundStyle(FoundryTheme.faintText)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.horizontal, 12)
            }

            Spacer(minLength: 8)

            HStack(spacing: 10) {
                footerActions
            }
        }
        .padding(.horizontal, 16)
        .frame(height: state.mode == .settings ? 32 : 38)
    }

    private var settingsButton: some View {
        Button {
            state.openSettings()
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(FoundryTheme.secondaryText)
                .frame(width: 30, height: 30)
        }
        .buttonStyle(FoundryQuietButtonStyle())
        .pointerCursor()
        .accessibilityLabel("Open Settings (⌘,)")
        .help("Open Settings (⌘,)")
    }

    @ViewBuilder
    private var footerActions: some View {
        switch state.mode {
        case .quickAI:
            FooterAction(label: "Submit", keys: "↵", emphasized: true)
            FooterAction(label: "Close", keys: "esc")
        case .settings:
            FooterAction(label: "Done", keys: "esc")
        case .dashboard:
            FooterAction(label: "Open", keys: "↵", emphasized: true)
            FooterAction(label: "Close", keys: "esc")
        case .agents:
            FooterAction(label: "Open", keys: "Click", emphasized: true)
            FooterAction(label: "Close", keys: "esc")
        case .emojiPicker:
            FooterAction(label: "Copy", keys: "↵")
            FooterAction(label: "Close", keys: "esc")
        case .fileConversion:
            FooterAction(label: "Convert", keys: "↵", emphasized: true)
            FooterAction(label: "Close", keys: "esc")
        case .camera:
            FooterAction(label: "Close", keys: "esc")
        case .fileShelf:
            FooterAction(label: "Remove", keys: "⌫")
            FooterAction(label: "Close", keys: "esc")
        case .clipboardHistory:
            FooterAction(label: "Copy", keys: "↵", emphasized: true)
            FooterAction(label: "Remove", keys: "⌫")
            FooterAction(label: "Close", keys: "esc")
        case .snippets:
            FooterAction(label: "Copy", keys: "Click", emphasized: true)
            FooterAction(label: "Close", keys: "esc")
        case .translator:
            FooterAction(label: "Close", keys: "esc")
        case .developerTools:
            FooterAction(label: "Copy Value", keys: "Click")
            FooterAction(label: "Close", keys: "esc")
        case .mediaDownloads:
            FooterAction(label: "Close", keys: "esc")
        case .search:
            FooterAction(label: selectedCalculatorResult == nil ? "Open" : "Copy Answer", keys: "↵", emphasized: true)
            FooterAction(label: "Actions", keys: "⌘K")
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
        var didLoad = false
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            didLoad = true
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                let url: URL?
                if let data = item as? Data {
                    url = URL(dataRepresentation: data, relativeTo: nil)
                } else {
                    url = item as? URL
                }
                guard let url else { return }
                Task { @MainActor in
                    state.fileShelf.add(urls: [url])
                    state.showFileShelf()
                }
            }
        }
        return didLoad
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
    let isSelected: Bool

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.white.opacity(0.07))
                .overlay(
                    Image(systemName: iconName)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(FoundryTheme.secondaryText)
                )
                .frame(width: 28, height: 28)

            Text(action.title)
                .font(FoundryTheme.body(size: 14, weight: .medium))
                .foregroundStyle(FoundryTheme.primaryText)

            Spacer()
        }
        .padding(.horizontal, 12)
        .frame(height: 40)
        .background(RowBackground(isSelected: isSelected, isHovering: isHovering))
        .animation(.easeOut(duration: 0.12), value: isSelected)
        .animation(.easeOut(duration: 0.12), value: isHovering)
        .onHover { hovering in
            isHovering = hovering
            if hovering { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
        }
    }

    private var iconName: String {
        switch action.kind {
        case .openQuickAI:
            "sparkles"
        case .openApp, .openURL, .openConfigFolder:
            "arrow.up.right.square"
        case .openSettings:
            "slider.horizontal.3"
        case .openDashboard:
            "rectangle.3.group"
        case .openMediaDownloads:
            "arrow.down.circle"
        case .revealInFinder:
            "folder"
        case .copyToClipboard:
            "doc.on.doc"
        case .pasteText:
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
        case .quitApplication:
            "app.badge.xmark"
        case .toggleKeepAwake:
            "cup.and.saucer.fill"
        case .terminatePort:
            "network"
        case .setAudioDevice:
            "speaker.wave.2.fill"
        case .resetRanking:
            "arrow.counterclockwise"
        case .rebuildApp:
            "hammer.fill"
        case .runProcess:
            "terminal"
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
        field.font = NSFont.systemFont(ofSize: 21, weight: .regular)
        field.textColor = .white
        field.placeholderString = placeholder
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
        nsView.onTab = onTab
        nsView.onReturn = onReturn
        nsView.delegate = context.coordinator
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
    var onTab: (() -> Void)?
    var onReturn: (() -> Void)?

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

private struct KeycapHint: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .foregroundStyle(FoundryTheme.faintText)
            .padding(.horizontal, 2)
    }
}

private struct FooterAction: View {
    let label: String
    let keys: String
    var emphasized: Bool = false

    var body: some View {
        HStack(spacing: 6) {
            Text(label)
                .font(FoundryTheme.body(size: 11, weight: emphasized ? .semibold : .medium))
                .foregroundStyle(emphasized ? FoundryTheme.secondaryText : FoundryTheme.mutedText)

            KeycapHint(text: keys)
        }
    }
}
