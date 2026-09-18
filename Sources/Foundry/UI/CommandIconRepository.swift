import AppKit

@MainActor
final class CommandIconRepository {
    static let shared = CommandIconRepository()

    private let cache = NSCache<NSString, NSImage>()
    private var inFlight: [String: Task<IconBox, Never>] = [:]
    private var inFlightRemote: [String: Task<NSImage?, Never>] = [:]

    private struct IconBox: @unchecked Sendable { let image: NSImage }

    private init() {
        cache.countLimit = 256
        cache.totalCostLimit = 256 * 64 * 64 * 4
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
        let task = Task.detached(priority: .utility) { () -> NSImage? in
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 5
            let session = URLSession(configuration: configuration)
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
