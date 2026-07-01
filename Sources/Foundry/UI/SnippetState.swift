import AppKit
import Foundation

@MainActor
final class SnippetState: ObservableObject {
    @Published var query = "" {
        didSet { keepSelectionValid() }
    }
    @Published private(set) var items: [StoredSnippet] = []
    @Published var selectedID: String?
    private let contentLimit = 65_536

    var visibleItems: [StoredSnippet] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard trimmed.isEmpty == false else { return items }
        return items.filter {
            $0.title.lowercased().contains(trimmed)
                || $0.content.lowercased().contains(trimmed)
                || $0.keyword.lowercased().contains(trimmed)
                || $0.tags.joined(separator: " ").lowercased().contains(trimmed)
        }
    }

    var selectedItem: StoredSnippet? {
        visibleItems.first { $0.id == selectedID } ?? visibleItems.first
    }

    func load() {
        items = sorted(LibraryPersistence.loadSnippets())
        keepSelectionValid()
    }

    func reset() {
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
        items[index].keyword = keyword
        items[index].tags = tags.filter { $0.isEmpty == false }
        items[index].updatedAt = Date()
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
        keepSelectionValid()
        persist()
    }

    func copySelected() {
        guard let selectedItem else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(SnippetRenderer.render(selectedItem.content), forType: .string)
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
        LibraryPersistence.saveSnippets(items)
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
}
