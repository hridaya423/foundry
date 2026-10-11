import AppKit

@MainActor
final class CommandIconRepository {
    static let shared = CommandIconRepository()

    private let cache = NSCache<NSString, NSImage>()
    private var inFlight: [String: Task<IconBox, Never>] = [:]
    private var inFlightRemote: [String: Task<NSImage?, Never>] = [:]
    private let session: URLSession

    private struct IconBox: @unchecked Sendable { let image: NSImage }

    private init() {
        cache.countLimit = 256
        cache.totalCostLimit = 256 * 64 * 64 * 4
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 5
        configuration.urlCache = URLCache(memoryCapacity: 8 * 1024 * 1024, diskCapacity: 32 * 1024 * 1024)
        session = URLSession(configuration: configuration)
    }

    /// Already-loaded icon — the row can render it without a placeholder
    /// flash. Misses return nil; callers then go through the async path.
    func cachedImage(for path: String) -> NSImage? {
        cache.object(forKey: path as NSString)
    }

    func cachedImage(forRemoteURL url: URL) -> NSImage? {
        cache.object(forKey: url.absoluteString as NSString)
    }

    /// Fetch icons the panel is about to show so the async path is already
    /// warm — cheap: cache hits and in-flight dedup do the work.
    func prewarm(paths: [String], remoteURLs: [URL]) {
        for path in paths where cache.object(forKey: path as NSString) == nil {
            Task { _ = await image(for: path) }
        }
        for url in remoteURLs where cache.object(forKey: url.absoluteString as NSString) == nil {
            Task { _ = await image(forRemoteURL: url) }
        }
    }

    func image(for path: String) async -> NSImage {
        if let cached = cache.object(forKey: path as NSString) {
            return cached
        }

        if let task = inFlight[path] {
            return await task.value.image
        }

        let task = Task.detached(priority: .utility) {
            IconBox(image: NSWorkspace.shared.icon(forFile: path))
        }
        inFlight[path] = task
        let image = await task.value.image
        inFlight[path] = nil
        cache.setObject(image, forKey: path as NSString, cost: max(Int(image.size.width * image.size.height * 4), 1))
        return image
    }

    func image(forRemoteURL url: URL) async -> NSImage? {
        let key = url.absoluteString
        if let cached = cache.object(forKey: key as NSString) {
            return cached
        }
        if let task = inFlightRemote[key] {
            return await task.value
        }
        let task = Task.detached(priority: .utility) { [session] () -> NSImage? in
            guard let (data, response) = try? await session.data(from: url),
                  let http = response as? HTTPURLResponse, http.statusCode == 200,
                  (http.value(forHTTPHeaderField: "Content-Type") ?? "").hasPrefix("image/") else {
                return nil
            }
            return NSImage(data: data)
        }
        inFlightRemote[key] = task
        let image = await task.value
        inFlightRemote[key] = nil
        guard let image else { return nil }
        cache.setObject(image, forKey: key as NSString, cost: max(Int(image.size.width * image.size.height * 4), 1))
        return image
    }
}
