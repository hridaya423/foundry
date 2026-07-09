import AppKit
import AVFoundation
import SwiftUI
import UniformTypeIdentifiers
#if canImport(Translation)
import Translation
#endif

struct CommandPanelView: View {
    @ObservedObject var state: CommandPanelState
    let dismiss: () -> Void

    @FocusState private var inputFocused: Bool
    @State private var isDropTargeted = false
    @State private var isShowingFoundryMenu = false

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

    var body: some View {
        VStack(spacing: 0) {
            header

            if state.mode == .search, state.isAgentShelfVisible, state.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, state.agents.sessions.isEmpty == false {
                agentShelfStrip
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if state.mode == .search, state.fileShelf.files.isEmpty == false {
                shelfStrip
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            contentSurface

            footer
        }
        .background(FoundryBackdrop())
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [Color.white.opacity(0.20), Color.white.opacity(0.08), Color.white.opacity(0.03)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: Color.black.opacity(0.5), radius: 40, x: 0, y: 24)
        .shadow(color: Color.black.opacity(0.28), radius: 8, x: 0, y: 4)
        .frame(width: 760, height: 500)
        .overlay {
            if isShowingFoundryMenu {
                foundryMenuOverlay
            }
        }
        .overlay(dropOverlay)
        .animation(.easeOut(duration: 0.14), value: state.mode)
        .animation(.easeOut(duration: 0.12), value: isShowingFoundryMenu)
        .animation(.easeOut(duration: 0.14), value: state.fileShelf.files.count)
        .animation(.easeOut(duration: 0.14), value: state.agents.sessions.count)
        .onChange(of: state.mode) { _, _ in
            isShowingFoundryMenu = false
        }
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted, perform: handleFileDrop)
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

    @ViewBuilder
    private var contentSurface: some View {
        Group {
            if state.mode == .settings {
                WidgetSettingsView(state: state)
            } else if state.mode == .activityMonitor {
                ActivityMonitorView(state: state.activityMonitor)
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
                FileShelfView(state: state.fileShelf) {
                    if let selectedFile = state.fileShelf.selectedFile {
                        state.fileConversion.setSource(url: selectedFile.url)
                        state.mode = .fileConversion
                    }
                }
            } else if state.mode == .clipboardHistory {
                ClipboardHistoryView(state: state.clipboardHistory, fileShelf: state.fileShelf)
            } else if state.mode == .snippets {
                SnippetsView(state: state.snippets)
            } else if state.mode == .translator {
                TranslatorView(state: state.translator)
            } else if state.mode == .developerTools {
                DeveloperToolsView(state: state.developerTools, close: state.backToSearch)
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

    private var contentID: String {
        if state.mode == .settings { return "settings" }
        if state.mode == .activityMonitor { return "activity" }
        if state.mode == .emojiPicker { return "emoji" }
        if state.mode == .fileConversion { return "fileConversion" }
        if state.mode == .camera { return "camera" }
        if state.mode == .fileShelf { return "shelf" }
        if state.mode == .clipboardHistory { return "clipboard" }
        if state.mode == .snippets { return "snippets" }
        if state.mode == .translator { return "translator" }
        if state.mode == .developerTools { return "developerTools" }
        if state.isShowingActions { return "actions" }
        if state.results.isEmpty { return "empty" }
        return "results"
    }

    private var dropOverlay: some View {
        RoundedRectangle(cornerRadius: 28, style: .continuous)
            .fill(isDropTargeted ? Color.white.opacity(0.10) : Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
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
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                }
            }
            .allowsHitTesting(false)
    }

    private var header: some View {
        HStack(spacing: 12) {
            if state.mode != .search {
                Button(action: state.backToSearch) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(FoundryTheme.secondaryText)
                        .frame(width: 30, height: 30)
                        .background(Color.white.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                }
                .buttonStyle(.plain)
                .pointerCursor()
            }

            if state.mode == .settings {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(FoundryTheme.mutedText)

                Text("Customize Widgets")
                    .font(FoundryTheme.body(size: 21, weight: .regular))
                    .foregroundStyle(FoundryTheme.primaryText)
            } else if state.mode == .activityMonitor {
                TextField("Filter processes...", text: activityQueryBinding)
                    .textFieldStyle(.plain)
                    .font(FoundryTheme.body(size: 21, weight: .regular))
                    .foregroundStyle(FoundryTheme.primaryText)
                    .focused($inputFocused)
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

                Text("Convert File")
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
                Image(systemName: "curlybraces")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(FoundryTheme.mutedText)

                Text("Snippets")
                    .font(FoundryTheme.body(size: 21, weight: .regular))
                    .foregroundStyle(FoundryTheme.primaryText)
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

                Text("Developer Tools")
                    .font(FoundryTheme.body(size: 21, weight: .regular))
                    .foregroundStyle(FoundryTheme.primaryText)
            } else {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(FoundryTheme.mutedText)

                TextField("Search apps and commands...", text: $state.query)
                    .textFieldStyle(.plain)
                    .font(FoundryTheme.body(size: 21, weight: .regular))
                    .foregroundStyle(FoundryTheme.primaryText)
                    .focused($inputFocused)
                    .onSubmit {
                        if state.executeSelectedResult() {
                            dismiss()
                        }
                    }

                if state.query.isEmpty == false {
                    Button {
                        state.query = ""
                        inputFocused = true
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16, weight: .regular))
                            .foregroundStyle(FoundryTheme.faintText)
                    }
                    .buttonStyle(PressableButtonStyle())
                    .pointerCursor()
                    .transition(.opacity.combined(with: .scale(scale: 0.7)))
                }
            }
        }
        .animation(.easeOut(duration: 0.12), value: state.query.isEmpty)
        .padding(.horizontal, 22)
        .frame(height: 60)
        .background(Color.clear)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.white.opacity(0.07))
                .frame(height: 1)
        }
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

    private var agentShelfStrip: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 7) {
                ForEach(state.agents.visibleSessions) { session in
                    AgentSessionCardView(session: session) {
                        state.agents.open(session)
                        dismiss()
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
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
                        if state.widgetBoard.homeWidgets.isEmpty == false {
                            WidgetBoardView(board: state.widgetBoard)
                                .padding(.horizontal, 4)
                                .padding(.bottom, 10)
                        }

                        if suggestionResults.isEmpty == false {
                            HomeSectionHeader(title: "Suggestions")
                            ForEach(Array(suggestionResults.prefix(3)), id: \.id) { result in
                                HomeResultRow(result: result, isSelected: state.selectedResultID == result.id, label: resultKindLabel(for: result))
                                    .id(result.id)
                                    .contentShape(Rectangle())
                                    .onTapGesture { execute(result) }
                            }
                        }

                        if commandResults.isEmpty == false {
                            HomeSectionHeader(title: "Commands")
                                .padding(.top, suggestionResults.isEmpty ? 0 : 12)
                            ForEach(Array(commandResults.prefix(3)), id: \.id) { result in
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
                .padding(.horizontal, 8)
                .padding(.vertical, selectedCalculatorResult == nil ? 8 : 12)
            }
            .scrollIndicators(.never)
            .background(Color.clear)
            .onChange(of: state.selectedResultID) { _, resultID in
                guard let resultID else { return }
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
                score: 0,
                primaryAction: CommandAction(id: "calculator.fallback.clipboard.open", title: "Open", kind: .openClipboardHistory),
                secondaryActions: []
            ),
            CommandResult(
                id: "calculator.fallback.fileshelf",
                title: "File Shelf",
                subtitle: "Hold files for quick actions",
                icon: CommandIcon(fallback: "FS", systemName: "tray.full"),
                score: 0,
                primaryAction: CommandAction(id: "calculator.fallback.fileshelf.open", title: "Open", kind: .openFileShelf),
                secondaryActions: []
            ),
            CommandResult(
                id: "calculator.fallback.settings",
                title: "Customize Widgets",
                subtitle: "Choose what appears on the home screen",
                icon: CommandIcon(fallback: "ST", systemName: "slider.horizontal.3"),
                score: 0,
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
        if state.executeSelectedResult() {
            dismiss()
        }
    }

    private func resultKindLabel(for result: CommandResult) -> String {
        switch result.primaryAction.kind {
        case .openApp:
            "Application"
        case .openEmojiPicker, .openFileShelf, .openClipboardHistory, .openSnippets, .openFileConverter, .openCamera, .openTranslator, .openDeveloperTools, .openActivityMonitor, .openConfigFolder, .openSettings, .quit:
            "Command"
        case .revealInFinder:
            "Finder"
        case .copyToClipboard:
            "Copy"
        case .pasteText:
            "Insert"
        case .createSnippetFromClipboard, .importSnippets:
            "Snippet"
        case .downloadMedia:
            "Download"
        case .chooseMediaDownloadFolder:
            "Folder"
        case .openURL:
            "URL"
        case .terminateProcess, .quitApplication, .terminatePort, .toggleKeepAwake, .setAudioDevice:
            "Utility"
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
                                if state.executeSelectedResult() {
                                    dismiss()
                                }
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
            foundryMenuButton

            if state.mode != .translator, state.diagnosticsSummary.isEmpty == false {
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
        .padding(.horizontal, 12)
        .frame(height: 44)
        .background(Color.black.opacity(0.08))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.white.opacity(0.06))
                .frame(height: 1)
        }
    }

    private var foundryMenuButton: some View {
        Button {
            isShowingFoundryMenu.toggle()
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "hammer.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(FoundryTheme.secondaryText)
                Text("Foundry")
                    .font(FoundryTheme.body(size: 12, weight: .semibold))
                    .foregroundStyle(FoundryTheme.secondaryText)
                Image(systemName: "chevron.up")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(FoundryTheme.faintText)
                    .rotationEffect(.degrees(isShowingFoundryMenu ? 180 : 0))
            }
            .padding(.horizontal, 8)
            .frame(height: 28)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(isShowingFoundryMenu ? 0.08 : 0))
            )
        }
        .buttonStyle(.plain)
        .pointerCursor()
    }

    private var foundryMenuOverlay: some View {
        ZStack(alignment: .bottomLeading) {
            Color.black.opacity(0.001)
                .contentShape(Rectangle())
                .onTapGesture { isShowingFoundryMenu = false }

            FoundryMenu(
                openSettings: {
                    isShowingFoundryMenu = false
                    state.openSettings()
                },
                quit: {
                    NSApp.terminate(nil)
                }
            )
            .padding(.leading, 12)
            .padding(.bottom, 50)
            .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .bottomLeading)))
        }
    }

    @ViewBuilder
    private var footerActions: some View {
        switch state.mode {
        case .settings:
            FooterAction(label: "Done", keys: "esc")
        case .activityMonitor:
            FooterAction(label: "Select", keys: "↑↓")
            FooterDivider()
            FooterAction(label: "Close", keys: "esc")
        case .emojiPicker:
            FooterAction(label: "Copy", keys: "↵")
            FooterDivider()
            FooterAction(label: "Close", keys: "esc")
        case .fileConversion:
            FooterAction(label: "Convert", keys: "↵", emphasized: true)
            FooterDivider()
            FooterAction(label: "Close", keys: "esc")
        case .camera:
            FooterAction(label: "Close", keys: "esc")
        case .fileShelf:
            FooterAction(label: "Remove", keys: "⌫")
            FooterDivider()
            FooterAction(label: "Close", keys: "esc")
        case .clipboardHistory:
            FooterAction(label: "Copy", keys: "↵", emphasized: true)
            FooterDivider()
            FooterAction(label: "Remove", keys: "⌫")
            FooterDivider()
            FooterAction(label: "Close", keys: "esc")
        case .snippets:
            FooterAction(label: "Copy", keys: "↵", emphasized: true)
            FooterDivider()
            FooterAction(label: "Close", keys: "esc")
        case .translator:
            FooterAction(label: "Close", keys: "esc")
        case .developerTools:
            FooterAction(label: "Copy Value", keys: "Click")
            FooterDivider()
            FooterAction(label: "Close", keys: "esc")
        case .search:
            FooterAction(label: selectedCalculatorResult == nil ? "Open" : "Copy Answer", keys: "↵", emphasized: true)
            FooterDivider()
            FooterAction(label: "Actions", keys: "⌘K")
        }
    }

    private var activityQueryBinding: Binding<String> {
        Binding(
            get: { state.activityMonitor.query },
            set: { state.activityMonitor.query = $0 }
        )
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

private struct FileShelfView: View {
    @ObservedObject var state: FileShelfState
    let convertSelected: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if state.files.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "tray.and.arrow.down")
                        .font(.system(size: 34, weight: .regular))
                        .foregroundStyle(FoundryTheme.secondaryText)
                    Text("Drop files anywhere on Foundry")
                        .font(FoundryTheme.body(size: 16, weight: .semibold))
                        .foregroundStyle(FoundryTheme.primaryText)
                    Text("They stay here temporarily until you remove them or quit.")
                        .font(FoundryTheme.body(size: 13, weight: .regular))
                        .foregroundStyle(FoundryTheme.secondaryText)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack {
                    Text("\(state.files.count) file\(state.files.count == 1 ? "" : "s") waiting")
                        .font(FoundryTheme.body(size: 11, weight: .semibold))
                        .foregroundStyle(FoundryTheme.faintText)
                        .textCase(.uppercase)
                        .tracking(0.5)
                    Spacer()
                    if state.selectedFile != nil {
                        Button("Convert") { convertSelected() }
                            .buttonStyle(PressableButtonStyle())
                            .font(FoundryTheme.body(size: 12, weight: .semibold))
                            .foregroundStyle(FoundryTheme.mutedText)
                            .pointerCursor()
                    }
                    Button("Clear") { state.clear() }
                        .buttonStyle(PressableButtonStyle())
                        .font(FoundryTheme.body(size: 12, weight: .semibold))
                        .foregroundStyle(FoundryTheme.mutedText)
                        .pointerCursor()
                }
                .padding(.horizontal, 4)

                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(state.files) { file in
                            FileShelfRow(
                                file: file,
                                isSelected: state.selectedID == file.id,
                                reveal: { NSWorkspace.shared.activateFileViewerSelecting([file.url]) },
                                remove: { state.remove(id: file.id) }
                            )
                            .id(file.id)
                            .contentShape(Rectangle())
                            .onTapGesture { state.select(id: file.id) }
                            .onDrag { NSItemProvider(object: file.url as NSURL) }
                        }
                    }
                }
                .scrollIndicators(.never)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 14)
    }
}

