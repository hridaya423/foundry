import AppKit
import SwiftUI

struct CommandPanelView: View {
    @ObservedObject var state: CommandPanelState
    let dismiss: () -> Void

    @FocusState private var inputFocused: Bool

    private var selectedCalculatorResult: CommandResult? {
        guard let selectedResult = state.selectedResult, selectedResult.id.hasPrefix("calculator.") else { return nil }
        return selectedResult
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            if state.isShowingActions {
                actionsSurface
            } else if state.results.isEmpty {
                emptyState
            } else {
                resultsSurface
            }

            footer
        }
        .background(FoundryBackdrop())
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [Color.white.opacity(0.42), Color.white.opacity(0.18), Color.white.opacity(0.06)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: FoundryTheme.glassShadow, radius: 34, x: 0, y: 22)
        .shadow(color: Color.white.opacity(0.12), radius: 1, x: 0, y: 1)
        .frame(width: 760, height: 500)
        .onAppear {
            inputFocused = true
        }
        .onMoveCommand { direction in
            switch direction {
            case .down:
                state.moveSelectionDown()
            case .up:
                state.moveSelectionUp()
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

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(FoundryTheme.mutedText)
                .frame(width: 24)

            TextField("Search apps, files, and commands...", text: $state.query)
                .textFieldStyle(.plain)
                .font(FoundryTheme.body(size: 24, weight: .regular))
                .foregroundStyle(FoundryTheme.primaryText)
                .focused($inputFocused)
                .onSubmit {
                    state.executeSelectedResult()
                    if state.selectedResult != nil {
                        dismiss()
                    }
                }
        }
        .padding(.horizontal, 28)
        .frame(height: 78)
        .background(Color.clear)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(FoundryTheme.border)
                .frame(height: 1)
                .opacity(0.55)
        }
    }

    private var resultsSurface: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 3) {
                    if let selectedCalculatorResult {
                        CalculatorResultCard(result: selectedCalculatorResult)
                            .padding(.bottom, 18)

                        if displayedResults.isEmpty == false {
                            CalculatorUseWithHeader(query: state.query)
                                .padding(.bottom, 4)
                        }
                    }

                    ForEach(Array(displayedResults.enumerated()), id: \.element.id) { index, result in
                        ResultRow(
                            result: result,
                            isSelected: state.selectedResultID == result.id,
                            index: index
                        )
                        .id(result.id)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            state.select(resultID: result.id)
                            state.executeSelectedResult()
                            dismiss()
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, selectedCalculatorResult == nil ? 10 : 14)
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
        guard selectedCalculatorResult != nil else { return state.results }
        return state.results.filter { $0.id.hasPrefix("calculator.") == false }
    }

    private var actionsSurface: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("Actions")
                    .font(FoundryTheme.body(size: 12, weight: .semibold))
                    .foregroundStyle(FoundryTheme.secondaryText)

                if let selectedResult = state.selectedResult {
                    Text(selectedResult.title)
                        .font(FoundryTheme.body(size: 12, weight: .regular))
                        .foregroundStyle(FoundryTheme.mutedText)
                        .lineLimit(1)
                }

                Spacer()
            }
            .padding(.horizontal, 22)
            .frame(height: 42)
            .background(Color.clear)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 3) {
                        ForEach(state.selectedActions, id: \.id) { action in
                            ActionRow(
                                action: action,
                                isSelected: state.selectedActionID == action.id
                            )
                            .id(action.id)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                state.select(actionID: action.id)
                                state.executeSelectedResult()
                                dismiss()
                            }
                        }
                    }
                    .padding(.horizontal, 10)
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

    private var emptyState: some View {
        VStack(spacing: 14) {
            Spacer()

            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white.opacity(0.075))
                    .frame(width: 68, height: 68)

                Image(systemName: "command")
                    .font(.system(size: 28, weight: .regular))
                    .foregroundStyle(FoundryTheme.secondaryText)
            }

            Text("Start typing")
                .font(FoundryTheme.body(size: 17, weight: .medium))
                .foregroundStyle(FoundryTheme.primaryText)

            Text("Find apps, files, and commands from one place.")
                .font(FoundryTheme.body(size: 13, weight: .regular))
                .foregroundStyle(FoundryTheme.secondaryText)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.clear)
    }

    private var footer: some View {
        HStack(spacing: 16) {
            FooterHint(keys: "return", label: selectedCalculatorResult == nil ? "Open" : "Copy Answer")
            FooterHint(keys: "⌘ K", label: "Actions")
            FooterHint(keys: "esc", label: "Close")

            Spacer()

            Text(state.diagnosticsSummary.lowercased())
                .font(FoundryTheme.body(size: 11, weight: .medium))
                .foregroundStyle(FoundryTheme.mutedText)
        }
        .padding(.horizontal, 22)
        .frame(height: 46)
        .background(Color.clear)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(FoundryTheme.border)
                .frame(height: 1)
                .opacity(0.35)
        }
    }
}

