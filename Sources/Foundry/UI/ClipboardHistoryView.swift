import AppKit
import ImageIO
import SwiftUI

struct ClipboardHistoryView: View {
    @Bindable var state: ClipboardHistoryState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let directPaste: () -> Bool
    let pause: (Bool) -> Void

    init(
        state: ClipboardHistoryState,
        directPaste: @escaping () -> Bool = { false },
        pause: @escaping (Bool) -> Void = { _ in }
    ) {
        self.state = state
        self.directPaste = directPaste
        self.pause = pause
    }

    var body: some View {
        VStack(alignment: .leading, spacing: FoundryTheme.Spacing.sm) {
            if state.isPaused {
                InlineNotice(level: .warning, text: "Capture paused. New copies aren’t saved.", symbol: "pause.circle",
                    actionTitle: "Resume", action: { pause(false) })
            }

            if state.items.isEmpty == false || state.isPaused == false {
                HStack(spacing: 6) {
                    if state.items.isEmpty == false {
                        ForEach(Array(ClipboardHistoryState.KindFilter.allCases.enumerated()), id: \.element) { index, filter in
                            let count = state.items.filter(filter.matches).count
                            if filter == .all || count > 0 || state.kindFilter == filter {
                                ClipboardFilterChip(
                                    title: filter.rawValue,
                                    count: filter == .all ? nil : count,
                                    isSelected: state.kindFilter == filter,
                                    shortcut: "⌘\(index + 1)"
                                ) { state.kindFilter = filter }
                            }
                        }
                    }
                    Spacer(minLength: 8)
                    if state.isPaused == false {
                        FoundryActionButton(title: String(localized: "Pause"), systemName: "pause.fill") { pause(true) }
                    }
                }
            }

            if state.items.isEmpty {
                FoundryEmptyState(
                    symbol: "doc.on.clipboard",
                    title: "Clipboard history is empty",
                    message: "Copy text, files, or images while Foundry is running and they will appear here."
                )
            } else if state.visibleItems.isEmpty {
                if state.query.isEmpty {
                    FoundryEmptyState(
                        symbol: "line.3.horizontal.decrease",
                        title: "No \(state.kindFilter.rawValue.lowercased()) in your history",
                        message: "Press ⌘1 to show everything."
                    )
                } else {
                    FoundryEmptyState(
                        symbol: "magnifyingglass",
                        title: "Nothing matches “\(state.query)”",
                        message: "Search covers text, file names and source apps. Press esc to clear."
                    )
                }
            } else {
                SplitPreviewLayout {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 2) {
                                ForEach(state.visibleItems) { item in
                                    ClipboardHistoryRow(
                                        item: item,
                                        isSelected: state.selectedID == item.id,
                                        onPaste: { state.select(id: item.id); _ = directPaste() },
                                        onRemove: { state.select(id: item.id); state.removeSelected() }
                                    )
                                        .id(item.id)
                                        .contentShape(Rectangle())
                                        .onTapGesture { state.select(id: item.id) }
                                        .onTapGesture(count: 2) { state.copySelected() }
                                        .accessibilityAddTraits(.isButton)
                                        .accessibilityAction { state.select(id: item.id); state.copySelected() }
                                }
                            }
                            .padding(.trailing, 8)
                            .padding(.bottom, 6)
                        }
                        .scrollIndicators(.never)
                        .onChange(of: state.selectedID) { _, id in
                            guard let id else { return }
                            proxy.scrollTo(id)
                        }
                    }
                } preview: {
                    if let item = state.selectedItem {
                        ClipboardPreviewPane(
                            item: item,
                            copy: { state.copy(item) },
                            paste: { state.select(id: item.id); _ = directPaste() }
                        )
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 14)
    }
}

private struct ClipboardHistoryRow: View {
    let item: ClipboardHistoryItem
    let isSelected: Bool
    let onPaste: () -> Void
    let onRemove: () -> Void

    @State private var isHovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: FoundryTheme.Spacing.sm) {
            Group {
                if case let .files(urls) = item.payload, let first = urls.first {
                    FileIcon(path: first.path) { Image(systemName: item.systemImage) }
                } else {
                    Image(systemName: item.systemImage)
                        .font(FoundryTheme.Glyph.sm)
                        .foregroundStyle(FoundryTheme.textSecondary)
                }
            }
            .frame(width: 26, height: 26)
            .accessibilityHidden(true)

            Text(item.title)
                .font(FoundryTheme.body)
                .foregroundStyle(FoundryTheme.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 6)

            if item.isPinned {
                Image(systemName: "pin.fill")
                    .font(FoundryTheme.Glyph.xs)
                    .foregroundStyle(FoundryTheme.textQuaternary)
                    .accessibilityLabel("Pinned")
            }
            if isHovering {
                HStack(spacing: 2) {
                    hoverAction("text.insert", label: "Paste", action: onPaste)
                    hoverAction("xmark", label: "Remove", action: onRemove)
                }
            } else {
                Text(item.timeLabel)
                    .font(FoundryTheme.caption.monospacedDigit())
                    .foregroundStyle(FoundryTheme.textQuaternary)
            }
        }
        .padding(.horizontal, FoundryTheme.Spacing.sm)
        .frame(height: 40)
        .background(RowBackground(isSelected: isSelected, isHovering: isHovering))
        .onHover { isHovering = $0 }
        .animation(reduceMotion ? nil : FoundryTheme.Motion.hover, value: isHovering)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func hoverAction(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(FoundryTheme.Glyph.xs)
                .foregroundStyle(FoundryTheme.textSecondary)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
    }
}

