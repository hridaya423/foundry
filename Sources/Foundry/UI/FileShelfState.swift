import AppKit
import Foundation

enum BackgroundRemovalEngine: String, CaseIterable, Identifiable, Sendable {
    case vision
    case ben2

    static let experimental: [Self] = [.ben2]

    var id: String { rawValue }

    var title: String {
        switch self {
        case .vision: "Vision"
        case .ben2: "BEN2"
        }
    }
}

@MainActor
final class FileShelfState: ObservableObject {
    @Published private(set) var files: [ShelfFile] = []
    @Published var selectedID: String?
    @Published private(set) var backgroundRemovalFileID: String?
    @Published private(set) var backgroundRemovalStatus = ""
    @Published private(set) var backgroundRemovalError: String?
    @Published private(set) var backgroundRemovalNeedsDestination = false
    @Published private(set) var backgroundRemovalEngine: BackgroundRemovalEngine?

    private let backgroundRemovalServices: [BackgroundRemovalEngine: any BackgroundRemoving]
    private var backgroundRemovalTask: Task<Void, Never>?
    private var backgroundRemovalGeneration = 0

    init(
        backgroundRemovalService: any BackgroundRemoving = VisionBackgroundRemovalService(),
        ben2Service: any BackgroundRemoving = BEN2BackgroundRemovalService()
    ) {
        self.backgroundRemovalServices = [
            .vision: backgroundRemovalService,
            .ben2: ben2Service
        ]
        backgroundRemovalFileID = nil
        backgroundRemovalEngine = nil
    }

    var experimentalEngines: [BackgroundRemovalEngine] {
        BackgroundRemovalEngine.experimental
    }

    var selectedFile: ShelfFile? {
        files.first { $0.id == selectedID } ?? files.first
    }

    var isRemovingBackground: Bool {
        backgroundRemovalTask != nil
    }

    var canRemoveBackgroundFromSelected: Bool {
        guard isRemovingBackground == false, let selectedFile else { return false }
        return supportsBackgroundRemoval(for: selectedFile)
    }

    var canTryExperimentalBackgroundRemovalFromSelected: Bool {
        guard isRemovingBackground == false, let selectedFile else { return false }
        return experimentalEngines.contains { supportsBackgroundRemoval(for: selectedFile, using: $0) }
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
        if id == backgroundRemovalFileID {
            cancelBackgroundRemoval()
        }
        files.removeAll { $0.id == id }
        selectFirst()
    }

    func clear() {
        cancelBackgroundRemoval()
        files.removeAll()
        selectedID = nil
    }

    func shutdown() {
        cancelBackgroundRemoval()
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

    func supportsBackgroundRemoval(for file: ShelfFile) -> Bool {
        supportsBackgroundRemoval(for: file, using: .vision)
    }

    func supportsBackgroundRemoval(for file: ShelfFile, using engine: BackgroundRemovalEngine) -> Bool {
        backgroundRemovalServices[engine]?.supports(file.url) == true
    }

    func canTryExperimentalBackgroundRemoval(for file: ShelfFile) -> Bool {
        experimentalEngines.contains { supportsBackgroundRemoval(for: file, using: $0) }
    }

    func removeBackgroundFromSelected() {
        guard let selectedFile,
              backgroundRemovalTask == nil,
              supportsBackgroundRemoval(for: selectedFile) else { return }
        startBackgroundRemoval(
            for: selectedFile,
            engine: .vision,
            destinationURL: nil
        )
    }

    func removeBackground(using engine: BackgroundRemovalEngine) {
        guard engine != .vision,
              let selectedFile,
              backgroundRemovalTask == nil,
              supportsBackgroundRemoval(for: selectedFile, using: engine) else { return }
        startBackgroundRemoval(
            for: selectedFile,
            engine: engine,
            destinationURL: nil
        )
    }

    func removeBackgroundWithBEN2() {
        removeBackground(using: .ben2)
    }

    func chooseBackgroundRemovalDestination() {
        guard let fileID = backgroundRemovalFileID ?? selectedFile?.id,
              let file = files.first(where: { $0.id == fileID }) else { return }

        let proposedURL = BackgroundRemovalFileSupport.destinationURL(
            for: file.url,
            defaultStemSuffix: backgroundRemovalSuffix(for: backgroundRemovalEngine ?? .vision)
        )
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.canCreateDirectories = true
        panel.directoryURL = proposedURL.deletingLastPathComponent()
        panel.nameFieldStringValue = proposedURL.lastPathComponent
        guard panel.runModal() == .OK, let destinationURL = panel.url else { return }

        let engine = backgroundRemovalEngine ?? .vision
        startBackgroundRemoval(
            for: file,
            engine: engine,
            destinationURL: destinationURL
        )
    }

    func dismissBackgroundRemovalError() {
        backgroundRemovalError = nil
        backgroundRemovalNeedsDestination = false
    }

    func cancelBackgroundRemoval() {
        guard backgroundRemovalTask != nil || backgroundRemovalFileID != nil || backgroundRemovalError != nil else { return }
        backgroundRemovalGeneration += 1
        backgroundRemovalTask?.cancel()
        backgroundRemovalTask = nil
        backgroundRemovalFileID = nil
        backgroundRemovalEngine = nil
        backgroundRemovalNeedsDestination = false
        backgroundRemovalError = nil
        backgroundRemovalStatus = "Background removal cancelled"
    }

    private func startBackgroundRemoval(
        for file: ShelfFile,
        engine: BackgroundRemovalEngine,
        destinationURL: URL?
    ) {
        guard let service = backgroundRemovalServices[engine] else { return }
        backgroundRemovalGeneration += 1
        let generation = backgroundRemovalGeneration
        backgroundRemovalTask?.cancel()
        backgroundRemovalFileID = file.id
        backgroundRemovalEngine = engine
        backgroundRemovalStatus = engine == .vision
            ? "Removing background..."
            : "Preparing \(engine.title)..."
        backgroundRemovalError = nil
        backgroundRemovalNeedsDestination = false

        backgroundRemovalTask = Task { [weak self] in
            do {
                let status: @MainActor @Sendable (String) -> Void = { [weak self] message in
                    guard let self, self.backgroundRemovalGeneration == generation else { return }
                    self.backgroundRemovalStatus = message
                }
                let outputURL = try await service.removeBackground(
                    from: file.url,
                    destinationURL: destinationURL,
                    status: status
                )
                guard Task.isCancelled == false, let self, self.backgroundRemovalGeneration == generation else { return }
                self.backgroundRemovalTask = nil
                self.backgroundRemovalFileID = nil
                self.backgroundRemovalEngine = nil
                self.backgroundRemovalStatus = "Created \(outputURL.lastPathComponent)"
                self.add(urls: [outputURL])
                self.selectedID = outputURL.path
            } catch is CancellationError {
                return
            } catch {
                guard Task.isCancelled == false, let self, self.backgroundRemovalGeneration == generation else { return }
                self.backgroundRemovalTask = nil
                self.backgroundRemovalStatus = "Background removal failed"
                self.backgroundRemovalError = error.localizedDescription
                self.backgroundRemovalNeedsDestination = (error as? BackgroundRemovalError) == .destinationNotWritable
            }
        }
    }

    private func backgroundRemovalSuffix(for engine: BackgroundRemovalEngine) -> String {
        engine == .vision
            ? " - background removed"
            : " - background removed (\(engine.title))"
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