private struct FileShelfRow: View {
    let file: ShelfFile
    let isSelected: Bool
    let reveal: () -> Void
    let remove: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 12) {
            Image(nsImage: IconCache.shared.icon(forFile: file.url.path))
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text(file.name)
                    .font(FoundryTheme.body(size: 14, weight: .medium))
                    .foregroundStyle(FoundryTheme.primaryText)
                    .lineLimit(1)
                Text(file.location)
                    .font(FoundryTheme.body(size: 12, weight: .regular))
                    .foregroundStyle(FoundryTheme.mutedText)
                    .lineLimit(1)
            }

            Spacer()

            if isSelected || isHovering {
                Button(action: reveal) {
                    Image(systemName: "folder")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(FoundryTheme.mutedText)
                        .frame(width: 26, height: 26)
                        .background(Color.white.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                .buttonStyle(PressableButtonStyle())
                .pointerCursor()

                Button(action: remove) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(FoundryTheme.mutedText)
                        .frame(width: 26, height: 26)
                        .background(Color.white.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                .buttonStyle(PressableButtonStyle())
                .pointerCursor()
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 48)
        .background(RowBackground(isSelected: isSelected, isHovering: isHovering, cornerRadius: 10))
        .animation(.easeOut(duration: 0.10), value: isSelected)
        .animation(.easeOut(duration: 0.12), value: isHovering)
        .onHover { hovering in
            isHovering = hovering
            if hovering { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
        }
    }
}

private struct ShelfIconStack: View {
    let files: [ShelfFile]

    private var stackWidth: CGFloat {
        files.count <= 1 ? 40 : min(40 + CGFloat(files.count - 1) * 14, 70)
    }

    var body: some View {
        ZStack {
            ForEach(Array(files.enumerated()), id: \.element.id) { index, file in
                Image(nsImage: IconCache.shared.icon(forFile: file.url.path))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 34, height: 34)
                    .background(Color.white.opacity(0.16))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .rotationEffect(.degrees(Double(index - 1) * 5))
                    .offset(x: CGFloat(index) * 13)
            }
        }
        .frame(width: stackWidth, height: 42, alignment: .leading)
    }
}

private struct RowBackground: View {
    let isSelected: Bool
    let isHovering: Bool
    var cornerRadius: CGFloat = 9

    private var fill: Color {
        if isSelected { return FoundryTheme.selection }
        if isHovering { return FoundryTheme.hover }
        return Color.clear
    }

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(fill)
    }
}

