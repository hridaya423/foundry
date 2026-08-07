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
    @Published private(set) var selectedIDs: Set<String> = []
    @Published private(set) var backgroundRemovalFileID: String?
    @Published private(set) var backgroundRemovalStatus = ""
    @Published private(set) var backgroundRemovalError: String?
    @Published private(set) var backgroundRemovalNeedsDestination = false
    @Published private(set) var backgroundRemovalEngine: BackgroundRemovalEngine?

    private let backgroundRemovalServices: [BackgroundRemovalEngine: any BackgroundRemoving]
    private var backgroundRemovalTask: Task<Void, Never>?
    private var backgroundRemovalGeneration = 0
    private var selectionAnchorID: String?

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
        guard let selectedID else { return nil }
        return files.first { $0.id == selectedID }
    }

    var selectedFiles: [ShelfFile] {
        let ids: Set<String>
        if selectedIDs.isEmpty, let selectedID {
            ids = [selectedID]
        } else {
            ids = selectedIDs
        }

        return files.filter { ids.contains($0.id) }
    }

    var isRemovingBackground: Bool {
        backgroundRemovalTask != nil
    }

    var canRemoveBackgroundFromSelected: Bool {
        guard isRemovingBackground == false else { return false }
        return selectedFiles.contains { supportsBackgroundRemoval(for: $0) }
    }

    var canTryExperimentalBackgroundRemovalFromSelected: Bool {
        guard isRemovingBackground == false else { return false }
        return selectedFiles.contains { canTryExperimentalBackgroundRemoval(for: $0) }
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
        if selectedIDs.isEmpty, selectedID == nil {
            selectFirst()
        }
    }

    func removeSelected() {
        let selectedIDs = selectedFiles.map(\.id)
        for id in selectedIDs {
            remove(id: id)
        }
    }

    func remove(id: String) {
        if id == backgroundRemovalFileID {
            cancelBackgroundRemoval()
        }
        files.removeAll { $0.id == id }
        selectedIDs.remove(id)
        if selectionAnchorID == id {
            selectionAnchorID = nil
        }
        repairSelection()
    }

    func clear() {
        cancelBackgroundRemoval()
        files.removeAll()
        selectedID = nil
        selectedIDs = []
        selectionAnchorID = nil
    }

    func shutdown() {
        cancelBackgroundRemoval()
    }

    func select(id: String) {
        guard files.contains(where: { $0.id == id }) else { return }
        selectedIDs = [id]
        selectedID = id
        selectionAnchorID = id
    }

    func toggleSelection(id: String) {
        guard files.contains(where: { $0.id == id }) else { return }
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
            if selectedIDs.isEmpty {
                selectedID = nil
                selectionAnchorID = nil
            } else {
                if selectedID == id {
                    selectedID = files.first(where: { selectedIDs.contains($0.id) })?.id
                }
                selectionAnchorID = selectionAnchorID.flatMap { selectedIDs.contains($0) ? $0 : selectedID }
            }
        } else {
            selectedIDs.insert(id)
            selectedID = id
            selectionAnchorID = id
        }
    }

    func extendSelection(to id: String) {
        guard let targetIndex = files.firstIndex(where: { $0.id == id }) else { return }
        let anchorID = selectionAnchorID ?? selectedID ?? id
        guard let anchorIndex = files.firstIndex(where: { $0.id == anchorID }) else {
            select(id: id)
            return
        }
        let range = min(anchorIndex, targetIndex)...max(anchorIndex, targetIndex)
        selectedIDs = Set(files[range].map(\.id))
        selectedID = id
    }

    func selectFirst() {
        guard let firstID = files.first?.id else {
            selectedID = nil
            selectedIDs = []
            selectionAnchorID = nil
            return
        }
        select(id: firstID)
    }

    func moveSelection(offset: Int) {
        guard files.isEmpty == false else { return }
        let currentIndex = selectedID.flatMap { id in files.firstIndex { $0.id == id } } ?? 0
        let nextIndex = min(max(currentIndex + offset, 0), files.count - 1)
        select(id: files[nextIndex].id)
    }

    func revealSelected() {
        let urls = selectedFiles.map(\.url)
        guard urls.isEmpty == false else { return }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    func copySelectedPath() {
        let paths = selectedFiles.map(\.url.path)
        guard paths.isEmpty == false else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(paths.joined(separator: "\n"), forType: .string)
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
        let selectedFiles = selectedFiles
        let supportedFiles = selectedFiles.filter { supportsBackgroundRemoval(for: $0) }
        guard backgroundRemovalTask == nil, supportedFiles.isEmpty == false else { return }
        startBackgroundRemoval(
            files: supportedFiles,
            engine: .vision,
            destinationURL: nil,
            skippedCount: selectedFiles.count - supportedFiles.count
        )
    }

    func removeBackground(using engine: BackgroundRemovalEngine) {
        let selectedFiles = selectedFiles
        let supportedFiles = selectedFiles.filter { supportsBackgroundRemoval(for: $0, using: engine) }
        guard engine != .vision, backgroundRemovalTask == nil, supportedFiles.isEmpty == false else { return }
        startBackgroundRemoval(
            files: supportedFiles,
            engine: engine,
            destinationURL: nil,
            skippedCount: selectedFiles.count - supportedFiles.count
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
            files: [file],
            engine: engine,
            destinationURL: destinationURL,
            skippedCount: 0
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
        files: [ShelfFile],
        engine: BackgroundRemovalEngine,
        destinationURL: URL?,
        skippedCount: Int
    ) {
        guard let service = backgroundRemovalServices[engine] else { return }
        guard files.isEmpty == false else { return }
        let total = files.count
        backgroundRemovalGeneration += 1
        let generation = backgroundRemovalGeneration
        backgroundRemovalTask?.cancel()
        backgroundRemovalFileID = files.first?.id
        backgroundRemovalEngine = engine
        backgroundRemovalStatus = total == 1
            ? (engine == .vision ? "Removing background..." : "Preparing \(engine.title)...")
            : "Preparing \(total) files with \(engine.title)..."
        backgroundRemovalError = nil
        backgroundRemovalNeedsDestination = false

        backgroundRemovalTask = Task { [weak self] in
            var outputURLs: [URL] = []
            var failureMessages: [String] = []
            var hasDestinationFailure = false

            for (index, file) in files.enumerated() {
                guard Task.isCancelled == false, let self else { return }
                self.backgroundRemovalFileID = file.id

                let status: @MainActor @Sendable (String) -> Void = { [weak self] message in
                    guard let self, self.backgroundRemovalGeneration == generation else { return }
                    self.backgroundRemovalStatus = total == 1
                        ? message
                        : "\(index + 1) of \(total): \(message)"
                }

                do {
                    let outputURL = try await service.removeBackground(
                        from: file.url,
                        destinationURL: total == 1 ? destinationURL : nil,
                        status: status
                    )
                    guard Task.isCancelled == false, self.backgroundRemovalGeneration == generation else { return }
                    outputURLs.append(outputURL)
                    self.add(urls: [outputURL])
                } catch is CancellationError {
                    return
                } catch {
                    if (error as? BackgroundRemovalError) == .destinationNotWritable {
                        hasDestinationFailure = true
                    }
                    failureMessages.append(total == 1 ? error.localizedDescription : "\(file.name): \(error.localizedDescription)")
                }
            }

            guard Task.isCancelled == false, let self, self.backgroundRemovalGeneration == generation else { return }
            self.backgroundRemovalTask = nil
            self.backgroundRemovalEngine = failureMessages.isEmpty || total > 1 ? nil : engine
            self.backgroundRemovalFileID = failureMessages.isEmpty || total > 1 ? nil : files[0].id
            self.backgroundRemovalNeedsDestination = total == 1 && hasDestinationFailure

            if failureMessages.isEmpty {
                self.backgroundRemovalError = nil
                self.backgroundRemovalStatus = outputURLs.count == 1 && skippedCount == 0
                    ? "Created \(outputURLs[0].lastPathComponent)"
                    : self.batchStatus(processed: outputURLs.count, skipped: skippedCount)
                self.selectGeneratedOutputs(outputURLs)
            } else {
                self.backgroundRemovalStatus = self.batchStatus(
                    processed: outputURLs.count,
                    skipped: skippedCount,
                    failed: failureMessages.count
                )
                self.backgroundRemovalError = failureMessages.joined(separator: "\n")
                self.selectGeneratedOutputs(outputURLs)
            }
        }
    }

    private func selectGeneratedOutputs(_ outputURLs: [URL]) {
        guard outputURLs.isEmpty == false else { return }
        selectedIDs = Set(outputURLs.map(\.path))
        selectedID = outputURLs.last?.path
        selectionAnchorID = selectedID
    }

    private func repairSelection() {
        selectedIDs = selectedIDs.intersection(Set(files.map(\.id)))
        if selectedIDs.isEmpty {
            selectFirst()
            return
        }
        if selectedID == nil || selectedIDs.contains(selectedID ?? "") == false {
            selectedID = files.first(where: { selectedIDs.contains($0.id) })?.id
        }
        if selectionAnchorID == nil || selectedIDs.contains(selectionAnchorID ?? "") == false {
            selectionAnchorID = selectedID
        }
    }

    private func batchStatus(processed: Int, skipped: Int, failed: Int = 0) -> String {
        var parts = ["Processed \(processed) file\(processed == 1 ? "" : "s")"]
        if failed > 0 {
            parts.append("\(failed) failed")
        }
        if skipped > 0 {
            parts.append("\(skipped) unsupported skipped")
        }
        return parts.joined(separator: ", ")
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