private struct ResultRow: View {
    let result: CommandResult
    let isSelected: Bool
    let index: Int

    var body: some View {
        HStack(spacing: 12) {
            AppIcon(icon: result.icon)

            VStack(alignment: .leading, spacing: 3) {
                Text(result.title)
                    .font(FoundryTheme.body(size: 15, weight: .semibold))
                    .foregroundStyle(FoundryTheme.primaryText)
                    .lineLimit(1)

                if let subtitle = result.subtitle {
                    Text(subtitle)
                        .font(FoundryTheme.body(size: 12, weight: .regular))
                        .foregroundStyle(FoundryTheme.secondaryText)
                        .lineLimit(1)
                }
            }

            Spacer()

            if isSelected {
                Text("return")
                    .font(FoundryTheme.body(size: 10, weight: .medium))
                    .foregroundStyle(FoundryTheme.mutedText)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(FoundryTheme.keycap)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 54)
        .background(isSelected ? FoundryTheme.selection : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(isSelected ? FoundryTheme.selectionBorder : Color.clear, lineWidth: 1)
        )
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
                .font(FoundryTheme.body(size: 14, weight: .semibold))
                .foregroundStyle(FoundryTheme.secondaryText)

            Spacer()
        }
        .padding(.horizontal, 8)
    }

    private var equation: some View {
        HStack(spacing: 0) {
            CalculatorValuePane(value: expression)

            VStack(spacing: 0) {
                Rectangle()
                    .fill(Color.white.opacity(0.10))
                    .frame(width: 1)

                Text(separator)
                    .font(.system(size: 34, weight: .regular))
                    .foregroundStyle(FoundryTheme.primaryText)
                    .frame(width: 72, height: 54)

                Rectangle()
                    .fill(Color.white.opacity(0.10))
                    .frame(width: 1)
            }

            CalculatorValuePane(value: result.title)
        }
        .frame(height: 112)
        .background(Color.white.opacity(0.065))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
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

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.white.opacity(0.075))
                .overlay(
                    Image(systemName: iconName)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(FoundryTheme.secondaryText)
                )
                .frame(width: 34, height: 34)

            Text(action.title)
                .font(FoundryTheme.body(size: 15, weight: .semibold))
                .foregroundStyle(FoundryTheme.primaryText)

            Spacer()

            if isSelected {
                Text("return")
                    .font(FoundryTheme.body(size: 10, weight: .medium))
                    .foregroundStyle(FoundryTheme.mutedText)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(FoundryTheme.keycap)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 54)
        .background(isSelected ? FoundryTheme.selection : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(isSelected ? FoundryTheme.selectionBorder : Color.clear, lineWidth: 1)
        )
    }

    private var iconName: String {
        switch action.kind {
        case .openApp, .openFile, .openURL, .openConfigFolder:
            "arrow.up.right.square"
        case .revealInFinder:
            "folder"
        case .copyToClipboard:
            "doc.on.doc"
        case .rebuildFileIndex:
            "arrow.clockwise"
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

    var body: some View {
        Group {
            if let image = nsImage {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else if let systemName = icon.systemName {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.white.opacity(0.075))
                    .overlay(
                        Image(systemName: systemName)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(FoundryTheme.secondaryText)
                    )
            } else {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.white.opacity(0.075))
                    .overlay(
                        Text(icon.fallback)
                            .font(FoundryTheme.body(size: 11, weight: .semibold))
                            .foregroundStyle(FoundryTheme.secondaryText)
                    )
            }
        }
        .frame(width: 34, height: 34)
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

private struct FooterHint: View {
    let keys: String
    let label: String

    var body: some View {
        HStack(spacing: 6) {
            Text(keys)
                .font(FoundryTheme.body(size: 10, weight: .semibold))
                .foregroundStyle(FoundryTheme.secondaryText)

            Text(label)
                .font(FoundryTheme.body(size: 11, weight: .medium))
                .foregroundStyle(FoundryTheme.mutedText)
        }
    }
}