private struct HomeSectionHeader: View {
    let title: String

    var body: some View {
        HStack {
            Text(title)
                .font(FoundryTheme.body(size: 11, weight: .semibold))
                .foregroundStyle(FoundryTheme.faintText)
                .textCase(.uppercase)
                .tracking(0.5)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.top, 4)
        .padding(.bottom, 4)
    }
}

private struct HomeResultRow: View {
    let result: CommandResult
    let isSelected: Bool
    let label: String

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 12) {
            AppIcon(icon: result.icon, size: 26, cornerRadius: 6)

            Text(result.title)
                .font(FoundryTheme.body(size: 14, weight: .medium))
                .foregroundStyle(FoundryTheme.primaryText)
                .lineLimit(1)

            Spacer()

            Text(label)
                .font(FoundryTheme.body(size: 12, weight: .regular))
                .foregroundStyle(FoundryTheme.faintText)
                .lineLimit(1)
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
}

private struct MediaResultRow: View {
    let result: CommandResult
    let isSelected: Bool
    var isExpanded = false

    @State private var isHovering = false

    var body: some View {
        HStack(alignment: isExpanded ? .top : .center, spacing: 16) {
            MediaThumbnail(icon: result.icon, isExpanded: isExpanded)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(result.title)
                        .font(FoundryTheme.body(size: isExpanded ? 20 : 15, weight: .semibold))
                        .foregroundStyle(FoundryTheme.primaryText)
                        .lineLimit(isExpanded ? 2 : 1)

                    Text("Download")
                        .font(FoundryTheme.body(size: 10, weight: .semibold))
                        .foregroundStyle(FoundryTheme.secondaryText)
                        .padding(.horizontal, 7)
                        .frame(height: 18)
                        .background(Color.white.opacity(0.08))
                        .clipShape(Capsule())
                }

                if let subtitle = result.subtitle {
                    Text(subtitle)
                        .font(FoundryTheme.body(size: isExpanded ? 14 : 12, weight: .regular))
                        .foregroundStyle(FoundryTheme.mutedText)
                        .lineLimit(isExpanded ? 3 : 2)
                }

                if isExpanded {
                    HStack(spacing: 8) {
                        Image(systemName: "folder")
                            .font(.system(size: 12, weight: .semibold))
                        Text(MediaDownloadDestination.folder.path)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .font(FoundryTheme.body(size: 12, weight: .medium))
                    .foregroundStyle(FoundryTheme.secondaryText)
                    .padding(.top, 10)

                    Text("Open Actions (⌘K) to change the folder.")
                        .font(FoundryTheme.body(size: 12, weight: .regular))
                        .foregroundStyle(FoundryTheme.faintText)
                }
            }

            Spacer()

            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(FoundryTheme.secondaryText)
        }
        .padding(.horizontal, isExpanded ? 20 : 12)
        .padding(.vertical, isExpanded ? 20 : 0)
        .frame(height: isExpanded ? 260 : 76)
        .background(RowBackground(isSelected: isSelected, isHovering: isHovering))
        .animation(.easeOut(duration: 0.12), value: isSelected)
        .animation(.easeOut(duration: 0.12), value: isHovering)
        .onHover { hovering in
            isHovering = hovering
            if hovering { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
        }
    }
}

private struct MediaThumbnail: View {
    let icon: CommandIcon
    var isExpanded = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.075))

            if let url = icon.thumbnailURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case let .success(image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        fallback
                    case .empty:
                        ProgressView()
                            .controlSize(.small)
                    @unknown default:
                        fallback
                    }
                }
            } else {
                fallback
            }
        }
        .frame(width: isExpanded ? 300 : 92, height: isExpanded ? 170 : 52)
        .clipShape(RoundedRectangle(cornerRadius: isExpanded ? 18 : 10, style: .continuous))
        .overlay(alignment: .center) {
            Circle()
                .fill(Color.black.opacity(0.34))
                .frame(width: isExpanded ? 44 : 24, height: isExpanded ? 44 : 24)
                .overlay(
                    Image(systemName: "play.fill")
                        .font(.system(size: isExpanded ? 17 : 10, weight: .bold))
                        .foregroundStyle(.white)
                        .offset(x: 1)
                )
        }
    }

    private var fallback: some View {
        Image(systemName: icon.systemName ?? "arrow.down.circle")
            .font(.system(size: 20, weight: .medium))
            .foregroundStyle(FoundryTheme.secondaryText)
    }
}

private struct ResultRow: View {
    let result: CommandResult
    let isSelected: Bool
    let index: Int

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 12) {
            AppIcon(icon: result.icon, size: 28, cornerRadius: 7)

            VStack(alignment: .leading, spacing: 2) {
                Text(result.title)
                    .font(FoundryTheme.body(size: 14, weight: .medium))
                    .foregroundStyle(FoundryTheme.primaryText)
                    .lineLimit(1)

                if let subtitle = result.subtitle {
                    Text(subtitle)
                        .font(FoundryTheme.body(size: 12, weight: .regular))
                        .foregroundStyle(FoundryTheme.mutedText)
                        .lineLimit(1)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .frame(height: result.subtitle == nil ? 40 : 46)
        .background(RowBackground(isSelected: isSelected, isHovering: isHovering))
        .animation(.easeOut(duration: 0.12), value: isSelected)
        .animation(.easeOut(duration: 0.12), value: isHovering)
        .onHover { hovering in
            isHovering = hovering
            if hovering { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
        }
    }
}

private struct ClipboardHistoryView: View {
    @ObservedObject var state: ClipboardHistoryState
    @ObservedObject var fileShelf: FileShelfState

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 3)

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if state.items.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "doc.on.clipboard")
                        .font(.system(size: 34, weight: .regular))
                        .foregroundStyle(FoundryTheme.secondaryText)
                    Text("Copy something to start history")
                        .font(FoundryTheme.body(size: 16, weight: .semibold))
                        .foregroundStyle(FoundryTheme.primaryText)
                    Text("Foundry keeps text, files, and images while it is running.")
                        .font(FoundryTheme.body(size: 13, weight: .regular))
                        .foregroundStyle(FoundryTheme.secondaryText)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack {
                    Text("\(state.visibleItems.count) item\(state.visibleItems.count == 1 ? "" : "s")")
                        .font(FoundryTheme.body(size: 11, weight: .semibold))
                        .foregroundStyle(FoundryTheme.faintText)
                        .textCase(.uppercase)
                        .tracking(0.5)
                    Spacer()
                    Button("Clear") { state.clear() }
                        .buttonStyle(PressableButtonStyle())
                        .font(FoundryTheme.body(size: 12, weight: .semibold))
                        .foregroundStyle(FoundryTheme.mutedText)
                        .pointerCursor()
                }
                .padding(.horizontal, 4)

                ScrollView {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
                        ForEach(state.visibleItems) { item in
                            ClipboardHistoryCard(
                                item: item,
                                isSelected: state.selectedID == item.id,
                                copy: { state.copySelected() },
                                remove: { state.select(id: item.id); state.removeSelected() },
                                addToShelf: { state.select(id: item.id); state.addSelectedFiles(to: fileShelf) }
                            )
                            .id(item.id)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                state.select(id: item.id)
                                state.copySelected()
                            }
                        }
                    }
                    .padding(.bottom, 6)
                }
                .scrollIndicators(.never)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 14)
    }
}

