import AppKit
import SwiftUI

struct ClipboardHistoryView: View {
    @ObservedObject var state: ClipboardHistoryState
    @ObservedObject var fileShelf: FileShelfState
    @State private var isConfirmingClear = false

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 3)

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if state.items.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "doc.on.clipboard")
                        .font(.system(size: 34, weight: .regular))
                        .foregroundStyle(FoundryTheme.secondaryText)
                    Text("Copy something to start history")
                        .font(FoundryTheme.body(size: 16, weight: .semibold))
                        .foregroundStyle(FoundryTheme.primaryText)
                    Text("Foundry keeps text, files, and images while it is running.")
                        .font(FoundryTheme.body(size: 13, weight: .regular))
                        .foregroundStyle(FoundryTheme.secondaryText)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack {
                    Text("\(state.visibleItems.count) item\(state.visibleItems.count == 1 ? "" : "s")")
                        .font(FoundryTheme.body(size: 11, weight: .semibold))
                        .foregroundStyle(FoundryTheme.faintText)
                        .textCase(.uppercase)
                        .tracking(0.5)
                    Spacer()
                    Button("Clear") { isConfirmingClear = true }
                        .buttonStyle(PressableButtonStyle())
                        .font(FoundryTheme.body(size: 12, weight: .semibold))
                        .foregroundStyle(FoundryTheme.mutedText)
                        .pointerCursor()
                }
                .padding(.horizontal, 4)

                ScrollView {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
                        ForEach(state.visibleItems) { item in
                            ClipboardHistoryCard(
                                item: item,
                                isSelected: state.selectedID == item.id,
                                copy: { state.copySelected() },
                                remove: { state.select(id: item.id); state.removeSelected() },
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
    let addToShelf: () -> Void

    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.white.opacity(0.075))
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
                ClipboardCardButton(symbol: "xmark", label: "Remove item", action: remove)
                Spacer(minLength: 0)
            }
            .opacity(isSelected || isHovering ? 1 : 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(height: 210, alignment: .topLeading)
        .background(RowBackground(isSelected: isSelected, isHovering: isHovering, cornerRadius: 10))
        .animation(.easeOut(duration: 0.10), value: isSelected)
        .animation(.easeOut(duration: 0.12), value: isHovering)
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
                .background(Color.white.opacity(0.06))
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
            if let image = NSImage(data: data) {
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
}
