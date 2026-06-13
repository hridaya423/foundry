import AppKit
import SwiftUI

struct CommandPanelView: View {
    @ObservedObject var state: CommandPanelState
    let dismiss: () -> Void

    @FocusState private var inputFocused: Bool

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
        .background(FoundryTheme.surface)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(FoundryTheme.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.26), radius: 26, x: 0, y: 18)
        .frame(width: 680, height: 430)
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
        HStack(spacing: 12) {
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
        .padding(.horizontal, 24)
        .frame(height: 72)
        .background(FoundryTheme.surfaceElevated.opacity(0.22))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(FoundryTheme.border)
                .frame(height: 1)
        }
    }

    private var resultsSurface: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 3) {
                    ForEach(Array(state.results.enumerated()), id: \.element.id) { index, result in
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
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
            }
            .scrollIndicators(.never)
            .background(FoundryTheme.surface)
            .onChange(of: state.selectedResultID) { _, resultID in
                guard let resultID else { return }
                withAnimation(.easeOut(duration: 0.12)) {
                    proxy.scrollTo(resultID, anchor: .center)
                }
            }
        }
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
            .background(FoundryTheme.surface)

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
                .background(FoundryTheme.surface)
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
                    .fill(FoundryTheme.surfaceElevated)
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
        .background(FoundryTheme.surface)
    }

    private var footer: some View {
        HStack(spacing: 14) {
            FooterHint(keys: "return", label: "Open")
            FooterHint(keys: "⌘ K", label: "Actions")
            FooterHint(keys: "esc", label: "Close")

            Spacer()

            Text(state.diagnosticsSummary.lowercased())
                .font(FoundryTheme.body(size: 11, weight: .medium))
                .foregroundStyle(FoundryTheme.mutedText)
        }
        .padding(.horizontal, 14)
        .frame(height: 36)
        .background(FoundryTheme.surfaceElevated.opacity(0.20))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(FoundryTheme.border)
                .frame(height: 1)
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

private struct ActionRow: View {
    let action: CommandAction
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(FoundryTheme.surfaceElevated)
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
                    .fill(FoundryTheme.surfaceElevated)
                    .overlay(
                        Image(systemName: systemName)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(FoundryTheme.secondaryText)
                    )
            } else {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(FoundryTheme.surfaceElevated)
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
                .foregroundStyle(FoundryTheme.primaryText)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(FoundryTheme.keycap)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))

            Text(label)
                .font(FoundryTheme.body(size: 11, weight: .medium))
                .foregroundStyle(FoundryTheme.mutedText)
        }
    }
}
