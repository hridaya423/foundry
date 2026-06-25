import AppKit
import Foundation

@MainActor
final class FileShelfState: ObservableObject {
    @Published private(set) var files: [ShelfFile] = []
    @Published var selectedID: String?

    var selectedFile: ShelfFile? {
        files.first { $0.id == selectedID } ?? files.first
    }

    var summary: String {
        files.isEmpty ? "Drop files here" : "\(files.count) file\(files.count == 1 ? "" : "s") waiting"
    }

    func add(urls: [URL]) {
        let existing = Set(files.map(\.url))
        let newFiles = urls
            .filter { $0.isFileURL && existing.contains($0) == false }
            .map(ShelfFile.init(url:))
        guard newFiles.isEmpty == false else { return }
        files.append(contentsOf: newFiles)
        selectedID = selectedID ?? files.first?.id
    }

    func removeSelected() {
        guard let selectedFile else { return }
        remove(id: selectedFile.id)
    }

    func remove(id: String) {
        files.removeAll { $0.id == id }
        selectFirst()
    }

    func clear() {
        files.removeAll()
        selectedID = nil
    }

    func select(id: String) {
        selectedID = id
    }

    func selectFirst() {
        selectedID = files.first?.id
    }

    func moveSelection(offset: Int) {
        guard files.isEmpty == false else { return }
        let currentIndex = selectedID.flatMap { id in files.firstIndex { $0.id == id } } ?? 0
        let nextIndex = min(max(currentIndex + offset, 0), files.count - 1)
        selectedID = files[nextIndex].id
    }

    func revealSelected() {
        guard let selectedFile else { return }
        NSWorkspace.shared.activateFileViewerSelecting([selectedFile.url])
    }

    func copySelectedPath() {
        guard let selectedFile else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(selectedFile.url.path, forType: .string)
    }
}

struct ShelfFile: Identifiable, Hashable {
    let id: String
    let url: URL

    init(url: URL) {
        self.url = url
        self.id = url.path
    }

    var name: String {
        url.lastPathComponent
    }

    var location: String {
        let parent = url.deletingLastPathComponent().path
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if parent == home { return "~" }
        if parent.hasPrefix(home + "/") { return "~" + parent.dropFirst(home.count) }
        return parent
    }
}
