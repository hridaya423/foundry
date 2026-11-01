import AppKit
import Foundation
import Observation
import FoundryDomain

@MainActor
@Observable
final class SnippetState {
    var query = "" {
        didSet { keepSelectionValid() }
    }
    private(set) var items: [StoredSnippet] = []
    var selectedID: String?
    private(set) var persistenceError: String? = nil
    private let store: any SnippetStore
    private let localState: LocalStateStore
    private let contentLimit = 65_536
    private var persistTask: Task<Void, Never>?
    private var visibleItemsCache: [StoredSnippet]?
    private var visibleItemsCacheQuery = ""
    private var exportFormatTarget: FormatPickerTarget?
    var selectedTag: String? {
        didSet { keepSelectionValid() }
    }

    enum SortMode: String, CaseIterable {
        case recent = "Recently updated"
        case title = "Title"
        case mostUsed = "Most used"
    }
    var sortMode: SortMode = .recent {
        didSet { invalidateVisibleItems(); keepSelectionValid() }
    }

    /// Tags present across the library, sorted by frequency — drives the
    /// filter chips row.
    var allTags: [String] {
        var counts: [String: Int] = [:]
        for item in items { for tag in item.tags { counts[tag, default: 0] += 1 } }
        return counts.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }.map(\.key)
    }

    init(store: any SnippetStore = FileSnippetStore(), localState: LocalStateStore = .shared) {
        self.store = store
        self.localState = localState
    }

    var visibleItems: [StoredSnippet] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let cacheKey = "\(trimmed)\u{0}\(selectedTag ?? "")"
        if cacheKey == visibleItemsCacheQuery, let visibleItemsCache { return visibleItemsCache }
        var filtered = items
        if let selectedTag {
            filtered = filtered.filter { $0.tags.contains(selectedTag) }
        }
        let visibleItems: [StoredSnippet]
        if trimmed.isEmpty {
            visibleItems = filtered
        } else {
            visibleItems = filtered.filter {
            $0.title.lowercased().contains(trimmed)
                || $0.content.lowercased().contains(trimmed)
                || $0.keyword.lowercased().contains(trimmed)
                || $0.tags.joined(separator: " ").lowercased().contains(trimmed)
            }
        }
        let sortedItems: [StoredSnippet]
        switch sortMode {
        case .recent:
            sortedItems = visibleItems
        case .title:
            sortedItems = visibleItems.sorted {
                if $0.isPinned != $1.isPinned { return $0.isPinned && !$1.isPinned }
                return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            }
        case .mostUsed:
            sortedItems = visibleItems.sorted {
                if $0.isPinned != $1.isPinned { return $0.isPinned && !$1.isPinned }
                if $0.useCount != $1.useCount { return $0.useCount > $1.useCount }
                return $0.updatedAt > $1.updatedAt
            }
        }
        visibleItemsCacheQuery = cacheKey
        visibleItemsCache = sortedItems
        return sortedItems
    }

    var selectedItem: StoredSnippet? {
        visibleItems.first { $0.id == selectedID } ?? visibleItems.first
    }

    var duplicateKeywords: [String] {
        Dictionary(grouping: items.filter { !$0.keyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty },
            by: { $0.keyword.trimmingCharacters(in: .whitespacesAndNewlines) })
            .filter { $0.value.count > 1 }
            .keys.sorted()
    }

    var expansionAvailabilityMessage: String {
        "Auto-expansion is unavailable in secure fields and excluded apps."
    }

    func load() {
        items = sorted(store.load())
        invalidateVisibleItems()
        keepSelectionValid()
    }

    func reset() {
        flushPendingPersistence()
        query = ""
        load()
    }

    func flushPendingPersistence() {
        guard persistTask != nil else { return }
        persistTask?.cancel()
        persistTask = nil
        persist()
    }

    func newSnippet() {
        let snippet = StoredSnippet(title: "Untitled Snippet")
        items.insert(snippet, at: 0)
        selectedID = snippet.id
        persist()
    }

    func updateSelected(title: String, content: String, keyword: String, tags: [String]) {
        guard let selectedID, let index = items.firstIndex(where: { $0.id == selectedID }) else { return }
        var edited = items[index]
        edited.title = title.isEmpty ? "Untitled Snippet" : title
        edited.content = String(content.prefix(contentLimit))
        edited.keyword = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        edited.tags = tags.filter { $0.isEmpty == false }
        guard edited.title != items[index].title || edited.content != items[index].content
            || edited.keyword != items[index].keyword || edited.tags != items[index].tags else { return }
        edited.updatedAt = Date()
        items[index] = edited
        invalidateVisibleItems()
        schedulePersist()
    }

    func duplicateSelected() {
        guard let selectedItem else { return }
        var copy = StoredSnippet(title: String(localized: "\(selectedItem.title) copy"), content: selectedItem.content, tags: selectedItem.tags)
        copy.keyword = ""
        items.insert(copy, at: 0)
        items = sorted(items)
        invalidateVisibleItems()
        selectedID = copy.id
        persist()
    }

    func togglePinnedSelected() {
        guard let selectedID, let index = items.firstIndex(where: { $0.id == selectedID }) else { return }
        items[index].isPinned.toggle()
        items[index].updatedAt = Date()
        persist()
    }

    func removeSelected() {
        guard let selectedID else { return }
        items.removeAll { $0.id == selectedID }
        invalidateVisibleItems()
        keepSelectionValid()
        persist()
    }

    func copySelected(arguments: [String: String] = [:]) {
        guard let selectedItem else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(SnippetRenderer.render(selectedItem.content, arguments: arguments).text, forType: .string)
        markUsed(id: selectedItem.id)
    }

    func markUsed(id: String) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].recordUse()
        invalidateVisibleItems()
        schedulePersist()
    }

    func moveSelection(offset: Int) {
        let visible = visibleItems
        guard visible.isEmpty == false else { return }
        let currentIndex = selectedID.flatMap { id in visible.firstIndex { $0.id == id } } ?? 0
        let nextIndex = min(max(currentIndex + offset, 0), visible.count - 1)
        selectedID = visible[nextIndex].id
    }

    func select(id: String) {
        selectedID = id
    }

    @discardableResult
    func add(_ incoming: [StoredSnippet]) -> Int {
        flushPendingPersistence()
        var added = 0
        for var snippet in incoming {
            snippet.title = snippet.title.trimmingCharacters(in: .whitespacesAndNewlines)
            snippet.content = String(snippet.content.trimmingCharacters(in: .whitespacesAndNewlines).prefix(contentLimit))
            guard snippet.title.isEmpty == false, snippet.content.isEmpty == false,
                  items.contains(where: { $0.title == snippet.title && $0.content == snippet.content }) == false else { continue }
            items.insert(snippet, at: 0)
            added += 1
        }
        guard added > 0 else { return 0 }
        items = sorted(items)
        invalidateVisibleItems()
        keepSelectionValid()
        persist()
        selectedID = items.first?.id
        return added
    }

    @ObservationIgnored var onFeedback: ((ActionFeedback) -> Void)?

    nonisolated static func importSummary(added: Int, total: Int) -> String {
        guard added > 0 else { return String(localized: "No new snippets in that file") }
        let skipped = total - added
        return skipped > 0
            ? String(localized: "Imported \(added) snippets · \(skipped) already in your library")
            : String(localized: "Imported \(added) snippets")
    }

    func importFromFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try Data(contentsOf: url)
            let imported = try JSONDecoder().decode([RaycastSnippetFile].self, from: data)
            let added = add(imported.map { StoredSnippet(title: $0.name, content: $0.text, keyword: $0.keyword ?? "") })
            onFeedback?(.success(Self.importSummary(added: added, total: imported.count)))
        } catch {
            persistenceError = String(localized: "Could not import snippets: \(error.localizedDescription)")
        }
    }

    func exportToFile() {
        guard items.isEmpty == false else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json, .commaSeparatedText]
        panel.nameFieldStringValue = "foundry-snippets.json"
        let formatPicker = NSPopUpButton(frame: .zero, pullsDown: false)
        formatPicker.addItems(withTitles: ["JSON (Raycast)", "CSV"])
        formatPicker.selectItem(at: 0)
        let actionTarget = FormatPickerTarget { [weak panel] index in
            panel?.nameFieldStringValue = "foundry-snippets." + (index == 1 ? "csv" : "json")
        }
        formatPicker.target = actionTarget
        formatPicker.action = #selector(FormatPickerTarget.changed(_:))
        exportFormatTarget = actionTarget
        let accessory = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 32))
        formatPicker.frame = NSRect(x: 0, y: 4, width: 180, height: 24)
        accessory.addSubview(formatPicker)
        panel.accessoryView = accessory
        if let lastDirectory = localState.get(\.snippetsLastExportDirectory) {
            panel.directoryURL = URL(fileURLWithPath: lastDirectory)
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        localState.set(\.snippetsLastExportDirectory, url.deletingLastPathComponent().path)
        do {
            if url.pathExtension.lowercased() == "csv" {
                try Data(csvExport().utf8).write(to: url, options: .atomic)
            } else {
                let exported = items.map { RaycastSnippetFile(name: $0.title, text: $0.content, keyword: $0.keyword.isEmpty ? nil : $0.keyword) }
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                try encoder.encode(exported).write(to: url, options: .atomic)
            }
            onFeedback?(.success(String(localized: "Exported \(items.count) snippets to \(url.lastPathComponent)")))
        } catch {
            persistenceError = String(localized: "Could not export snippets: \(error.localizedDescription)")
        }
    }

    func csvExport() -> String {
        func field(_ value: String) -> String {
            "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        var lines = ["name,keyword,text,uses,last_used"]
        for item in items {
            let lastUsed = item.lastUsedAt.map { ISO8601DateFormatter().string(from: $0) } ?? ""
            lines.append([item.title, item.keyword, item.content, "\(item.useCount)", lastUsed].map(field).joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private func persist() {
        items = sorted(items)
        invalidateVisibleItems()
        switch store.save(items) {
        case .success:
            persistenceError = nil
        case let .failure(error):
            persistenceError = String(localized: "Could not save snippets: \(error.localizedDescription)")
        }
    }

    private func schedulePersist() {
        persistTask?.cancel()
        persistTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(350))
            } catch {
                return
            }
            guard let self else { return }
            self.persist()
        }
    }

    private func sorted(_ items: [StoredSnippet]) -> [StoredSnippet] {
        items.sorted {
            if $0.isPinned != $1.isPinned { return $0.isPinned && !$1.isPinned }
            return $0.updatedAt > $1.updatedAt
        }
    }

    private func keepSelectionValid() {
        let visible = visibleItems
        if let selectedID, visible.contains(where: { $0.id == selectedID }) { return }
        selectedID = visible.first?.id
    }

    private func invalidateVisibleItems() {
        visibleItemsCache = nil
    }
}

struct RaycastSnippetFile: Codable {
    let name: String
    let text: String
    let keyword: String?
}

private final class FormatPickerTarget: NSObject {
    private let handler: (Int) -> Void
    init(_ handler: @escaping (Int) -> Void) { self.handler = handler }
    @objc @MainActor func changed(_ sender: NSPopUpButton) { handler(sender.indexOfSelectedItem) }
}