private struct ClipboardPreviewPane: View {
    let item: ClipboardHistoryItem
    let copy: () -> Void
    let paste: () -> Void

    @AppStorage("clipboard.preview.monospace") private var monospace = false

    private var sourceApp: String? {
        guard let bundleID = item.sourceBundleIdentifier,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return item.sourceBundleIdentifier }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }

    private var metadata: [(label: String, value: String)] {
        var rows: [(String, String)] = [("Kind", item.kindLabel)]
        if let sourceApp { rows.append(("Source", sourceApp)) }
        rows.append(("Copied", PreviewMetadata.date(item.createdAt)))
        switch item.payload {
        case let .text(value): rows.append(("Characters", value.count.formatted()))
        case let .image(data):
            rows.append(("Size", PreviewMetadata.size(data.count)))
            if let source = CGImageSourceCreateWithData(data as CFData, nil),
               let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
               let width = properties[kCGImagePropertyPixelWidth] as? Int,
               let height = properties[kCGImagePropertyPixelHeight] as? Int {
                rows.append(("Dimensions", "\(width) × \(height)"))
            }
        case let .files(urls):
            if urls.count == 1, let url = urls.first {
                rows.append(("Where", (url.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath))
            } else {
                rows.append(("Items", urls.count.formatted()))
            }
        }
        return rows
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                if case .text = item.payload {
                    ClipboardCardButton(symbol: monospace ? "textformat" : "chevron.left.forwardslash.chevron.right",
                        label: monospace ? "Show proportional text" : "Show monospaced text") { monospace.toggle() }
                }
                Spacer(minLength: 0)
                ClipboardCardButton(symbol: "doc.on.doc", label: "Copy", action: copy)
                ClipboardCardButton(symbol: "text.insert", label: "Paste", action: paste)
            }

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            PreviewMetadata(rows: metadata)
        }
        .padding(.leading, 14)
    }

    @ViewBuilder
    private var content: some View {
        switch item.payload {
        case let .text(value):
            ScrollView {
                Text(value.count > 20_000 ? String(value.prefix(20_000)) + "\n…" : value)
                    .font(monospace ? FoundryTheme.mono : FoundryTheme.bodySecondary)
                    .foregroundStyle(FoundryTheme.textSecondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.automatic)
        case let .image(data):
            ClipboardImagePreview(data: data, signature: item.signature)
        case let .files(urls):
            if urls.count == 1, let url = urls.first {
                FilePreview(path: url.path, showsMetadata: false)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(urls, id: \.path) { url in
                            HStack(spacing: 8) {
                                FileIcon(path: url.path) { Color.clear }
                                    .frame(width: 18, height: 18)
                                Text(url.lastPathComponent)
                                    .font(FoundryTheme.bodySecondary)
                                    .foregroundStyle(FoundryTheme.textSecondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct ClipboardFilterChip: View {
    let title: String
    let count: Int?
    let isSelected: Bool
    let shortcut: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Text(title)
                if let count {
                    Text(count.formatted())
                        .monospacedDigit()
                        .foregroundStyle(isSelected ? FoundryTheme.textSecondary : FoundryTheme.textTertiary)
                }
            }
            .font(FoundryTheme.caption)
            .foregroundStyle(isSelected ? FoundryTheme.textPrimary : FoundryTheme.textSecondary)
            .padding(.horizontal, FoundryTheme.Spacing.xs)
            .frame(height: 24)
            .background(Capsule(style: .continuous).fill(isSelected ? FoundryTheme.accentTintFill : FoundryTheme.fillHover))
            .contentShape(Capsule())
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel(count.map { "\(title), \($0)" } ?? title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .help("\(title) \(shortcut)")
    }
}

private struct ClipboardCardButton: View {
    let symbol: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(FoundryTheme.Glyph.xs)
                .foregroundStyle(FoundryTheme.textTertiary)
                .frame(width: 24, height: 24)
                .background(FoundryTheme.fillHover)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel(label)
        .help(label)
    }
}

struct ClipboardImagePreview: View {
    let data: Data
    let signature: String

    static let imageCache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 64
        cache.totalCostLimit = 48 * 1024 * 1024
        return cache
    }()

    static func releaseCachedImages() {
        imageCache.removeAllObjects()
    }

    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .accessibilityLabel("Copied image")
            }
        }
        .task(id: signature) {
            let key = signature as NSString
            if let cached = Self.imageCache.object(forKey: key) {
                image = cached
                return
            }
            let decoded = await Task.detached(priority: .utility) {
                guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil as CGImage? }
                return CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceThumbnailMaxPixelSize: 1200,
                    kCGImageSourceCreateThumbnailWithTransform: true
                ] as CFDictionary)
            }.value.map { NSImage(cgImage: $0, size: .zero) }
            if let decoded {
                let pixels = decoded.representations.first.map { $0.pixelsWide * $0.pixelsHigh } ?? 0
                Self.imageCache.setObject(decoded, forKey: key, cost: pixels * 4)
            }
            image = decoded
        }
    }
}
