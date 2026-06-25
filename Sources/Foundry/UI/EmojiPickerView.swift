import SwiftUI

struct EmojiPickerView: View {
    @ObservedObject var state: EmojiPickerState
    let copyAndDismiss: () -> Void

    private let columns = Array(repeating: GridItem(.fixed(44), spacing: 10), count: 12)

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Emoji & Symbols")
                        .font(FoundryTheme.body(size: 13, weight: .semibold))
                        .foregroundStyle(FoundryTheme.secondaryText)

                    if state.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        emojiSection(title: "Pinned", items: state.pinned)
                    }

                    emojiSection(title: state.query.isEmpty ? "All" : "Results", items: state.visibleEmoji)
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 18)
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
                .font(FoundryTheme.body(size: 12, weight: .semibold))
                .foregroundStyle(FoundryTheme.secondaryText)

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

    var body: some View {
        Text(item.value)
            .font(.system(size: 26))
            .frame(width: 44, height: 44)
            .background(isSelected ? Color.white.opacity(0.16) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isSelected ? Color.white.opacity(0.18) : Color.clear, lineWidth: 1)
            )
            .accessibilityLabel(item.name)
    }
}