private struct SnippetsView: View {
    @ObservedObject var state: SnippetState

    var body: some View {
        HStack(spacing: 14) {
            sidebar
            detail
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text(state.visibleItems.count == 1 ? "1 SNIPPET" : "\(state.visibleItems.count) SNIPPETS")
                    .font(FoundryTheme.body(size: 11, weight: .semibold))
                    .foregroundStyle(FoundryTheme.faintText)
                    .tracking(0.6)
                    .padding(.leading, 11)
                Spacer()
                SnippetIconButton(symbol: "plus", help: "New snippet", action: state.newSnippet)
            }
            .frame(height: 30)

            if state.visibleItems.isEmpty {
                sidebarEmptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 3) {
                        ForEach(state.visibleItems) { snippet in
                            SnippetRow(
                                snippet: snippet,
                                subtitle: snippetSubtitle(snippet),
                                isSelected: state.selectedItem?.id == snippet.id,
                                select: { state.select(id: snippet.id) }
                            )
                        }
                    }
                    .padding(.bottom, 2)
                }
                .scrollIndicators(.never)
            }
        }
        .padding(16)
        .frame(width: 264)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .modifier(SnippetPanelSurface())
    }

    private var sidebarEmptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "curlybraces")
                .font(.system(size: 24, weight: .regular))
                .foregroundStyle(FoundryTheme.faintText)
            Text("No snippets yet")
                .font(FoundryTheme.body(size: 13, weight: .medium))
                .foregroundStyle(FoundryTheme.secondaryText)
            newSnippetButton
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }


    @ViewBuilder
    private var detail: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let selected = state.selectedItem {
                HStack(spacing: 4) {
                    Text("EDIT SNIPPET")
                        .font(FoundryTheme.body(size: 11, weight: .semibold))
                        .foregroundStyle(FoundryTheme.faintText)
                        .tracking(0.6)
                        .padding(.leading, 13)
                    Spacer()
                    SnippetIconButton(
                        symbol: selected.isPinned ? "pin.fill" : "pin",
                        help: selected.isPinned ? "Unpin" : "Pin",
                        tint: selected.isPinned ? FoundryTheme.primaryText : FoundryTheme.secondaryText,
                        action: state.togglePinnedSelected
                    )
                    SnippetIconButton(symbol: "doc.on.doc", help: "Copy to clipboard", action: state.copySelected)
                    SnippetIconButton(symbol: "trash", help: "Delete snippet", destructive: true, action: state.removeSelected)
                }
                .frame(height: 30)
                SnippetEditor(state: state)
            } else {
                detailEmptyState
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .modifier(SnippetPanelSurface())
    }

    private var detailEmptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "curlybraces.square")
                .font(.system(size: 30, weight: .regular))
                .foregroundStyle(FoundryTheme.faintText)
            VStack(spacing: 4) {
                Text("No snippet selected")
                    .font(FoundryTheme.body(size: 14, weight: .semibold))
                    .foregroundStyle(FoundryTheme.secondaryText)
                Text("Create a snippet or pick one from the list.")
                    .font(FoundryTheme.body(size: 12, weight: .regular))
                    .foregroundStyle(FoundryTheme.mutedText)
            }
            newSnippetButton
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var newSnippetButton: some View {
        Button(action: state.newSnippet) {
            HStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .bold))
                Text("New Snippet")
                    .font(FoundryTheme.body(size: 12.5, weight: .semibold))
            }
            .foregroundStyle(FoundryTheme.primaryText)
            .padding(.horizontal, 14)
            .frame(height: 32)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.white.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(PressableButtonStyle())
        .pointerCursor()
    }

    private func snippetSubtitle(_ snippet: StoredSnippet) -> String {
        let parts: [String?] = [
            snippet.keyword.isEmpty ? nil : snippet.keyword,
            snippet.tags.isEmpty ? nil : snippet.tags.map { "#\($0)" }.joined(separator: " "),
            relativeDate(snippet.updatedAt)
        ]
        return parts.compactMap { $0 }.joined(separator: "  •  ")
    }
}

private struct SnippetPanelSurface: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Color.white.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.07), lineWidth: 1)
            )
    }
}

private struct SnippetIconButton: View {
    let symbol: String
    var help: String = ""
    var tint: Color = FoundryTheme.secondaryText
    var destructive = false
    let action: () -> Void

    @State private var isHovering = false

    private var foreground: Color {
        if isHovering {
            return destructive ? Color(red: 1.0, green: 0.45, blue: 0.45) : FoundryTheme.primaryText
        }
        return tint
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(foreground)
                .frame(width: 30, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.white.opacity(isHovering ? 0.09 : 0))
                )
        }
        .buttonStyle(.plain)
        .help(help)
        .animation(.easeOut(duration: 0.12), value: isHovering)
        .onHover { hovering in
            isHovering = hovering
            if hovering { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
        }
    }
}

private struct SnippetRow: View {
    let snippet: StoredSnippet
    let subtitle: String
    let isSelected: Bool
    let select: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(snippet.title.isEmpty ? "Untitled Snippet" : snippet.title)
                        .font(FoundryTheme.body(size: 14, weight: .medium))
                        .foregroundStyle(FoundryTheme.primaryText)
                        .lineLimit(1)
                    if snippet.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(FoundryTheme.mutedText)
                    }
                }
                if subtitle.isEmpty == false {
                    Text(subtitle)
                        .font(FoundryTheme.body(size: 11.5, weight: .regular))
                        .foregroundStyle(FoundryTheme.mutedText)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 11)
        .frame(height: 48)
        .background(RowBackground(isSelected: isSelected, isHovering: isHovering, cornerRadius: 10))
        .contentShape(Rectangle())
        .onTapGesture(perform: select)
        .animation(.easeOut(duration: 0.10), value: isHovering)
        .onHover { hovering in
            isHovering = hovering
            if hovering { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
        }
    }
}

private struct SnippetEditor: View {
    @ObservedObject var state: SnippetState
    @State private var title = ""
    @State private var keyword = ""
    @State private var tags = ""
    @State private var content = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Snippet title", text: $title)
                .textFieldStyle(.plain)
                .font(FoundryTheme.body(size: 16, weight: .semibold))
                .foregroundStyle(FoundryTheme.primaryText)
                .padding(.horizontal, 13)
                .frame(height: 40)
                .background(fieldBackground)

            HStack(spacing: 10) {
                labeledField(icon: "number", placeholder: "Keyword", text: $keyword)
                labeledField(icon: "tag", placeholder: "Tags, comma separated", text: $tags)
            }

