import AppKit
import Foundation
import Observation

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
    private let contentLimit = 65_536
    private var persistTask: Task<Void, Never>?
    private var visibleItemsCache: [StoredSnippet]?
    private var visibleItemsCacheQuery = ""

    init(store: any SnippetStore = FileSnippetStore()) {
        self.store = store
    }

    var visibleItems: [StoredSnippet] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if trimmed == visibleItemsCacheQuery, let visibleItemsCache { return visibleItemsCache }
        let visibleItems: [StoredSnippet]
        if trimmed.isEmpty {
            visibleItems = items
        } else {
            visibleItems = items.filter {
            $0.title.lowercased().contains(trimmed)
                || $0.content.lowercased().contains(trimmed)
                || $0.keyword.lowercased().contains(trimmed)
                || $0.tags.joined(separator: " ").lowercased().contains(trimmed)
            }
        }
        visibleItemsCacheQuery = trimmed
        visibleItemsCache = visibleItems
        return visibleItems
    }

    var selectedItem: StoredSnippet? {
        visibleItems.first { $0.id == selectedID } ?? visibleItems.first
    }

    var duplicateKeywords: [String] {
        Dictionary(grouping: items.filter { !$0.keyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }, by: { $0.keyword.trimmingCharacters(in: .whitespacesAndNewlines) })
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
        items[index].title = title.isEmpty ? "Untitled Snippet" : title
        items[index].content = String(content.prefix(contentLimit))
        items[index].keyword = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        items[index].tags = tags.filter { $0.isEmpty == false }
        items[index].updatedAt = Date()
        invalidateVisibleItems()
        schedulePersist()
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

    func copySelected() {
        guard let selectedItem else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(SnippetRenderer.render(selectedItem.content).text, forType: .string)
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

    func importFromFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try Data(contentsOf: url)
            let imported = try JSONDecoder().decode([RaycastSnippetFile].self, from: data)
            flushPendingPersistence()
            var added = 0
            for item in imported {
                let title = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
                let content = item.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard title.isEmpty == false, content.isEmpty == false else { continue }
                if items.contains(where: { $0.title == title && $0.content == content }) { continue }
                items.insert(StoredSnippet(title: title, content: String(content.prefix(contentLimit)), keyword: item.keyword ?? ""), at: 0)
                added += 1
            }
            items = sorted(items)
            invalidateVisibleItems()
            keepSelectionValid()
            persist()
            if added > 0 { selectedID = items.first?.id }
        } catch {
            persistenceError = "Could not import snippets: \(error.localizedDescription)"
        }
    }

    func exportToFile() {
        guard items.isEmpty == false else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "foundry-snippets.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let exported = items.map { RaycastSnippetFile(name: $0.title, text: $0.content, keyword: $0.keyword.isEmpty ? nil : $0.keyword) }
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(exported).write(to: url, options: .atomic)
        } catch {
            persistenceError = "Could not export snippets: \(error.localizedDescription)"
        }
    }

    private func persist() {
        items = sorted(items)
        invalidateVisibleItems()
        switch store.save(items) {
        case .success:
            persistenceError = nil
        case let .failure(error):
            persistenceError = "Could not save snippets: \(error.localizedDescription)"
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

private struct RaycastSnippetFile: Codable {
    let name: String
    let text: String
    let keyword: String?
}
