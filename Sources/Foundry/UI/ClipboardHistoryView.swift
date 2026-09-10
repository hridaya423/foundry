import AppKit
import ImageIO
import SwiftUI

struct ClipboardHistoryView: View {
    @ObservedObject var state: ClipboardHistoryState
    @ObservedObject var fileShelf: FileShelfState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isConfirmingClear = false
    let directPaste: () -> Bool
    let pause: (Bool) -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 3)

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

            if state.items.isEmpty {
                FoundryEmptyState(
                    symbol: "doc.on.clipboard",
                    title: "Clipboard history is empty",
                    message: "Copy text, files, or images while Foundry is running and they will appear here."
                )
            } else if state.visibleItems.isEmpty {
                FoundryEmptyState(
                    symbol: "magnifyingglass",
                    title: "No clipboard matches",
                    message: "Try a shorter search or clear the search field."
                )
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
                            ForEach(state.visibleItems) { item in
                                ClipboardHistoryCard(
                                    item: item,
                                    isSelected: state.selectedID == item.id,
                                    copy: { state.copy(item) },
                                     remove: { state.select(id: item.id); state.removeSelected() },
                                     paste: { state.select(id: item.id); _ = directPaste() },
                                    addToShelf: { state.select(id: item.id); state.addSelectedFiles(to: fileShelf) }
                                )
                                .id(item.id)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    state.select(id: item.id)
                                }
                                .onTapGesture(count: 2) { state.copySelected() }
                            }
                        }
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

private struct ClipboardHistoryCard: View {
    let item: ClipboardHistoryItem
    let isSelected: Bool
    let copy: () -> Void
    let remove: () -> Void
    let paste: () -> Void
    let addToShelf: () -> Void

    @State private var isHovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.primary.opacity(0.075))
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
                    ClipboardCardButton(symbol: "tray.and.arrow.down", label: "Add files to shelf", action: addToShelf)
                }
                ClipboardCardButton(symbol: "doc.on.doc", label: "Copy item", action: copy)
                ClipboardCardButton(symbol: "text.insert", label: "Paste into originating app", action: paste)
                ClipboardCardButton(symbol: "xmark", label: "Remove item", action: remove)
                Spacer(minLength: 0)
            }
            .opacity(isSelected || isHovering ? 1 : 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(height: 210, alignment: .topLeading)
        .background(RowBackground(isSelected: isSelected, isHovering: isHovering, cornerRadius: 10))
        .animation(reduceMotion ? nil : .easeOut(duration: 0.10), value: isSelected)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isHovering)
        .onHover { hovering in
            isHovering = hovering
            if hovering { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
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

private struct ClipboardInlinePreview: View {
    let item: ClipboardHistoryItem

    private static let imageCache = NSCache<NSString, NSImage>()

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
            if let image = Self.cachedImage(data: data, key: item.signature) {
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

    private static func cachedImage(data: Data, key: String) -> NSImage? {
        let cacheKey = key as NSString
        if let cached = imageCache.object(forKey: cacheKey) { return cached }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceThumbnailMaxPixelSize: 600,
                  kCGImageSourceCreateThumbnailWithTransform: true
              ] as CFDictionary) else { return nil }
        let result = NSImage(cgImage: image, size: .zero)
        imageCache.setObject(result, forKey: cacheKey)
        return result
    }
}