            ZStack(alignment: .topLeading) {
                if content.isEmpty {
                    Text("Write your snippet…")
                        .font(FoundryTheme.body(size: 13.5, weight: .regular))
                        .foregroundStyle(FoundryTheme.faintText)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $content)
                    .font(FoundryTheme.body(size: 13.5, weight: .regular))
                    .foregroundStyle(FoundryTheme.primaryText)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(fieldBackground)

            HStack(spacing: 6) {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 10, weight: .semibold))
                Text("{clipboard}  {date}  {time}  {cursor}  auto-expand when used")
                    .font(FoundryTheme.body(size: 11, weight: .regular))
            }
            .foregroundStyle(FoundryTheme.faintText)
            .padding(.leading, 2)
        }
        .onAppear { sync() }
        .onChange(of: state.selectedID) { _, _ in sync() }
        .onChange(of: title) { _, _ in persist() }
        .onChange(of: keyword) { _, _ in persist() }
        .onChange(of: tags) { _, _ in persist() }
        .onChange(of: content) { _, _ in persist() }
    }

    private func labeledField(icon: String, placeholder: String, text: Binding<String>) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(FoundryTheme.faintText)
            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .font(FoundryTheme.body(size: 13, weight: .medium))
                .foregroundStyle(FoundryTheme.primaryText)
        }
        .padding(.horizontal, 12)
        .frame(height: 36)
        .frame(maxWidth: .infinity)
        .background(fieldBackground)
    }

    private var fieldBackground: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Color.white.opacity(0.06))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.07), lineWidth: 1)
            )
    }

    private func sync() {
        title = state.selectedItem?.title ?? ""
        keyword = state.selectedItem?.keyword ?? ""
        tags = state.selectedItem?.tags.joined(separator: ", ") ?? ""
        content = state.selectedItem?.content ?? ""
    }

    private func persist() {
        state.updateSelected(title: title, content: content, keyword: keyword, tags: tags.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) })
    }
}

private func relativeDate(_ date: Date) -> String {
    let seconds = max(0, Int(Date().timeIntervalSince(date)))
    if seconds < 60 { return "now" }
    let minutes = seconds / 60
    if minutes < 60 { return "\(minutes)m ago" }
    let hours = minutes / 60
    if hours < 24 { return "\(hours)h ago" }
    return "\(hours / 24)d ago"
}

private func relativeDuration(_ date: Date) -> String {
    let seconds = max(0, Int(Date().timeIntervalSince(date)))
    if seconds < 60 { return "<1m" }
    let minutes = seconds / 60
    if minutes < 60 { return "\(minutes)m" }
    let hours = minutes / 60
    if hours < 24 { return "\(hours)h \(minutes % 60)m" }
    return "\(hours / 24)d"
}

private struct ClipboardHistoryCard: View {
    let item: ClipboardHistoryItem
    let isSelected: Bool
    let copy: () -> Void
    let remove: () -> Void
    let addToShelf: () -> Void

    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.white.opacity(0.075))
                    .overlay(
                        Image(systemName: item.systemImage)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(FoundryTheme.secondaryText)
                    )
                    .frame(width: 32, height: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(FoundryTheme.body(size: 14, weight: .medium))
                        .foregroundStyle(FoundryTheme.primaryText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    HStack(spacing: 6) {
                        Text(item.kindLabel)
                        Text("•")
                        Text(item.subtitle)
                        Text("•")
                        Text(item.timeLabel)
                    }
                    .font(FoundryTheme.body(size: 12, weight: .regular))
                    .foregroundStyle(FoundryTheme.mutedText)
                    .lineLimit(1)
                }

                Spacer(minLength: 0)
            }

            ClipboardInlinePreview(item: item)

            HStack(spacing: 7) {
                if item.kindLabel == "Files" {
                    ClipboardCardButton(symbol: "tray.and.arrow.down", action: addToShelf)
                }
                ClipboardCardButton(symbol: "doc.on.doc", action: copy)
                ClipboardCardButton(symbol: "xmark", action: remove)
                Spacer(minLength: 0)
            }
            .opacity(isSelected || isHovering ? 1 : 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(height: 210, alignment: .topLeading)
        .background(RowBackground(isSelected: isSelected, isHovering: isHovering, cornerRadius: 10))
        .animation(.easeOut(duration: 0.10), value: isSelected)
        .animation(.easeOut(duration: 0.12), value: isHovering)
        .onHover { hovering in
            isHovering = hovering
            if hovering { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
        }
    }
}

private struct ClipboardCardButton: View {
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(FoundryTheme.mutedText)
                .frame(width: 24, height: 24)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(PressableButtonStyle())
        .pointerCursor()
    }
}

private struct TranslatorView: View {
    @ObservedObject var state: TranslatorState

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                TranslatorPane(title: "English", placeholder: "Enter text", text: $state.sourceText, isEditable: true)

                Image(systemName: "arrow.right")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(FoundryTheme.secondaryText)

                TranslatorPane(title: state.targetLanguage, placeholder: "Translation", text: $state.result, isEditable: false, copy: state.copyResult) {
                    languageMenu
                }
            }

            HStack(spacing: 10) {
                if state.isTranslating {
                    ProgressView()
                        .controlSize(.small)
                    Text("Translating")
                        .font(FoundryTheme.body(size: 13, weight: .semibold))
                        .foregroundStyle(FoundryTheme.secondaryText)
                }

                if shouldShowAppleFallback {
                    Button("Try Apple Translation") { state.requestAppleTranslationFallback() }
                        .buttonStyle(PressableButtonStyle())
                        .font(FoundryTheme.body(size: 13, weight: .semibold))
                        .foregroundStyle(FoundryTheme.secondaryText)
                }

                Spacer()
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .background(translationBackend)
    }

    private var shouldShowAppleFallback: Bool {
        let value = state.result.lowercased()
        return value.contains("unsafe") || value.contains("unavailable") || value.contains("failed") || value.contains("require macos")
    }

    @ViewBuilder
    private var translationBackend: some View {
        #if canImport(Translation)
        if #available(macOS 15.0, *) {
            AppleTranslationTask(state: state, requestVersion: state.requestVersion)
        }
        #endif
    }

    private var languageMenu: some View {
        Menu {
            ForEach(state.languages, id: \.self) { language in
                Button(language) {
                    state.targetLanguage = language
                }
            }
        } label: {
            HStack(spacing: 5) {
                Text(state.targetLanguage)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
            }
            .font(FoundryTheme.body(size: 12, weight: .semibold))
            .foregroundStyle(FoundryTheme.secondaryText)
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(Color.white.opacity(0.07))
            .clipShape(Capsule())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
    }
}

#if canImport(Translation)
@available(macOS 15.0, *)
private struct AppleTranslationTask: View {
    @ObservedObject var state: TranslatorState
    let requestVersion: Int

    @State private var configuration: TranslationSession.Configuration?

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onChange(of: requestVersion) { _, _ in
                configure()
            }
            .translationTask(configuration) { session in
                let text = state.sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard text.isEmpty == false else { return }
                guard state.needsAppleTranslationFallback else {
                    let modelTranslation = await AppleTranslator.translate(text, to: state.targetLanguage)
                    state.finishTranslation(modelTranslation)
                    return
                }

                do {
                    nonisolated(unsafe) let translationSession = session
                    let response = try await translationSession.translate(text)
                    state.finishTranslation(response.targetText)
                } catch {
                    state.finishTranslation("Apple Translation failed: \(error.localizedDescription)")
                }
            }
    }

    private func configure() {
        guard requestVersion > 0,
              let targetCode = state.languageCode(for: state.targetLanguage) else { return }
        configuration = TranslationSession.Configuration(
            source: Locale.Language(identifier: "en"),
            target: Locale.Language(identifier: targetCode)
        )
        configuration?.invalidate()
    }
}
#endif

private struct TranslatorPane<Accessory: View>: View {
    let title: String
    let placeholder: String
    @Binding var text: String
    let isEditable: Bool
    var copy: (() -> Void)? = nil
    @ViewBuilder var accessory: () -> Accessory

