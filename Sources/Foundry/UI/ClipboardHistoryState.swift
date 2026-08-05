import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers
import FoundryServices

@MainActor
final class ClipboardHistoryState: ObservableObject {
    @Published var query = "" {
        didSet { keepSelectionValid() }
    }
    @Published private(set) var items: [ClipboardHistoryItem] = []
    @Published var selectedID: String?

    private var timer: Timer?
    private var lastChangeCount = NSPasteboard.general.changeCount
    private let diagnostics = DiagnosticsService()

    var visibleItems: [ClipboardHistoryItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard trimmed.isEmpty == false else { return items }
        return items.filter { item in
            item.title.lowercased().contains(trimmed)
                || item.subtitle.lowercased().contains(trimmed)
                || item.kindLabel.lowercased().contains(trimmed)
        }
    }

    var selectedItem: ClipboardHistoryItem? {
        visibleItems.first { $0.id == selectedID } ?? visibleItems.first
    }

    func start() {
        guard timer == nil else { return }
        captureCurrentPasteboard()
        timer = Timer.scheduledTimer(withTimeInterval: 0.7, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.captureIfChanged() }
        }
        timer?.tolerance = 0.2
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func reset() {
        query = ""
        selectedID = visibleItems.first?.id
    }

    func select(id: String) {
        selectedID = id
    }

    func moveSelection(offset: Int) {
        let items = visibleItems
        guard items.isEmpty == false else { return }
        let currentIndex = selectedID.flatMap { id in items.firstIndex { $0.id == id } } ?? 0
        let nextIndex = min(max(currentIndex + offset, 0), items.count - 1)
        selectedID = items[nextIndex].id
    }

    func copySelected() {
        guard let selectedItem else { return }
        copy(item: selectedItem)
    }

    func removeSelected() {
        guard let selectedItem else { return }
        items.removeAll { $0.id == selectedItem.id }
        keepSelectionValid()
    }

    func clear() {
        items.removeAll()
        selectedID = nil
    }

    func addSelectedFiles(to fileShelf: FileShelfState) {
        guard let selectedItem, case let .files(urls) = selectedItem.payload else { return }
        fileShelf.add(urls: urls)
    }

    private func captureIfChanged() {
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount
        captureCurrentPasteboard()
    }

    private func captureCurrentPasteboard() {
        let span = diagnostics.startSpan("clipboard.capture")
        defer { diagnostics.endSpan(span) }
        guard let item = ClipboardHistoryItem.current() else { return }
        items.removeAll { $0.signature == item.signature }
        items.insert(item, at: 0)
        if items.count > ClipboardHistoryPolicy.maxItems {
            items.removeLast(items.count - ClipboardHistoryPolicy.maxItems)
        }
        trimToMemoryBudget()
        keepSelectionValid()
    }

    private func trimToMemoryBudget() {
        var total = items.reduce(0) { $0 + $1.memoryCost }
        while total > ClipboardHistoryPolicy.maxBytes, items.count > 1 {
            guard let removed = items.popLast() else { break }
            total -= removed.memoryCost
        }
    }

    private func copy(item: ClipboardHistoryItem) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        switch item.payload {
        case let .text(value):
            pasteboard.setString(value, forType: .string)
        case let .files(urls):
            pasteboard.writeObjects(urls as [NSURL])
        case let .image(data):
            if let image = NSImage(data: data) {
                pasteboard.writeObjects([image])
            }
        }
        lastChangeCount = pasteboard.changeCount
    }

    private func keepSelectionValid() {
        let visible = visibleItems
        if let selectedID, visible.contains(where: { $0.id == selectedID }) {
            return
        }
        selectedID = visible.first?.id
    }
}

struct ClipboardHistoryItem: Identifiable, Hashable {
    let id: String
    let createdAt: Date
    let payload: ClipboardPayload
    let signature: String
    let imageWidth: Int?
    let imageHeight: Int?

    init(payload: ClipboardPayload, signature: String, imageWidth: Int? = nil, imageHeight: Int? = nil) {
        self.id = UUID().uuidString
        self.createdAt = Date()
        self.payload = payload
        self.signature = signature
        self.imageWidth = imageWidth
        self.imageHeight = imageHeight
    }

