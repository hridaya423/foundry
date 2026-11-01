import AppKit
import Foundation
import Observation
import FoundryServices

@MainActor
@Observable
final class EmojiPickerState {
    var query = "" {
        didSet { keepSelectionValid() }
    }
    var selectedID: String?

    private(set) var recentValues: [String]

    private(set) var columns: Int
    static let columnOptions = [10, 12, 14]
    private let localState: LocalStateStore
    private static let recentLimit = 12
    private static let suggestedValues = ["👍", "😂", "❤️", "🔥", "🎉", "✅"]

    private(set) var skinTone: String
    static let skinTones = ["", "🏻", "🏼", "🏽", "🏾", "🏿"]

    init(localState: LocalStateStore = .shared) {
        self.localState = localState
        self.recentValues = localState.get(\.emojiRecents)
        let storedColumns = localState.get(\.emojiColumns) ?? 12
        self.columns = Self.columnOptions.contains(storedColumns) ? storedColumns : 12
        let storedTone = localState.get(\.emojiSkinTone)
        self.skinTone = Self.skinTones.contains(storedTone) ? storedTone : ""
    }

    var hasRecents: Bool { recentValues.isEmpty == false }

    var recents: [EmojiItem] {
        (hasRecents ? recentValues : Self.suggestedValues).compactMap { value in
            Self.allEmoji.first { $0.value == value }
        }
    }

    func cycleColumns() {
        guard let index = Self.columnOptions.firstIndex(of: columns) else { return }
        columns = Self.columnOptions[(index + 1) % Self.columnOptions.count]
        localState.set(\.emojiColumns, columns)
    }

    func recordRecent(_ value: String) {
        recentValues = Array(([value] + recentValues.filter { $0 != value }).prefix(Self.recentLimit))
        localState.set(\.emojiRecents, recentValues)
    }

    func cycleSkinTone() {
        guard let index = Self.skinTones.firstIndex(of: skinTone) else { return }
        setSkinTone(Self.skinTones[(index + 1) % Self.skinTones.count])
    }

    func setSkinTone(_ tone: String) {
        guard Self.skinTones.contains(tone) else { return }
        skinTone = tone
        localState.set(\.emojiSkinTone, skinTone)
    }

    func toneAppliedValue(_ item: EmojiItem) -> String {
        guard skinTone.isEmpty == false else { return item.value }
        let base = Self.stripTones(item.value)
        guard Self.toneableBases.contains(base) else { return item.value }
        return base + skinTone
    }

    static func stripTones(_ value: String) -> String {
        String(String.UnicodeScalarView(value.unicodeScalars.filter { (0x1F3FB ... 0x1F3FF).contains($0.value) == false }))
    }

    var visibleEmoji: [EmojiItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard trimmed.isEmpty == false else {
            return Self.allEmoji.filter { Self.stripTones($0.value) == $0.value }
        }
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
    func copySelectedEmoji() -> String? {
        guard let selectedEmoji else { return nil }
        let value = toneAppliedValue(selectedEmoji)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
        recordRecent(value)
        return value
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

    static let toneableBases: Set<String> = {
        let values = Set(allEmoji.map(\.value))
        var bases = Set<String>()
        for value in values {
            let base = stripTones(value)
            if base != value, values.contains(base) { bases.insert(base) }
        }
        return bases
    }()

    static func loadEmojiCatalog() -> [EmojiItem] {
        guard let url = Bundle.packagedResources?.url(forResource: "emoji", withExtension: "tsv") else {
            return []
        }
        let data = BestEffort.attempt("load emoji catalog") {
            try String(contentsOf: url, encoding: .utf8)
        }
        guard let data else {
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
