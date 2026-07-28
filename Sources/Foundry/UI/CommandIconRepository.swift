import AppKit

@MainActor
final class CommandIconRepository {
    static let shared = CommandIconRepository()

    private let cache = NSCache<NSString, NSImage>()
    private var inFlight: [String: Task<NSImage, Never>] = [:]

    private init() {
        cache.countLimit = 256
        cache.totalCostLimit = 256 * 64 * 64 * 4
    }

    func image(for path: String) async -> NSImage {
        if let cached = cache.object(forKey: path as NSString) {
            return cached
        }

        if let task = inFlight[path] {
            return await task.value
        }

        let task = Task { @MainActor in
            NSWorkspace.shared.icon(forFile: path)
        }
        inFlight[path] = task
        let image = await task.value
        inFlight[path] = nil
        cache.setObject(image, forKey: path as NSString, cost: max(Int(image.size.width * image.size.height * 4), 1))
        return image
    }
}