    var memoryCost: Int {
        switch payload {
        case let .text(value):
            return value.utf8.count
        case let .files(urls):
            return urls.reduce(0) { $0 + $1.path.utf8.count }
        case let .image(data):
            return data.count
        }
    }

    var title: String {
        switch payload {
        case let .text(value):
            let firstLine = value.components(separatedBy: .newlines).first ?? value
            return firstLine.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Text" : firstLine
        case let .files(urls):
            return urls.count == 1 ? urls[0].lastPathComponent : "\(urls.count) files"
        case .image:
            if let imageWidth, let imageHeight {
                return "Image \(imageWidth)×\(imageHeight)"
            }
            return "Image"
        }
    }

    var subtitle: String {
        switch payload {
        case let .text(value):
            return "\(value.count) chars"
        case let .files(urls):
            return urls.first?.deletingLastPathComponent().path.replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~") ?? "Files"
        case let .image(data):
            return ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file)
        }
    }

    var timeLabel: String {
        let seconds = max(0, Int(Date().timeIntervalSince(createdAt)))
        if seconds < 60 { return "now" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m ago" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h ago" }
        return "\(hours / 24)d ago"
    }

    var kindLabel: String {
        switch payload {
        case .text: return "Text"
        case .files: return "Files"
        case .image: return "Image"
        }
    }

    var systemImage: String {
        switch payload {
        case .text: return "doc.text"
        case .files: return "doc.on.doc"
        case .image: return "photo"
        }
    }

    static func current() -> ClipboardHistoryItem? {
        let pasteboard = NSPasteboard.general
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL], urls.isEmpty == false {
            let signature = "files:" + urls.map(\.path).joined(separator: "|")
            return ClipboardHistoryItem(payload: .files(urls), signature: signature)
        }
        if let image = NSImage(pasteboard: pasteboard) {
            if let compressed = compressedImageData(from: image) {
                return ClipboardHistoryItem(
                    payload: .image(compressed.data),
                    signature: "image:\(compressed.data.hashValue):\(compressed.data.count)",
                    imageWidth: compressed.width,
                    imageHeight: compressed.height
                )
            }
            if let data = image.tiffRepresentation, data.count <= ClipboardHistoryPolicy.maxImageBytes {
                return ClipboardHistoryItem(
                    payload: .image(data),
                    signature: "image:\(data.hashValue):\(data.count)",
                    imageWidth: Int(image.size.width),
                    imageHeight: Int(image.size.height)
                )
            }
        }
        if let text = pasteboard.string(forType: .string), text.isEmpty == false {
            let storedText = String(decoding: text.utf8.prefix(ClipboardHistoryPolicy.maxTextBytes), as: UTF8.self)
            return ClipboardHistoryItem(payload: .text(storedText), signature: "text:\(storedText.hashValue):\(storedText.utf8.count)")
        }
        return nil
    }

    private static func compressedImageData(from image: NSImage) -> (data: Data, width: Int, height: Int)? {
        guard let tiff = image.tiffRepresentation,
              let source = CGImageSourceCreateWithData(tiff as CFData, nil) else { return nil }

        let dimensions = [1600, 1200, 800, 600, 400]
        let qualities: [Double] = [0.78, 0.6, 0.4, 0.25]
        for dimension in dimensions {
            let options: CFDictionary = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: dimension
            ] as CFDictionary
            guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else { continue }

            for quality in qualities {
                let output = NSMutableData()
                guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else { continue }
                CGImageDestinationAddImage(destination, thumbnail, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
                guard CGImageDestinationFinalize(destination), output.length <= ClipboardHistoryPolicy.maxImageBytes else { continue }
                return (
                    Data(bytes: output.bytes, count: output.length),
                    thumbnail.width,
                    thumbnail.height
                )
            }
        }
        return nil
    }

}

enum ClipboardHistoryPolicy {
    static let maxItems = 40
    static let maxBytes = 16 * 1024 * 1024
    static let maxImageBytes = 4 * 1024 * 1024
    static let maxTextBytes = 2 * 1024 * 1024
}

enum ClipboardPayload: Hashable {
    case text(String)
    case files([URL])
    case image(Data)
}
