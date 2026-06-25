import AppKit
import Foundation

@MainActor
final class EmojiPickerState: ObservableObject {
    @Published var query = "" {
        didSet { keepSelectionValid() }
    }
    @Published var selectedID: String?

    private let columns = 12

    var pinned: [EmojiItem] {
        ["😍", "😋", "🥵", "😂", "❤️", "🔥"].compactMap { value in
            Self.allEmoji.first { $0.value == value }
        }
    }

    var visibleEmoji: [EmojiItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard trimmed.isEmpty == false else { return Self.allEmoji }
        return Self.allEmoji.filter { item in
            item.value == trimmed
                || item.name.contains(trimmed)
                || item.keywords.contains { $0.contains(trimmed) }
        }
    }

    var selectedEmoji: EmojiItem? {
        let items = visibleEmoji
        guard let selectedID else { return items.first }
        return items.first { $0.id == selectedID } ?? items.first
    }

    func reset() {
        query = ""
        selectedID = visibleEmoji.first?.id
    }

    func select(id: String) {
        selectedID = id
    }

    func moveSelection(offset: Int) {
        let items = visibleEmoji
        guard items.isEmpty == false else { return }
        let currentIndex = selectedID.flatMap { id in items.firstIndex { $0.id == id } } ?? 0
        let nextIndex = min(max(currentIndex + offset, 0), items.count - 1)
        selectedID = items[nextIndex].id
    }

    func moveLeft() {
        moveSelection(offset: -1)
    }

    func moveRight() {
        moveSelection(offset: 1)
    }

    func moveUp() {
        moveSelection(offset: -columns)
    }

    func moveDown() {
        moveSelection(offset: columns)
    }

    @discardableResult
    func copySelectedEmoji() -> Bool {
        guard let selectedEmoji else { return false }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(selectedEmoji.value, forType: .string)
        return true
    }

    private func keepSelectionValid() {
        let items = visibleEmoji
        if let selectedID, items.contains(where: { $0.id == selectedID }) {
            return
        }
        selectedID = items.first?.id
    }
}

struct EmojiItem: Identifiable, Hashable, Sendable {
    let id: String
    let value: String
    let name: String
    let keywords: [String]

    init(_ value: String, _ name: String, _ keywords: [String] = []) {
        self.id = value
        self.value = value
        self.name = name.lowercased()
        self.keywords = (keywords + name.split(separator: " ").map(String.init)).map { $0.lowercased() }
    }
}

private extension EmojiPickerState {
    static let allEmoji: [EmojiItem] = loadEmojiCatalog() + extraSymbols

    static func loadEmojiCatalog() -> [EmojiItem] {
        guard let url = Bundle.module.url(forResource: "emoji", withExtension: "tsv"),
              let data = try? String(contentsOf: url, encoding: .utf8) else {
            return []
        }

        return data.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: "\t", maxSplits: 2).map(String.init)
            guard parts.count >= 2 else { return nil }
            let keywords = parts.count == 3 ? parts[2].split(separator: "|").map(String.init) : []
            return EmojiItem(parts[0], parts[1], keywords)
        }
    }

    static let extraSymbols: [EmojiItem] = [
        EmojiItem("⌘", "command symbol", ["mac", "keyboard"]),
        EmojiItem("⌥", "option symbol", ["mac", "keyboard"]),
        EmojiItem("⇧", "shift symbol", ["mac", "keyboard"]),
        EmojiItem("⌫", "delete symbol", ["backspace", "keyboard"]),
        EmojiItem("→", "right arrow", ["arrow"]),
        EmojiItem("←", "left arrow", ["arrow"]),
        EmojiItem("↑", "up arrow", ["arrow"]),
        EmojiItem("↓", "down arrow", ["arrow"]),
        EmojiItem("•", "bullet", ["dot"]),
        EmojiItem("—", "em dash", ["dash"]),
        EmojiItem("…", "ellipsis", ["dots"])
    ]
}
