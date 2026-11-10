import AppKit
import Foundation
import SwiftUI
import FoundryDomain
import FoundryServices

// Files dropped on the panel surface and the shelf/convert choice flow.
extension CommandPanelState {
    enum DropChoice: CaseIterable {
        case shelf, convert, extractText, compress

        var title: String {
            switch self {
            case .shelf: return "Add to File Shelf"
            case .convert: return "Convert…"
            case .extractText: return "Extract Text"
            case .compress: return "Compress to ZIP"
            }
        }

        var systemIcon: String {
            switch self {
            case .shelf: return "tray.and.arrow.down"
            case .convert: return "arrow.triangle.2.circlepath"
            case .extractText: return "text.viewfinder"
            case .compress: return "archivebox"
            }
        }
    }

    /// Drop choices for the pending files — Extract Text only when every file
    /// is an image the OCR engine can read.
    var dropChoices: [DropChoice] {
        guard let urls = pendingDropURLs, urls.isEmpty == false else { return [] }
        var choices: [DropChoice] = [.shelf, .convert]
        let allImages = urls.allSatisfy {
            ConversionGraph.visionReadExts.contains(ConversionGraph.normalizedExtension(of: $0))
        }
        if allImages { choices.append(.extractText) }
        choices.append(.compress)
        return choices
    }

    func performHaptic(_ pattern: NSHapticFeedbackManager.FeedbackPattern) {
        guard settings.hapticsEnabled else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(pattern, performanceTime: .now)
    }

    func resolveDrop(_ choice: DropChoice) {
        guard let urls = pendingDropURLs else { return }
        pendingDropURLs = nil
        performHaptic(.levelChange)
        switch choice {
        case .shelf:
            shelfFiles(urls)
        case .convert:
            router.openFileConverter(paths: urls.map(\.path))
        case .extractText:
            Task { @MainActor [weak self] in
                _ = await self?.execute(CommandAction(
                    id: "drop.ocr.\(UUID().uuidString)",
                    title: DropChoice.extractText.title,
                    behavior: ExtractTextFromImageAction(paths: urls.map(\.path))
                ), commandID: "foundry.files")
            }
        case .compress:
            for url in urls {
                Task { @MainActor [weak self] in
                    _ = await self?.execute(CommandAction(
                        id: "drop.compress.\(UUID().uuidString)",
                        title: DropChoice.compress.title,
                        behavior: CompressFileAction(path: url.path)
                    ), commandID: "foundry.files")
                }
            }
        }
    }

    func resolveSelectedDrop() -> Bool {
        guard dropChoices.indices.contains(dropSelection) else { return false }
        resolveDrop(dropChoices[dropSelection])
        return true
    }

    func handleDroppedFiles(_ urls: [URL]) {
        if mode == .fileConversion {
            guard urls.isEmpty == false else { return }
            fileConversion.addSources(urls: urls)
            return
        }
        guard urls.isEmpty == false else { return }
        if mode == .fileShelf { return shelfFiles(urls) }
        pendingDropURLs = urls
    }

    private func shelfFiles(_ urls: [URL]) {
        let result = fileShelf.add(urls: urls)
        guard result.didReceiveFiles else {
            showActionFeedback(.failure(String(localized: "Only files can go on the shelf. Drop them from Finder.")))
            return
        }
        if result.addedCount > 0 {
            let noun = result.addedCount == 1 ? "file" : "files"
            let duplicateSuffix = result.duplicateCount > 0 ? " · \(result.duplicateCount) already waiting" : ""
            let rejectedSuffix = result.rejectedCount > 0 ? " · \(result.rejectedCount) unsupported" : ""
            showActionFeedback(.success(String(localized: "Added \(result.addedCount) \(noun) to File Shelf\(duplicateSuffix)\(rejectedSuffix)")))
        } else if result.duplicateCount > 0 {
            let noun = result.duplicateCount == 1 ? "file is" : "files are"
            showActionFeedback(.info(String(localized: "Those \(noun) already on File Shelf")))
        }
        if mode == .search {
            if session.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                session.refreshHomeResults()
            }
        } else if mode != .fileShelf, result.addedCount > 0 {
            router.openFileShelf()
        }
    }
}