    init(title: String, placeholder: String, text: Binding<String>, isEditable: Bool, copy: (() -> Void)? = nil, @ViewBuilder accessory: @escaping () -> Accessory = { EmptyView() }) {
        self.title = title
        self.placeholder = placeholder
        self._text = text
        self.isEditable = isEditable
        self.copy = copy
        self.accessory = accessory
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                if isEditable {
                    Text(title)
                        .font(FoundryTheme.body(size: 12, weight: .semibold))
                        .foregroundStyle(FoundryTheme.secondaryText)
                } else {
                    accessory()
                    if text.isEmpty == false, let copy {
                        Button(action: copy) {
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(FoundryTheme.secondaryText)
                                .frame(width: 26, height: 26)
                                .background(Color.white.opacity(0.07))
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .pointerCursor()
                    }
                }
                Spacer()
            }

            ZStack(alignment: .topLeading) {
                if text.isEmpty && isEditable == false {
                    Text(placeholder)
                        .font(FoundryTheme.body(size: 18, weight: .regular))
                        .foregroundStyle(FoundryTheme.faintText)
                        .padding(.top, 8)
                        .padding(.leading, 4)
                }

                if isEditable {
                    TextField(placeholder, text: $text, axis: .vertical)
                        .font(FoundryTheme.body(size: 18, weight: .regular))
                        .foregroundStyle(FoundryTheme.primaryText)
                        .textFieldStyle(.plain)
                        .background(Color.clear)
                        .lineLimit(8...12)
                        .padding(.top, 8)
                        .padding(.leading, 4)
                } else {
                    Text(text)
                        .font(FoundryTheme.body(size: 20, weight: .semibold))
                        .foregroundStyle(FoundryTheme.primaryText)
                        .textSelection(.enabled)
                        .padding(.top, 8)
                        .padding(.leading, 4)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 265, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.white.opacity(0.055))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.07), lineWidth: 1)
        )
    }
}

private struct ClipboardInlinePreview: View {
    let item: ClipboardHistoryItem

    var body: some View {
        switch item.payload {
        case let .text(value):
            Text(value)
                .font(FoundryTheme.body(size: 12, weight: .regular))
                .foregroundStyle(FoundryTheme.secondaryText)
                .lineLimit(5)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.black.opacity(0.14))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        case let .image(data):
            if let image = NSImage(data: data) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(maxWidth: .infinity, minHeight: 96, maxHeight: 104)
                    .clipped()
                    .padding(8)
                    .background(Color.black.opacity(0.16))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        case let .files(urls):
            VStack(alignment: .leading, spacing: 5) {
                ForEach(Array(urls.prefix(3)), id: \.path) { url in
                    HStack(spacing: 8) {
                        Image(nsImage: IconCache.shared.icon(forFile: url.path))
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 18, height: 18)
                        Text(url.lastPathComponent)
                            .font(FoundryTheme.body(size: 12, weight: .medium))
                            .foregroundStyle(FoundryTheme.secondaryText)
                            .lineLimit(1)
                    }
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.black.opacity(0.14))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }
}

private struct CalculatorResultCard: View {
    let result: CommandResult
    var alternatives: [CommandResult] = []
    var executeAlternative: (CommandResult) -> Void = { _ in }

    private var expression: String {
        result.subtitle ?? "Calculation"
    }

    private var separator: String {
        "→"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            equation
        }
        .padding(.horizontal, 8)
        .padding(.top, 4)
    }

    private var header: some View {
        HStack(spacing: 0) {
            Text("Calculator")
                .font(FoundryTheme.body(size: 11, weight: .semibold))
                .foregroundStyle(FoundryTheme.faintText)
                .textCase(.uppercase)
                .tracking(0.5)

            Spacer()
        }
        .padding(.horizontal, 8)
    }

    private var equation: some View {
        HStack(spacing: 0) {
            CalculatorValuePane(value: expression)

            VStack(spacing: 0) {
                Rectangle()
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 1)

                Text(separator)
                    .font(.system(size: 32, weight: .regular))
                    .foregroundStyle(FoundryTheme.secondaryText)
                    .frame(width: 72, height: 54)

                Rectangle()
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 1)
            }

            CalculatorValuePane(value: result.title, alternatives: alternatives, executeAlternative: executeAlternative)
        }
        .frame(height: 112)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.07), lineWidth: 1)
        )
    }
}

private struct CalculatorValuePane: View {
    let value: String
    var alternatives: [CommandResult] = []
    var executeAlternative: (CommandResult) -> Void = { _ in }

    private var splitValue: (amount: String, unit: String?) {
        split(value)
    }

