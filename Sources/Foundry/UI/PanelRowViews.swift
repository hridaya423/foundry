import AppKit
import SwiftUI
import FoundryDomain

struct RowBackground: View {
    let isSelected: Bool
    let isHovering: Bool
    var cornerRadius: CGFloat = FoundryTheme.Radius.row
    @Environment(\.foundryHoverHighlightsArmed) private var hoverHighlightsArmed
    @Environment(\.foundryIncreaseContrast) private var increaseContrast

    private var fill: Color {
        if isSelected { return increaseContrast ? FoundryTheme.highContrastSelection : FoundryTheme.fillSelected }
        if isHovering && hoverHighlightsArmed { return FoundryTheme.fillHover }
        return Color.clear
    }

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(fill)
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(isSelected ? (increaseContrast ? FoundryTheme.highContrastSelectionBorder : FoundryTheme.selectionBorder) : Color.clear,
                        lineWidth: increaseContrast ? 2 : 1)
            }
    }
}

private struct FoundryHoverHighlightsArmedKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    var foundryHoverHighlightsArmed: Bool {
        get { self[FoundryHoverHighlightsArmedKey.self] }
        set { self[FoundryHoverHighlightsArmedKey.self] = newValue }
    }
}

struct HomeSectionHeader: View {
    let title: String
    var action: (() -> Void)? = nil

    var body: some View {
        HStack {
            Text(title.uppercased())
                .font(FoundryTheme.micro)
                .tracking(0.4)
                .foregroundStyle(FoundryTheme.sectionHeader)
            Spacer()
            if let action {
                Button(action: action) {
                    Image(systemName: "slider.horizontal.3")
                        .font(FoundryTheme.Glyph.xs)
                        .foregroundStyle(FoundryTheme.textSecondary)
                        .frame(width: 28, height: 28)
                }
                    .buttonStyle(FoundryQuietButtonStyle())
                    .accessibilityLabel("Customize widgets")
                    .help("Customize widgets")
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 6)
    }
}

struct FavoritesRow: View {
    let results: [CommandResult]
    let showsShortcuts: Bool
    let onSelect: (CommandResult) -> Void

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(results.prefix(8).enumerated()), id: \.element.id) { index, result in
                FavoriteTile(result: result, shortcut: showsShortcuts ? "⌘\(index + 1)" : nil) {
                    onSelect(result)
                }
            }
        }
        .animation(FoundryTheme.Motion.hover, value: showsShortcuts)
        .padding(.horizontal, 2)
    }
}

private struct FavoriteTile: View {
    let result: CommandResult
    let shortcut: String?
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                AppIcon(icon: result.icon, size: 30, cornerRadius: 8)
                ZStack {
                    Text(result.title)
                        .lineLimit(1)
                        .opacity(shortcut == nil ? 1 : 0)
                    Text(shortcut ?? "")
                        .monospacedDigit()
                        .opacity(shortcut == nil ? 0 : 1)
                }
                .font(FoundryTheme.caption)
                .foregroundStyle(FoundryTheme.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(isHovering ? FoundryTheme.fillHover : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: FoundryTheme.Radius.row, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .pointerCursor()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(result.title)
        .accessibilityAddTraits(.isButton)
    }
}

struct MediaResultRow: View {
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
                        .font(isExpanded ? FoundryTheme.title : FoundryTheme.body)
                        .foregroundStyle(FoundryTheme.textPrimary)
                        .lineLimit(isExpanded ? 2 : 1)

                    Text("Download")
                        .font(FoundryTheme.micro)
                        .foregroundStyle(FoundryTheme.textSecondary)
                        .padding(.horizontal, 7)
                        .frame(height: 18)
                        .background(FoundryTheme.fillTint)
                        .clipShape(Capsule())
                }

                if let subtitle = result.subtitle {
                    Text(subtitle)
                        .font(FoundryTheme.bodySecondary)
                        .foregroundStyle(FoundryTheme.textTertiary)
                        .lineLimit(isExpanded ? nil : 2)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }

                if isExpanded {
                    HStack(spacing: 8) {
                        Image(systemName: "folder")
                            .font(FoundryTheme.Glyph.xs)
                        Text(MediaDownloadDestination.folder.path)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .font(FoundryTheme.bodySecondary)
                    .foregroundStyle(FoundryTheme.textSecondary)
                    .padding(.top, 10)

                    Text("Open Actions (⌘K) to change the folder.")
                        .font(FoundryTheme.bodySecondary)
                        .foregroundStyle(FoundryTheme.textQuaternary)
                }
            }

            Spacer()

            Image(systemName: "arrow.down.circle.fill")
                .font(FoundryTheme.Glyph.md)
                .foregroundStyle(FoundryTheme.textSecondary)
        }
        .padding(.horizontal, isExpanded ? 20 : 12)
        .padding(.vertical, isExpanded ? 20 : 0)
        .frame(height: isExpanded ? 260 : 76)
        .background(RowBackground(isSelected: isSelected, isHovering: isHovering))
        .onHover { hovering in
            isHovering = hovering

        }
    }
}

