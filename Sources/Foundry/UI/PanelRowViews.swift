import AppKit
import SwiftUI
import FoundryDomain

struct RowBackground: View {
    let isSelected: Bool
    let isHovering: Bool
    var cornerRadius: CGFloat = FoundryTheme.Radius.row
    @Environment(\.foundryHoverHighlightsArmed) private var hoverHighlightsArmed

    private var fill: Color {
        if isSelected { return FoundryTheme.selection }
        if isHovering && hoverHighlightsArmed { return FoundryTheme.hover }
        return Color.clear
    }

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(fill)
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(isSelected ? FoundryTheme.selectionBorder : Color.clear, lineWidth: 1)
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
                .font(FoundryTheme.sectionHeaderFont)
                .tracking(0.4)
                .foregroundStyle(FoundryTheme.primaryText.opacity(0.72))
            Spacer()
            if let action {
                Button(action: action) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(FoundryTheme.secondaryText)
                        .frame(width: 28, height: 28)
                }
                    .buttonStyle(FoundryQuietButtonStyle())
                    .pointerCursor()
                    .accessibilityLabel("Customize widgets")
                    .help("Customize widgets")
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 6)
    }
}

struct HomeResultRow: View {
    let result: CommandResult
    let isSelected: Bool
    let label: String

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 12) {
            AppIcon(icon: result.icon, size: 26, cornerRadius: 6)
                .scaleEffect(isSelected ? 1.04 : 1)

            Text(result.title)
                .font(FoundryTheme.rowTitleFont)
                .foregroundStyle(FoundryTheme.primaryText)
                .lineLimit(1)

            Spacer()

            Text(label)
                .font(FoundryTheme.secondaryFont)
                .foregroundStyle(FoundryTheme.faintText)
                .lineLimit(1)
        }
        .padding(.horizontal, FoundryTheme.Spacing.sm)
        .frame(height: 40)
        .background(RowBackground(isSelected: isSelected, isHovering: isHovering))
        .onHover { hovering in
            isHovering = hovering
            if hovering { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
        }
    }
}

struct FavoritesRow: View {
    let results: [CommandResult]
    let onSelect: (CommandResult) -> Void

    var body: some View {
        HStack(spacing: 4) {
            ForEach(results.prefix(8), id: \.id) { result in
                FavoriteTile(result: result) {
                    onSelect(result)
                }
            }
        }
        .padding(.horizontal, 2)
    }
}

private struct FavoriteTile: View {
    let result: CommandResult
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                AppIcon(icon: result.icon, size: 30, cornerRadius: 8)
                Text(result.title)
                    .font(FoundryTheme.body(size: 10, weight: .medium))
                    .foregroundStyle(FoundryTheme.secondaryText)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(isHovering ? FoundryTheme.hover : Color.clear)
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
                        .font(FoundryTheme.body(size: isExpanded ? 20 : 15, weight: .semibold))
                        .foregroundStyle(FoundryTheme.primaryText)
                        .lineLimit(isExpanded ? 2 : 1)

                    Text("Download")
                        .font(FoundryTheme.body(size: 10, weight: .semibold))
                        .foregroundStyle(FoundryTheme.secondaryText)
                        .padding(.horizontal, 7)
                        .frame(height: 18)
                        .background(Color.primary.opacity(0.08))
                        .clipShape(Capsule())
                }

                if let subtitle = result.subtitle {
                    Text(subtitle)
                        .font(FoundryTheme.body(size: isExpanded ? 14 : 12, weight: .regular))
                        .foregroundStyle(FoundryTheme.mutedText)
                        .lineLimit(isExpanded ? nil : 2)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
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
        .onHover { hovering in
            isHovering = hovering
            if hovering { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
        }
    }
}

struct MediaThumbnail: View {
    let icon: CommandIcon
    var isExpanded = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.075))

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
                    .font(FoundryTheme.rowTitleFont)
                    .foregroundStyle(FoundryTheme.primaryText)
                    .lineLimit(1)

                if let subtitle = result.subtitle, ResultSection.of(result) != .commands {
                    Text(subtitle)
                        .font(FoundryTheme.secondaryFont)
                        .foregroundStyle(FoundryTheme.mutedText)
                        .lineLimit(1)
                }
            }

            Spacer()

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
                        .font(FoundryTheme.secondaryFont)
                        .foregroundStyle(FoundryTheme.faintText)
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, FoundryTheme.Spacing.sm)
        .frame(height: compact ? 38 : 44)
        .background(RowBackground(isSelected: isSelected, isHovering: isHovering))
        .onHover { hovering in
            isHovering = hovering
            if hovering { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
        }
    }

    private var dragProvider: (() -> NSItemProvider)? {
        guard result.id.hasPrefix("file.") else { return nil }
        let path = String(result.id.dropFirst(5))
        return { NSItemProvider(object: NSURL(fileURLWithPath: path)) }
    }
}

private struct ResultBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(FoundryTheme.metaFont)
            .foregroundStyle(FoundryTheme.mutedText)
            .lineLimit(1)
            .padding(.horizontal, 6)
            .frame(height: 20)
            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
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
                .fill(Color.primary.opacity(0.075))
                .overlay(
                    Image(systemName: systemName)
                        .font(.system(size: size * 0.47, weight: .medium))
                        .foregroundStyle(FoundryTheme.secondaryText)
                )
        } else {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.primary.opacity(0.075))
                .overlay(
                    Text(icon.fallback)
                        .font(FoundryTheme.body(size: size * 0.32, weight: .semibold))
                        .foregroundStyle(FoundryTheme.secondaryText)
                )
        }
    }
}

struct FileIcon<Placeholder: View>: View {
    let path: String
    @ViewBuilder var placeholder: () -> Placeholder

    @State private var image: NSImage?

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