    var body: some View {
        VStack(spacing: 8) {
            Text(splitValue.amount)
                .font(FoundryTheme.display(size: 36, weight: .bold))
                .foregroundStyle(FoundryTheme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.45)

            if let unit = splitValue.unit {
                Menu {
                    ForEach(alternatives, id: \.id) { alternative in
                        Button(split(alternative.title).unit ?? alternative.title) {
                            withAnimation(.easeOut(duration: 0.16)) {
                                if let code = currencyCode(in: alternative.title) {
                                    UserDefaults.standard.set(code, forKey: "preferredCurrencyQuote")
                                }
                                executeAlternative(alternative)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Text(unit)
                        if alternatives.isEmpty == false {
                            Image(systemName: "chevron.down")
                                .font(.system(size: 9, weight: .bold))
                        }
                    }
                    .font(FoundryTheme.body(size: 13, weight: .semibold))
                    .foregroundStyle(FoundryTheme.secondaryText)
                    .padding(.horizontal, 10)
                    .frame(height: 26)
                    .background(Color.white.opacity(0.07))
                    .clipShape(Capsule())
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.horizontal, 32)
    }

    private func split(_ value: String) -> (amount: String, unit: String?) {
        guard let space = value.firstIndex(of: " ") else { return (value, nil) }
        return (String(value[..<space]), String(value[value.index(after: space)...]))
    }

    private func currencyCode(in value: String) -> String? {
        guard let unit = split(value).unit else { return nil }
        switch unit {
        case "US Dollar": return "USD"
        case "Euro": return "EUR"
        case "British Pound": return "GBP"
        case "Indian Rupee": return "INR"
        case "Japanese Yen": return "JPY"
        case "Canadian Dollar": return "CAD"
        case "Australian Dollar": return "AUD"
        case "Swiss Franc": return "CHF"
        case "Chinese Yuan": return "CNY"
        default: return nil
        }
    }
}

private struct CalculatorUseWithHeader: View {
    let query: String

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        HStack(spacing: 10) {
            Text("Use \"\(trimmedQuery)\" with...")
                .font(FoundryTheme.body(size: 13, weight: .semibold))
                .foregroundStyle(FoundryTheme.secondaryText)

            Image(systemName: "gearshape")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(FoundryTheme.mutedText)

            Spacer()
        }
        .padding(.horizontal, 8)
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
        case .openApp, .openURL, .openConfigFolder:
            "arrow.up.right.square"
        case .openSettings:
            "slider.horizontal.3"
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
        case .downloadMedia:
            "arrow.down.circle"
        case .chooseMediaDownloadFolder:
            "folder.badge.gearshape"
        case .openActivityMonitor:
            "cpu"
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
        case .runProcess:
            "terminal"
        case .quit:
            "power"
        case .log:
            "text.bubble"
        }
    }
}

private struct AgentSessionCardView: View {
    let session: AgentSessionCard
    let open: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: open) {
            HStack(spacing: 9) {
                AgentProviderIconView(provider: session.provider, isHovering: isHovering)
                    .frame(width: 30, height: 30)

                VStack(alignment: .leading, spacing: 4) {
                    Text(session.title)
                        .font(FoundryTheme.body(size: 13, weight: .semibold))
                        .foregroundStyle(FoundryTheme.primaryText)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    if let detailLine = detailLine.nilIfEmpty {
                        Text(detailLine)
                            .font(FoundryTheme.body(size: 10, weight: .regular))
                            .foregroundStyle(FoundryTheme.mutedText)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }

                Spacer(minLength: 0)

                Image(systemName: "arrow.up.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(FoundryTheme.mutedText)
                    .opacity(isHovering ? 0.9 : 0)
            }
            .padding(.horizontal, 10)
            .frame(height: 72)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(isHovering ? 0.070 : 0.038))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(isHovering ? 0.12 : 0.055), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .scaleEffect(isHovering ? 1.006 : 1)
        .animation(.easeOut(duration: 0.12), value: isHovering)
        .onHover { hovering in
            isHovering = hovering
            if hovering { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
        }
    }

    private var detailLine: String {
        [session.model?.nilIfEmpty, session.subtitle.nilIfEmpty].compactMap { $0 }.joined(separator: " · ")
    }

    private var statusLabel: String {
        switch session.status {
        case .needsInput:
            "Needs you"
        case .reviewReady:
            "Review"
        case .working, .running, .failed, .planning:
            session.status.rawValue
        case .completed:
            "Done"
        case .idle, .recent:
            "Recent"
        }
    }

    private var statusColor: Color {
        switch session.status {
        case .working, .running:
            Color(red: 0.42, green: 0.90, blue: 0.67)
        case .needsInput:
            Color(red: 1.0, green: 0.76, blue: 0.35)
        case .reviewReady:
            Color(red: 0.52, green: 0.72, blue: 1.0)
        case .planning:
            Color(red: 0.70, green: 0.62, blue: 1.0)
        case .completed:
            Color(red: 0.44, green: 0.72, blue: 1.0)
        case .failed:
            Color(red: 1.0, green: 0.38, blue: 0.38)
        case .idle, .recent:
            FoundryTheme.faintText
        }
    }

    private var statusTextColor: Color {
        session.status == .recent || session.status == .idle ? FoundryTheme.faintText : statusColor
    }
}

private struct AgentProviderIconView: View {
    let provider: AgentProviderKind
    let isHovering: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(isHovering ? 0.075 : 0.045))

            if let logoURL = provider.logoURL {
                AsyncImage(url: logoURL) { phase in
                    if let image = phase.image {
                        image
                            .resizable()
                            .scaledToFit()
                            .padding(5)
                    }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private struct CameraPreviewView: View {
    @ObservedObject var state: CameraPreviewState

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.white.opacity(0.05))

                CameraPreviewSurface(session: state.session)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

                if state.status.isEmpty == false {
                    VStack(spacing: 10) {
                        Image(systemName: "camera")
                            .font(.system(size: 28, weight: .medium))
                            .foregroundStyle(FoundryTheme.secondaryText)
                        Text(state.status)
                            .font(FoundryTheme.body(size: 15, weight: .semibold))
                            .foregroundStyle(FoundryTheme.primaryText)
                    }
                    .padding(24)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.white.opacity(0.07), lineWidth: 1)
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .onAppear { state.start() }
    }
}

private struct FileConversionView: View {
    @ObservedObject var state: FileConversionState

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Source")
                        .font(FoundryTheme.body(size: 11, weight: .semibold))
                        .foregroundStyle(FoundryTheme.faintText)
                        .textCase(.uppercase)
                        .tracking(0.5)
                    Spacer()
                    Button("Choose File") { state.chooseSourceFile() }
                        .buttonStyle(PressableButtonStyle())
                        .font(FoundryTheme.body(size: 12, weight: .semibold))
                        .foregroundStyle(FoundryTheme.secondaryText)
                        .pointerCursor()
                }

                sourceCard
                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Convert To")
                        .font(FoundryTheme.body(size: 11, weight: .semibold))
                        .foregroundStyle(FoundryTheme.faintText)
                        .textCase(.uppercase)
                        .tracking(0.5)
                    Spacer()
                }

                settingsCard
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
    }

    private var sourceCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let sourceURL = state.sourceURL {
                HStack(alignment: .top, spacing: 12) {
                    Image(nsImage: IconCache.shared.icon(forFile: sourceURL.path))
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 42, height: 42)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(sourceURL.lastPathComponent)
                            .font(FoundryTheme.body(size: 15, weight: .semibold))
                            .foregroundStyle(FoundryTheme.primaryText)
                            .lineLimit(2)
                        Text(prettyFolder(sourceURL.deletingLastPathComponent()))
                            .font(FoundryTheme.body(size: 12, weight: .regular))
                            .foregroundStyle(FoundryTheme.mutedText)
                            .lineLimit(2)
                            .truncationMode(.middle)
                    }
                    Spacer(minLength: 0)
                    if sourceURL.pathExtension.isEmpty == false {
                        Text(sourceURL.pathExtension.uppercased())
                            .font(FoundryTheme.body(size: 10, weight: .bold))
                            .foregroundStyle(FoundryTheme.secondaryText)
                            .tracking(0.5)
                            .padding(.horizontal, 8)
                            .frame(height: 22)
                            .background(Color.white.opacity(0.08))
                            .clipShape(Capsule())
                    }
                }
                Spacer(minLength: 0)
            } else {
                Button { state.chooseSourceFile() } label: {
                    VStack(spacing: 12) {
                        Image(systemName: "doc.badge.plus")
                            .font(.system(size: 30, weight: .regular))
                            .foregroundStyle(FoundryTheme.secondaryText)
                        Text("Choose a file to convert")
                            .font(FoundryTheme.body(size: 15, weight: .semibold))
                            .foregroundStyle(FoundryTheme.primaryText)
                        Text("or drop one onto Foundry")
                            .font(FoundryTheme.body(size: 12, weight: .regular))
                            .foregroundStyle(FoundryTheme.faintText)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .pointerCursor()
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 220, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.white.opacity(0.055))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.white.opacity(0.07), lineWidth: 1))
    }

    private var canConvert: Bool {
        state.sourceURL != nil && state.selectedTarget != nil && state.isConverting == false
    }

    private var settingsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            if state.availableTargets.isEmpty == false {
                fieldLabel("Format")

                Menu {
                    ForEach(groupedTargetCategories, id: \.self) { category in
                        Section(category.rawValue) {
                            ForEach(groupedTargets[category] ?? []) { target in
                                Button(target.title) { state.selectedTargetID = target.id }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(state.selectedTarget?.title ?? "Choose format")
                                .font(FoundryTheme.body(size: 14, weight: .semibold))
                                .foregroundStyle(FoundryTheme.primaryText)
                            if let category = state.selectedTarget?.category {
                                Text(category.rawValue)
                                    .font(FoundryTheme.body(size: 11, weight: .medium))
                                    .foregroundStyle(FoundryTheme.faintText)
                            }
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(FoundryTheme.mutedText)
                    }
                    .padding(.horizontal, 13)
                    .frame(height: 40)
                    .background(fieldBackground)
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .pointerCursor()

                fieldLabel("Save To")

                Button {
                    state.chooseOutputFolder()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "folder")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(FoundryTheme.mutedText)
                        Text(prettyFolder(state.outputFolderURL))
                            .font(FoundryTheme.body(size: 13, weight: .medium))
                            .foregroundStyle(FoundryTheme.primaryText)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 13)
                    .frame(height: 40)
                    .background(fieldBackground)
                }
                .buttonStyle(.plain)
                .pointerCursor()

                Spacer(minLength: 0)

                convertButton

                if let detail = statusDetail {
                    HStack(spacing: 6) {
                        Image(systemName: detail.icon)
                            .font(.system(size: 11, weight: .semibold))
                        Text(detail.text)
                            .font(FoundryTheme.body(size: 12, weight: .medium))
                            .lineLimit(2)
                    }
                    .foregroundStyle(detail.color)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                if state.outputURL != nil {
                    Button("Reveal in Finder") { state.revealOutput() }
                        .buttonStyle(PressableButtonStyle())
                        .font(FoundryTheme.body(size: 12, weight: .semibold))
                        .foregroundStyle(FoundryTheme.secondaryText)
                        .frame(maxWidth: .infinity)
                        .pointerCursor()
                }
            } else if state.sourceURL != nil {
                Spacer(minLength: 0)
                VStack(spacing: 10) {
                    Image(systemName: "questionmark.folder")
                        .font(.system(size: 28, weight: .regular))
                        .foregroundStyle(FoundryTheme.mutedText)
                    Text("No converter for this file yet")
                        .font(FoundryTheme.body(size: 14, weight: .semibold))
                        .foregroundStyle(FoundryTheme.primaryText)
                    Text("Images, documents and PDFs work out of the box. Audio and video need ffmpeg installed.")
                        .font(FoundryTheme.body(size: 12, weight: .regular))
                        .foregroundStyle(FoundryTheme.faintText)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                Spacer(minLength: 0)
            } else {
                Spacer(minLength: 0)
                Text("Choose a file to see the formats you can convert it to.")
                    .font(FoundryTheme.body(size: 13, weight: .regular))
                    .foregroundStyle(FoundryTheme.faintText)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .multilineTextAlignment(.center)
                Spacer(minLength: 0)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 220, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.white.opacity(0.055))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.white.opacity(0.07), lineWidth: 1))
    }

    private var groupedTargets: [FileConversionTarget.Category: [FileConversionTarget]] {
        Dictionary(grouping: state.availableTargets, by: \.category)
    }

    private var groupedTargetCategories: [FileConversionTarget.Category] {
        FileConversionTarget.Category.allCases.filter { groupedTargets[$0]?.isEmpty == false }
    }

    private var convertButton: some View {
        Button { state.convert() } label: {
            HStack(spacing: 8) {
                if state.isConverting {
                    ProgressView()
                        .controlSize(.small)
                        .tint(FoundryTheme.primaryText)
                }
                Text(state.isConverting ? "Converting…" : "Convert")
                    .font(FoundryTheme.body(size: 14, weight: .bold))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .foregroundStyle(FoundryTheme.primaryText)
            .background(convertButtonGlass)
            .opacity(canConvert ? 1 : 0.45)
        }
        .buttonStyle(PressableButtonStyle())
        .disabled(canConvert == false)
        .keyboardShortcut(.defaultAction)
        .pointerCursor()
    }

    private var convertButtonGlass: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        return shape
            .fill(.ultraThinMaterial)
            .overlay {
                shape.fill(Color.white.opacity(0.10))
            }
            .overlay {
                shape.strokeBorder(Color.white.opacity(0.16), lineWidth: 1)
            }
            .compositingGroup()
            .shadow(color: Color.black.opacity(0.28), radius: 12, y: 6)
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(FoundryTheme.body(size: 11, weight: .semibold))
            .foregroundStyle(FoundryTheme.faintText)
            .textCase(.uppercase)
            .tracking(0.5)
    }

    private var fieldBackground: some View {
        RoundedRectangle(cornerRadius: 11, style: .continuous)
            .fill(Color.white.opacity(0.06))
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
    }

    private func prettyFolder(_ url: URL?) -> String {
        guard let url else { return "Choose folder" }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let path = url.path
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }

    private var statusDetail: (text: String, icon: String, color: Color)? {
        if state.isConverting { return nil }
        if state.status.isEmpty { return nil }
        if state.outputURL != nil {
            return (state.status, "checkmark.circle.fill", Color.green.opacity(0.85))
        }
        return (state.status, "exclamationmark.triangle.fill", Color.orange.opacity(0.9))
    }
}

