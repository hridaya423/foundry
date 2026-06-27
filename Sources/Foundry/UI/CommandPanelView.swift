import AppKit
import SwiftUI
import UniformTypeIdentifiers

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
        .onChange(of: state.mode) { _, _ in
            isShowingFoundryMenu = false
        }
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted, perform: handleFileDrop)
        .onDeleteCommand {
            if state.mode == .fileShelf {
                state.fileShelf.removeSelected()
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
                WidgetSettingsView(board: state.widgetBoard)
            } else if state.mode == .activityMonitor {
                ActivityMonitorView(state: state.activityMonitor)
            } else if state.mode == .emojiPicker {
                EmojiPickerView(state: state.emojiPicker) {
                    if state.emojiPicker.copySelectedEmoji() {
                        dismiss()
                    }
                }
            } else if state.mode == .fileShelf {
                FileShelfView(state: state.fileShelf)
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
        if state.mode == .fileShelf { return "shelf" }
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
            } else if state.mode == .fileShelf {
                Image(systemName: "tray.full")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(FoundryTheme.mutedText)

                Text("File Shelf")
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

    private var resultsSurface: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: isHome ? 2 : 3) {
                    if let selectedCalculatorResult {
                        CalculatorResultCard(result: selectedCalculatorResult)
                            .padding(.bottom, 18)

                        if displayedResults.isEmpty == false {
                            CalculatorUseWithHeader(query: state.query)
                                .padding(.bottom, 4)
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
                            ResultRow(
                                result: result,
                                isSelected: state.selectedResultID == result.id,
                                index: index
                            )
                            .id(result.id)
                            .contentShape(Rectangle())
                            .onTapGesture { execute(result) }
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
            results = results.filter { $0.id.hasPrefix("calculator.") == false }
        }
        if state.mode == .search, state.fileShelf.files.isEmpty == false, state.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            results = results.filter { $0.id != "foundry.file-shelf" }
        }
        return results
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
        case .openEmojiPicker, .openFileShelf, .openActivityMonitor, .openConfigFolder, .openSettings, .quit:
            "Command"
        case .revealInFinder:
            "Finder"
        case .copyToClipboard:
            "Copy"
        case .openURL:
            "URL"
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

            Spacer(minLength: 14)

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
        case .fileShelf:
            FooterAction(label: "Remove", keys: "⌫")
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

private struct CalculatorResultCard: View {
    let result: CommandResult

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

            CalculatorValuePane(value: result.title)
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

    var body: some View {
        Text(value)
            .font(FoundryTheme.display(size: 36, weight: .bold))
            .foregroundStyle(FoundryTheme.primaryText)
            .lineLimit(1)
            .minimumScaleFactor(0.45)
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.horizontal, 32)
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
        case .openActivityMonitor:
            "cpu"
        case .openEmojiPicker:
            "face.smiling"
        case .openFileShelf:
            "tray.full"
        case .runProcess:
            "terminal"
        case .quit:
            "power"
        case .log:
            "text.bubble"
        }
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
