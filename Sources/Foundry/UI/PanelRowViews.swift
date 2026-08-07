import AppKit
import SwiftUI
import FoundryDomain

struct RowBackground: View {
    let isSelected: Bool
    let isHovering: Bool
    var cornerRadius: CGFloat = 9
    @Environment(\.foundryHoverHighlightsArmed) private var hoverHighlightsArmed

    private var fill: Color {
        if isSelected { return FoundryTheme.selection }
        if isHovering && hoverHighlightsArmed { return FoundryTheme.hover }
        return Color.clear
    }

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(fill)
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
            Text(title)
                .font(FoundryTheme.body(size: 13, weight: .semibold))
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isSelected)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isHovering)
        .onHover { hovering in
            isHovering = hovering
            if hovering { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
        }
    }
}

struct MediaResultRow: View {
    let result: CommandResult
    let isSelected: Bool
    var isExpanded = false

    @State private var isHovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isSelected)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isHovering)
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

struct ResultRow: View {
    let result: CommandResult
    let isSelected: Bool
    let index: Int

    @State private var isHovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isSelected)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isHovering)
        .onHover { hovering in
            isHovering = hovering
            if hovering { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
        }
    }
}

struct AppIcon: View {
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
final class IconCache {
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
