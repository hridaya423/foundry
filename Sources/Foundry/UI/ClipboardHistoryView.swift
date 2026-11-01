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
    let extractText: (String) -> Void
    let decodeBarcode: (String) -> Void

    init(
        state: ClipboardHistoryState,
        fileShelf: FileShelfState,
        directPaste: @escaping () -> Bool = { false },
        pause: @escaping (Bool) -> Void = { _ in },
        extractText: @escaping (String) -> Void = { _ in },
        decodeBarcode: @escaping (String) -> Void = { _ in }
    ) {
        self.state = state
        self.fileShelf = fileShelf
        self.directPaste = directPaste
        self.pause = pause
        self.extractText = extractText
        self.decodeBarcode = decodeBarcode
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
                        .font(FoundryTheme.body)
                        .foregroundStyle(FoundryTheme.textSecondary)
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
                                    ClipboardHistoryRow(
                                        item: item,
                                        isSelected: state.selectedID == item.id,
                                        onCopy: { state.select(id: item.id); state.copySelected() },
                                        onPaste: { state.select(id: item.id); _ = directPaste() },
                                        onExtractText: { extractText(item.id) },
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
                            proxy.scrollTo(id, anchor: .center)
                        }
                    }
                } preview: {
                    if let item = state.selectedItem {
                        ClipboardPreviewPane(
                            item: item,
                            copy: { state.copy(item) },
                            remove: { state.select(id: item.id); state.removeSelected() },
                            paste: { state.select(id: item.id); _ = directPaste() },
                            addToShelf: { state.select(id: item.id); state.addSelectedFiles(to: fileShelf) },
                            mergeWithPrevious: { state.select(id: item.id); state.copyMergedWithPreviousSelected() },
                            extractText: { extractText(item.id) },
                            decodeBarcode: { decodeBarcode(item.id) }
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
    let onCopy: () -> Void
    let onPaste: () -> Void
    let onExtractText: () -> Void
    let onRemove: () -> Void

    @State private var isHovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 10) {
            Group {
                if case let .files(urls) = item.payload, let first = urls.first {
                    FileIcon(path: first.path) { Image(systemName: item.systemImage) }
                } else {
                    Image(systemName: item.systemImage)
                        .font(FoundryTheme.Glyph.sm)
                        .foregroundStyle(FoundryTheme.textSecondary)
                }
            }
            .frame(width: 22, height: 22)
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
                    hoverAction("doc.on.doc", label: "Copy", action: onCopy)
                    hoverAction("arrow.up.doc.on.clipboard", label: "Paste as plain text", action: onPaste)
                    if case .image = item.payload {
                        hoverAction("text.viewfinder", label: "Extract text", action: onExtractText)
                    }
                    hoverAction("xmark", label: "Remove", action: onRemove)
                }
            } else {
                Text(item.timeLabel)
                    .font(FoundryTheme.caption.monospacedDigit())
                    .foregroundStyle(FoundryTheme.textQuaternary)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 36)
        .background(RowBackground(isSelected: isSelected, isHovering: isHovering, cornerRadius: 8))
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
    let remove: () -> Void
    let paste: () -> Void
    let addToShelf: () -> Void
    let mergeWithPrevious: () -> Void
    let extractText: () -> Void
    let decodeBarcode: () -> Void

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
                if case let .text(value) = item.payload, let url = linkURL(in: value) {
                    ClipboardCardButton(symbol: "safari", label: "Open link") { NSWorkspace.shared.open(url) }
                }
                if case .files = item.payload {
                    ClipboardCardButton(symbol: "tray.and.arrow.down", label: "Add files to shelf", action: addToShelf)
                }
                if case .image = item.payload {
                    ClipboardCardButton(symbol: "text.viewfinder", label: "Extract text (OCR)", action: extractText)
                    ClipboardCardButton(symbol: "qrcode.viewfinder", label: "Read QR or barcode", action: decodeBarcode)
                }
                if case .text = item.payload {
                    ClipboardCardButton(symbol: "doc.plaintext", label: "Paste as plain text", action: paste)
                    ClipboardCardButton(symbol: "text.append", label: "Copy merged with previous", action: mergeWithPrevious)
                } else {
                    ClipboardCardButton(symbol: "text.insert", label: "Paste into originating app", action: paste)
                }
                ClipboardCardButton(symbol: "doc.on.doc", label: "Copy item", action: copy)
                ClipboardCardButton(symbol: "xmark", label: "Remove item", action: remove)
            }

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            PreviewMetadata(rows: metadata)
        }
        .padding(.leading, 14)
    }

    private func linkURL(in value: String) -> URL? {
        ClipboardHistoryState.linkURL(in: value)
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
