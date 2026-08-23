import AppKit
import Foundation

@MainActor
final class SnippetState: ObservableObject {
    @Published var query = "" {
        didSet { keepSelectionValid() }
    }
    @Published private(set) var items: [StoredSnippet] = []
    @Published var selectedID: String?
    @Published private(set) var persistenceError: String? = nil
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
        persistTask?.cancel()
        query = ""
        load()
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
