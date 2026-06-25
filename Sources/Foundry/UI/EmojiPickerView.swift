import AppKit
import SwiftUI

struct EmojiPickerView: View {
    @ObservedObject var state: EmojiPickerState
    let copyAndDismiss: () -> Void

    private let columns = Array(repeating: GridItem(.fixed(44), spacing: 10), count: 12)

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if state.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        emojiSection(title: "Pinned", items: state.pinned)
                    }

                    emojiSection(title: state.query.isEmpty ? "All" : "Results", items: state.visibleEmoji)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .scrollIndicators(.never)
            .onChange(of: state.selectedID) { _, selectedID in
                guard let selectedID else { return }
                withAnimation(.easeOut(duration: 0.12)) {
                    proxy.scrollTo(selectedID, anchor: .center)
                }
            }
        }
    }

    private func emojiSection(title: String, items: [EmojiItem]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(FoundryTheme.body(size: 11, weight: .semibold))
                .foregroundStyle(FoundryTheme.faintText)
                .textCase(.uppercase)
                .tracking(0.5)

            if items.isEmpty {
                Text("No matching emoji")
                    .font(FoundryTheme.body(size: 14, weight: .medium))
                    .foregroundStyle(FoundryTheme.mutedText)
                    .frame(height: 72)
            } else {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
                    ForEach(items) { item in
                        EmojiCell(
                            item: item,
                            isSelected: state.selectedID == item.id
                        )
                        .id(item.id)
                        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .onTapGesture {
                            state.select(id: item.id)
                            copyAndDismiss()
                        }
                    }
                }
            }
        }
    }
}

private struct EmojiCell: View {
    let item: EmojiItem
    let isSelected: Bool

    @State private var isHovering = false

    private var fill: Color {
        if isSelected { return Color.white.opacity(0.16) }
        if isHovering { return Color.white.opacity(0.08) }
        return Color.clear
    }

    var body: some View {
        Text(item.value)
            .font(.system(size: 26))
            .frame(width: 44, height: 44)
            .background(fill)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isSelected ? Color.white.opacity(0.18) : Color.clear, lineWidth: 1)
            )
            .scaleEffect(isHovering && isSelected == false ? 1.08 : 1)
            .animation(.easeOut(duration: 0.12), value: isHovering)
            .accessibilityLabel(item.name)
            .onHover { hovering in
                isHovering = hovering
                if hovering { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
            }
    }
}
