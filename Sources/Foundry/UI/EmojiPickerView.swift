import AppKit
import SwiftUI

struct EmojiPickerView: View {
    var state: EmojiPickerState
    let copyAndDismiss: () -> Void

    private var columns: [GridItem] { Array(repeating: GridItem(.fixed(44), spacing: 10), count: state.columns) }

    var body: some View {
        if state.resultCells.isEmpty {
            FoundryEmptyState(
                symbol: "face.smiling",
                title: "No emoji for “\(state.query)”",
                message: "Try a feeling or an object, like “happy” or “pizza”."
            )
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        if state.recentCells.isEmpty == false {
                            emojiSection(title: state.hasRecents ? "Recent" : "Suggested", cells: state.recentCells)
                        }
                        emojiSection(title: state.query.isEmpty ? "All" : "Results", cells: state.resultCells)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                }
                .scrollIndicators(.never)
                .onChange(of: state.selectedID) { _, selectedID in
                    guard let selectedID else { return }
                    proxy.scrollTo(selectedID)
                }
            }
        }
    }

    private func emojiSection(title: String, cells: [EmojiPickerState.Cell]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            FoundrySectionHeader(title: title)
            LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
                ForEach(cells) { cell in
                    Button {
                        state.select(id: cell.id)
                        copyAndDismiss()
                    } label: {
                        EmojiCell(value: state.toneAppliedValue(cell.item), name: cell.item.name, isSelected: state.selectedID == cell.id)
                    }
                    .buttonStyle(.plain)
                    .id(cell.id)
                }
            }
        }
    }
}

private struct EmojiCell: View {
    let value: String
    let name: String
    let isSelected: Bool

    @State private var isHovering = false

    var body: some View {
        Text(value)
            .font(FoundryTheme.Glyph.lg)
            .frame(width: 44, height: 44)
            .background(RowBackground(isSelected: isSelected, isHovering: isHovering))
            .onHover { isHovering = $0 }
            .accessibilityLabel(name)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct EmojiSkinToneMenu: View {
    var state: EmojiPickerState

    var body: some View {
        Menu {
            ForEach(Array(EmojiPickerState.skinTones.enumerated()), id: \.offset) { index, tone in
                Button("✋\(tone)  ⌘\(index + 1)") { state.setSkinTone(tone) }
            }
        } label: {
            Text("✋\(state.skinTone)")
                .font(FoundryTheme.Glyph.md)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Skin tone (⌘1–6)")
        .accessibilityLabel("Skin tone")
    }
}