private struct CameraPreviewSurface: NSViewRepresentable {
    let session: AVCaptureSession

    func makeNSView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.videoGravity = .resizeAspectFill
        view.previewLayer.session = session
        return view
    }

    func updateNSView(_ nsView: PreviewView, context: Context) {
        nsView.previewLayer.session = session
    }
}

private final class PreviewView: NSView {
    let previewLayer = AVCaptureVideoPreviewLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer = CALayer()
        previewLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        previewLayer.frame = bounds
        layer?.addSublayer(previewLayer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        previewLayer.frame = bounds
    }
}

private struct AppIcon: View {
    let icon: CommandIcon
    var size: CGFloat = 34
    var cornerRadius: CGFloat = 9

    var body: some View {
        Group {
            if let image = nsImage {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else if let systemName = icon.systemName {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.white.opacity(0.075))
                    .overlay(
                        Image(systemName: systemName)
                            .font(.system(size: size * 0.47, weight: .medium))
                            .foregroundStyle(FoundryTheme.secondaryText)
                    )
            } else {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.white.opacity(0.075))
                    .overlay(
                        Text(icon.fallback)
                            .font(FoundryTheme.body(size: size * 0.32, weight: .semibold))
                            .foregroundStyle(FoundryTheme.secondaryText)
                    )
            }
        }
        .frame(width: size, height: size)
    }

    private var nsImage: NSImage? {
        guard let filePath = icon.filePath else { return nil }
        return IconCache.shared.icon(forFile: filePath)
    }
}

@MainActor
private final class IconCache {
    static let shared = IconCache()

    private let cache = NSCache<NSString, NSImage>()

    func icon(forFile path: String) -> NSImage {
        let key = path as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }

        let image = NSWorkspace.shared.icon(forFile: path)
        image.size = NSSize(width: 34, height: 34)
        cache.setObject(image, forKey: key)
        return image
    }
}

private struct KeycapHint: View {
    let text: String

    var body: some View {
        Text(text)
            .font(FoundryTheme.body(size: 11, weight: .medium))
            .foregroundStyle(FoundryTheme.secondaryText)
            .frame(minWidth: 18)
            .padding(.horizontal, 5)
            .frame(height: 20)
            .background(FoundryTheme.keycap)
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .stroke(FoundryTheme.keycapBorder, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
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

private struct FooterDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.white.opacity(0.10))
            .frame(width: 1, height: 14)
    }
}

private struct FoundryMenu: View {
    let openSettings: () -> Void
    let quit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("Foundry")
                .font(FoundryTheme.body(size: 11, weight: .semibold))
                .foregroundStyle(FoundryTheme.faintText)
                .padding(.horizontal, 10)
                .padding(.top, 8)
                .padding(.bottom, 4)

            FoundryMenuItem(symbol: "slider.horizontal.3", title: "Settings", shortcut: "⌘,", action: openSettings)

            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(height: 1)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)

            FoundryMenuItem(symbol: "power", title: "Quit Foundry", shortcut: "⌘Q", action: quit)
        }
        .padding(.bottom, 6)
        .frame(width: 232)
        .background(VisualEffectView(material: .menu, blendingMode: .behindWindow))
        .background(Color.black.opacity(0.28))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.45), radius: 24, x: 0, y: 12)
    }
}

private struct FoundryMenuItem: View {
    let symbol: String
    let title: String
    let shortcut: String
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(FoundryTheme.secondaryText)
                    .frame(width: 18)

                Text(title)
                    .font(FoundryTheme.body(size: 13, weight: .medium))
                    .foregroundStyle(FoundryTheme.primaryText)

                Spacer()

                Text(shortcut)
                    .font(FoundryTheme.body(size: 12, weight: .medium))
                    .foregroundStyle(FoundryTheme.faintText)
            }
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(isHovering ? 0.10 : 0))
            )
            .padding(.horizontal, 6)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
            if hovering { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
        }
    }
}

private struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.975 : 1)
            .opacity(configuration.isPressed ? 0.82 : 1)
            .animation(.easeOut(duration: 0.10), value: configuration.isPressed)
    }
}
