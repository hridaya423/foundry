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

    let columns = 13
    private let localState: LocalStateStore
    private static let recentLimit = 12
    private static let suggestedValues = ["👍", "😂", "❤️", "🔥", "🎉", "✅"]

    private(set) var skinTone: String
    static let skinTones = ["", "🏻", "🏼", "🏽", "🏾", "🏿"]

    init(localState: LocalStateStore = .shared) {
        self.localState = localState
        self.recentValues = localState.get(\.emojiRecents)
        let storedTone = localState.get(\.emojiSkinTone)
        self.skinTone = Self.skinTones.contains(storedTone) ? storedTone : ""
    }

    var hasRecents: Bool { recentValues.isEmpty == false }

    var recents: [EmojiItem] {
        (hasRecents ? recentValues : Self.suggestedValues).compactMap { value in
            Self.allEmoji.first { $0.value == value }
        }
    }

    struct Cell: Identifiable, Hashable {
        let id: String
        let item: EmojiItem
    }

    var hasQuery: Bool { query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false }

    var recentCells: [Cell] {
        guard hasQuery == false else { return [] }
        return recents.map { Cell(id: "recent:" + $0.id, item: $0) }
    }

    var resultCells: [Cell] { visibleEmoji.map { Cell(id: "all:" + $0.id, item: $0) } }

    var cells: [Cell] { recentCells + resultCells }

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

    nonisolated static func stripTones(_ value: String) -> String {
        String(String.UnicodeScalarView(value.unicodeScalars.filter { (0x1F3FB ... 0x1F3FF).contains($0.value) == false }))
    }

    var visibleEmoji: [EmojiItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard trimmed.isEmpty == false else { return Self.browseEmoji }
        return Self.allEmoji.filter { item in
            item.value == trimmed
                || item.name.contains(trimmed)
                || item.keywords.contains { $0.contains(trimmed) }
        }
    }

    var selectedEmoji: EmojiItem? {
        let cells = cells
        guard let selectedID else { return cells.first?.item }
        return (cells.first { $0.id == selectedID } ?? cells.first)?.item
    }

    nonisolated static func prewarmCatalog() {
        Task.detached(priority: .utility) {
            _ = browseEmoji
            _ = toneableBases
        }
    }

    func reset() {
        query = ""
        selectedID = cells.first?.id
    }

    func select(id: String) {
        selectedID = id
    }

    func moveSelection(offset: Int) {
        let cells = cells
        guard cells.isEmpty == false else { return }
        let currentIndex = selectedID.flatMap { id in cells.firstIndex { $0.id == id } } ?? 0
        let nextIndex = min(max(currentIndex + offset, 0), cells.count - 1)
        selectedID = cells[nextIndex].id
    }

    func moveLeft() {
        moveSelection(offset: -1)
    }

    func moveRight() {
        moveSelection(offset: 1)
    }

    func moveUp() {
        moveRows(-1)
    }

    func moveDown() {
        moveRows(1)
    }

    private func moveRows(_ rows: Int) {
        let sections = [recentCells, resultCells].filter { $0.isEmpty == false }
        guard let start = sections.indices.first(where: { section in sections[section].contains { $0.id == selectedID } }),
              let index = sections[start].firstIndex(where: { $0.id == selectedID }) else {
            selectedID = sections.first?.first?.id
            return
        }
        let column = index % columns
        let lastRow = { [columns] (section: Int) in (sections[section].count - 1) / columns }
        var section = start
        var row = index / columns + rows
        if row < 0 {
            guard section > 0 else { return }
            section -= 1
            row = lastRow(section)
        } else if row > lastRow(section) {
            guard section < sections.count - 1 else {
                selectedID = sections[section].last?.id
                return
            }
            section += 1
            row = 0
        }
        selectedID = sections[section][min(row * columns + column, sections[section].count - 1)].id
    }

    func takeSelectedEmoji() -> String? {
        guard let selectedEmoji else { return nil }
        let value = toneAppliedValue(selectedEmoji)
        recordRecent(value)
        return value
    }

    private func keepSelectionValid() {
        let cells = cells
        if let selectedID, cells.contains(where: { $0.id == selectedID }) {
            return
        }
        selectedID = cells.first?.id
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
    nonisolated static let allEmoji: [EmojiItem] = loadEmojiCatalog() + extraSymbols

    nonisolated static let browseEmoji = allEmoji.filter { stripTones($0.value) == $0.value }

    nonisolated static let toneableBases: Set<String> = {
        let values = Set(allEmoji.map(\.value))
        var bases = Set<String>()
        for value in values {
            let base = stripTones(value)
            if base != value, values.contains(base) { bases.insert(base) }
        }
        return bases
    }()

    nonisolated static func loadEmojiCatalog() -> [EmojiItem] {
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

    nonisolated static let extraSymbols: [EmojiItem] = [
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
