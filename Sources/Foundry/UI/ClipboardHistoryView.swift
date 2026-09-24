import AppKit
import ImageIO
import SwiftUI

struct ClipboardHistoryView: View {
    @Bindable var state: ClipboardHistoryState
    var fileShelf: FileShelfState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isConfirmingClear = false
    let directPaste: () -> Bool
    let pause: (Bool) -> Void

    init(state: ClipboardHistoryState, fileShelf: FileShelfState, directPaste: @escaping () -> Bool = { false }, pause: @escaping (Bool) -> Void = { _ in }) {
        self.state = state
        self.fileShelf = fileShelf
        self.directPaste = directPaste
        self.pause = pause
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                if state.items.isEmpty == false {
                    FoundrySectionHeader(
                        title: "Clipboard",
                        count: "\(state.visibleItems.count) item\(state.visibleItems.count == 1 ? "" : "s")",
                        actionTitle: "Clear",
                        action: { isConfirmingClear = true }
                    )
                } else {
                    Text("Clipboard")
                        .font(FoundryTheme.body(size: 13, weight: .semibold))
                        .foregroundStyle(FoundryTheme.secondaryText)
                }
                Spacer()
                Button(state.isPaused ? "Resume" : "Pause") { pause(!state.isPaused) }
            }
            .padding(.horizontal, 4)

            if state.items.isEmpty == false {
                Picker("Show", selection: $state.kindFilter) {
                    ForEach(ClipboardHistoryState.KindFilter.allCases) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.small)
                .fixedSize()
                .help("⌘1–⌘5")
            }

            if state.items.isEmpty {
                FoundryEmptyState(
                    symbol: "doc.on.clipboard",
                    title: "Clipboard history is empty",
                    message: "Copy text, files, or images while Foundry is running and they will appear here."
                )
            } else if state.visibleItems.isEmpty {
                FoundryEmptyState(
                    symbol: "magnifyingglass",
                    title: state.query.isEmpty ? "No \(state.kindFilter.rawValue.lowercased()) in your history" : "No clipboard matches",
                    message: state.query.isEmpty ? "Press ⌘1 to show everything." : "Try a shorter search or clear the search field."
                )
            } else {
                SplitPreviewLayout {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 2) {
                                ForEach(state.visibleItems) { item in
                                    ClipboardHistoryRow(item: item, isSelected: state.selectedID == item.id)
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
                            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.12)) {
                                proxy.scrollTo(id, anchor: .center)
                            }
                        }
                    }
                } preview: {
                    if let item = state.visibleItems.first(where: { $0.id == state.selectedID }) ?? state.visibleItems.first {
                        ClipboardPreviewPane(
                            item: item,
                            copy: { state.copy(item) },
                            remove: { state.select(id: item.id); state.removeSelected() },
                            paste: { state.select(id: item.id); _ = directPaste() },
                            addToShelf: { state.select(id: item.id); state.addSelectedFiles(to: fileShelf) }
                        )
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 14)
        .alert("Clear Clipboard History?", isPresented: $isConfirmingClear) {
            Button("Clear History", role: .destructive) { state.clear() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Remove the copied items currently held by Foundry.")
        }
    }
}

private struct ClipboardHistoryRow: View {
    let item: ClipboardHistoryItem
    let isSelected: Bool

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 10) {
            Group {
                if case let .files(urls) = item.payload, let first = urls.first {
                    FileIcon(path: first.path) { Image(systemName: item.systemImage) }
                } else {
                    Image(systemName: item.systemImage)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(FoundryTheme.secondaryText)
                }
            }
            .frame(width: 22, height: 22)
            .accessibilityHidden(true)

            Text(item.title)
                .font(FoundryTheme.body(size: 13, weight: .medium))
                .foregroundStyle(FoundryTheme.primaryText)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 6)

            if item.isPinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(FoundryTheme.faintText)
                    .accessibilityLabel("Pinned")
            }
            Text(item.timeLabel)
                .font(FoundryTheme.metaFont.monospacedDigit())
                .foregroundStyle(FoundryTheme.faintText)
        }
        .padding(.horizontal, 10)
        .frame(height: 36)
        .background(RowBackground(isSelected: isSelected, isHovering: isHovering, cornerRadius: 8))
        .onHover { isHovering = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct ClipboardPreviewPane: View {
    let item: ClipboardHistoryItem
    let copy: () -> Void
    let remove: () -> Void
    let paste: () -> Void
    let addToShelf: () -> Void

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
        case let .image(data): rows.append(("Size", PreviewMetadata.size(data.count)))
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
                    ClipboardCardButton(symbol: monospace ? "textformat" : "chevron.left.forwardslash.chevron.right", label: monospace ? "Show proportional text" : "Show monospaced text") { monospace.toggle() }
                }
                Spacer(minLength: 0)
                if case .files = item.payload {
                    ClipboardCardButton(symbol: "tray.and.arrow.down", label: "Add files to shelf", action: addToShelf)
                }
                ClipboardCardButton(symbol: "doc.on.doc", label: "Copy item", action: copy)
                ClipboardCardButton(symbol: "text.insert", label: "Paste into originating app", action: paste)
                ClipboardCardButton(symbol: "xmark", label: "Remove item", action: remove)
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
                    .font(monospace ? .system(size: 12, design: .monospaced) : FoundryTheme.body(size: 13, weight: .regular))
                    .foregroundStyle(FoundryTheme.secondaryText)
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
                                    .font(FoundryTheme.body(size: 12, weight: .medium))
                                    .foregroundStyle(FoundryTheme.secondaryText)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct ClipboardCardButton: View {
    let symbol: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(FoundryTheme.mutedText)
                .frame(width: 24, height: 24)
                .background(Color.primary.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(PressableButtonStyle())
        .pointerCursor()
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
