import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class EmojiPickerState {
    var query = "" {
        didSet { keepSelectionValid() }
    }
    var selectedID: String?

    private(set) var recentValues: [String]

    private(set) var columns: Int
    private static let columnsKey = "emoji.columns"
    static let columnOptions = [10, 12, 14]
    private let defaults: UserDefaults
    private static let recentsKey = "emoji.recents"
    private static let recentLimit = 12
    private static let suggestedValues = ["👍", "😂", "❤️", "🔥", "🎉", "✅"]

    private(set) var skinTone: String
    static let skinTones = ["", "🏻", "🏼", "🏽", "🏾", "🏿"]
    private static let skinToneKey = "emoji.skinTone"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.recentValues = defaults.stringArray(forKey: Self.recentsKey) ?? []
        let storedColumns = defaults.integer(forKey: Self.columnsKey)
        self.columns = Self.columnOptions.contains(storedColumns) ? storedColumns : 12
        let storedTone = defaults.string(forKey: Self.skinToneKey) ?? ""
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
        defaults.set(columns, forKey: Self.columnsKey)
    }

    func recordRecent(_ value: String) {
        recentValues = Array(([value] + recentValues.filter { $0 != value }).prefix(Self.recentLimit))
        defaults.set(recentValues, forKey: Self.recentsKey)
    }

    func cycleSkinTone() {
        guard let index = Self.skinTones.firstIndex(of: skinTone) else { return }
        skinTone = Self.skinTones[(index + 1) % Self.skinTones.count]
        defaults.set(skinTone, forKey: Self.skinToneKey)
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
    func copySelectedEmoji() -> Bool {
        guard let selectedEmoji else { return false }
        let value = toneAppliedValue(selectedEmoji)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
        recordRecent(value)
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
        guard let url = Bundle.packagedResources?.url(forResource: "emoji", withExtension: "tsv"),
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