struct MediaThumbnail: View {
    let icon: CommandIcon
    var isExpanded = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(FoundryTheme.fillTint)

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
                .fill(FoundryTheme.shadow)
                .frame(width: isExpanded ? 44 : 24, height: isExpanded ? 44 : 24)
                .overlay(
                    Image(systemName: "play.fill")
                        .font(isExpanded ? FoundryTheme.Glyph.md : FoundryTheme.Glyph.xs)
                        .foregroundStyle(.white)
                        .offset(x: 1)
                )
        }
    }

    private var fallback: some View {
        Image(systemName: icon.systemName ?? "arrow.down.circle")
            .font(FoundryTheme.Glyph.md)
            .foregroundStyle(FoundryTheme.textSecondary)
    }
}

struct ResultRow: View {
    let result: CommandResult
    let isSelected: Bool
    var alias: String? = nil
    var hotkey: String? = nil
    var isRunning = false
    var kindLabel: String? = nil
    var compact = false

    @State private var isHovering = false

    var body: some View {
        if let dragProvider {
            row.onDrag(dragProvider)
        } else {
            row
        }
    }

    private var row: some View {
        HStack(spacing: 12) {
            AppIcon(icon: result.icon, size: 28, cornerRadius: 7)
                .scaleEffect(isSelected ? 1.04 : 1)

            VStack(alignment: .leading, spacing: 2) {
                Text(result.title)
                    .font(FoundryTheme.rowTitle)
                    .foregroundStyle(FoundryTheme.textPrimary)
                    .lineLimit(1)

                // Commands explain themselves by title; a detail line is noise.
                if let subtitle = result.subtitle, ResultSection.of(result) != .commands {
                    Text(subtitle)
                        .font(FoundryTheme.rowDetail)
                        .foregroundStyle(FoundryTheme.textTertiary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            HStack(spacing: 6) {
                if let alias {
                    ResultBadge(text: alias)
                }
                if let hotkey {
                    ResultBadge(text: hotkey)
                }
                if isRunning {
                    Circle()
                        .fill(FoundryTheme.success)
                        .frame(width: 6, height: 6)
                        .accessibilityLabel("Running")
                }
                if let kindLabel {
                    Text(kindLabel)
                        .font(FoundryTheme.rowDetail)
                        .foregroundStyle(FoundryTheme.textQuaternary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, FoundryTheme.Spacing.sm)
        .frame(height: compact ? 38 : 44)
        .background(RowBackground(isSelected: isSelected, isHovering: isHovering))
        .onHover { isHovering = $0 }
        .pointerCursor()
    }

    private var dragProvider: (() -> NSItemProvider)? {
        guard case let .file(url) = result.payload else { return nil }
        return { NSItemProvider(object: url as NSURL) }
    }
}

private struct ResultBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(FoundryTheme.caption)
            .foregroundStyle(FoundryTheme.textTertiary)
            .lineLimit(1)
            .padding(.horizontal, 6)
            .frame(height: 20)
            .background(FoundryTheme.fillHover, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
    }
}

struct AppIcon: View {
    let icon: CommandIcon
    var size: CGFloat = 34
    var cornerRadius: CGFloat = 9

    var body: some View {
        Group {
            if let filePath = icon.filePath {
                FileIcon(path: filePath) { fallback }
            } else if let remoteIconURL = icon.remoteIconURL {
                RemoteIcon(url: remoteIconURL) { fallback }
            } else {
                fallback
            }
        }
        .frame(width: size, height: size)
    }

    @ViewBuilder private var fallback: some View {
        if let systemName = icon.systemName {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(FoundryTheme.fillTint)
                .overlay(
                    Image(systemName: systemName)
                        .font(FoundryTheme.glyph(size * 0.47, weight: .medium))
                        .foregroundStyle(FoundryTheme.textSecondary)
                )
        } else {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(FoundryTheme.fillTint)
                .overlay(
                    Text(icon.fallback)
                        .font(FoundryTheme.glyph(size * 0.32))
                        .foregroundStyle(FoundryTheme.textSecondary)
                )
        }
    }
}

struct FileIcon<Placeholder: View>: View {
    let path: String
    @ViewBuilder var placeholder: () -> Placeholder

    @State private var image: NSImage?

    init(path: String, @ViewBuilder placeholder: @escaping () -> Placeholder) {
        self.path = path
        self.placeholder = placeholder
        // A warm cache renders the icon on the first frame — no flash of
        // placeholder that pops when the async fetch lands.
        _image = State(initialValue: CommandIconRepository.shared.cachedImage(for: path))
    }

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                placeholder()
            }
        }
        .task(id: path) {
            image = await CommandIconRepository.shared.image(for: path)
        }
    }
}

struct RemoteIcon<Placeholder: View>: View {
    let url: URL
    @ViewBuilder var placeholder: () -> Placeholder

    @State private var image: NSImage?

    init(url: URL, @ViewBuilder placeholder: @escaping () -> Placeholder) {
        self.url = url
        self.placeholder = placeholder
        _image = State(initialValue: CommandIconRepository.shared.cachedImage(forRemoteURL: url))
    }

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                placeholder()
            }
        }
        .task(id: url) {
            image = await CommandIconRepository.shared.image(forRemoteURL: url)
        }
    }
}

extension View {
    /// Records a result row's visibility in a set so scroll handlers can
    /// skip re-centering items already on screen.
    func trackVisible(_ id: String, into set: Binding<Set<String>>) -> some View {
        onAppear { set.wrappedValue.insert(id) }
            .onDisappear { set.wrappedValue.remove(id) }
    }
}
