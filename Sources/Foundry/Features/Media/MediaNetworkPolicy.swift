import Foundation
import Darwin

protocol MediaArtifactFileSystem: Sendable {
    func createDirectory(at url: URL) throws
    func reserveFile(at url: URL) throws
    func createFile(at url: URL) throws
    func append(_ data: Data, to url: URL) throws
    func fileExists(at url: URL) -> Bool
    func readData(at url: URL) throws -> Data
    func moveItem(at source: URL, to destination: URL) throws
    func removeItem(at url: URL) throws
    func temporaryFile(prefix: String) throws -> URL
    func temporaryDirectory(prefix: String) throws -> URL
    func fileSize(at url: URL) throws -> Int64
    func regularFiles(in directory: URL) throws -> [URL]
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}

extension FileManager: MediaArtifactFileSystem {
    func createDirectory(at url: URL) throws {
        try createDirectory(at: url, withIntermediateDirectories: true)
    }

    func reserveFile(at url: URL) throws {
        let descriptor = open(url.path, O_WRONLY | O_CREAT | O_EXCL, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else {
            if errno == EEXIST { throw CocoaError(.fileWriteFileExists) }
            throw MediaNetworkPolicyFailure.destinationUnavailable
        }
        close(descriptor)
    }

    func createFile(at url: URL) throws {
        guard createFile(atPath: url.path, contents: nil) else { throw MediaNetworkPolicyFailure.destinationUnavailable }
    }

    func append(_ data: Data, to url: URL) throws {
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
        try handle.close()
    }
    func fileExists(at url: URL) -> Bool { fileExists(atPath: url.path) }

    func readData(at url: URL) throws -> Data { try Data(contentsOf: url) }
    func temporaryFile(prefix: String) throws -> URL {
        let url = temporaryDirectory.appendingPathComponent("\(prefix)-\(UUID().uuidString)")
        try reserveFile(at: url)
        return url
    }
    func temporaryDirectory(prefix: String) throws -> URL {
        let url = temporaryDirectory.appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
        try createDirectory(at: url)
        return url
    }
    func fileSize(at url: URL) throws -> Int64 {
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        return Int64(values.fileSize ?? 0)
    }
    func regularFiles(in directory: URL) throws -> [URL] {
        try contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])
            .filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }
    }
}

protocol MediaNetworkAddressLocating: Sendable {
    func addresses(for host: String) -> [String]
}

struct SystemMediaNetworkAddressLocator: MediaNetworkAddressLocating {
    func addresses(for host: String) -> [String] {
        var hints = addrinfo(ai_flags: AI_ADDRCONFIG, ai_family: AF_UNSPEC, ai_socktype: SOCK_STREAM, ai_protocol: IPPROTO_TCP, ai_addrlen: 0, ai_canonname: nil, ai_addr: nil, ai_next: nil)
        var result: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, nil, &hints, &result) == 0, let result else { return [] }
        defer { freeaddrinfo(result) }
        var addresses: [String] = []
        for pointer in sequence(first: result, next: { $0.pointee.ai_next }) {
            var hostBuffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(pointer.pointee.ai_addr, pointer.pointee.ai_addrlen, &hostBuffer, socklen_t(hostBuffer.count), nil, 0, NI_NUMERICHOST) == 0 else { continue }
            let bytes = hostBuffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
            addresses.append(String(decoding: bytes, as: UTF8.self))
        }
        return addresses
    }
}

enum MediaNetworkPolicyFailure: Error, Equatable, LocalizedError {
    case unsupportedScheme
    case blockedDestination
    case tooManyRedirects
    case invalidStatus(Int)
    case responseTooLarge
    case truncatedBody
    case mimeMismatch
    case invalidSignature
    case destinationUnavailable

    var errorDescription: String? {
        switch self {
        case .unsupportedScheme: return "Only HTTP and HTTPS media URLs are allowed"
        case .blockedDestination: return "The media destination is not publicly reachable"
        case .tooManyRedirects: return "Too many media redirects"
        case let .invalidStatus(status): return "Media server returned HTTP \(status)"
        case .responseTooLarge: return "Media response exceeds the size limit"
        case .truncatedBody: return "Media response was truncated"
        case .mimeMismatch: return "Media response has an unexpected MIME type"
        case .invalidSignature: return "Media response is not a recognized media file"
        case .destinationUnavailable: return "A destination filename could not be reserved"
        }
    }
}

struct MediaNetworkPolicy: Sendable {
    private static let reservations = DestinationReservations()

    let locator: any MediaNetworkAddressLocating
    let maxRedirects: Int
    let maxBytes: Int64

    init(locator: any MediaNetworkAddressLocating = SystemMediaNetworkAddressLocator(), maxRedirects: Int = 5, maxBytes: Int64 = 512 * 1024 * 1024) {
        self.locator = locator
        self.maxRedirects = max(0, maxRedirects)
        self.maxBytes = max(1, maxBytes)
    }

    func validate(_ url: URL) throws {
        guard ["http", "https"].contains(url.scheme?.lowercased()) else { throw MediaNetworkPolicyFailure.blockedDestination }
        guard let host = url.host, host.isEmpty == false, isPublic(host: host) else { throw MediaNetworkPolicyFailure.blockedDestination }
    }

    func pinnedURL(for url: URL) throws -> (url: URL, host: String) {
        try validate(url)
        guard let host = url.host, let address = locator.addresses(for: host).first(where: { !Self.isBlockedIP($0) }) else {
            throw MediaNetworkPolicyFailure.blockedDestination
        }
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.host = address.contains(":") ? "[\(address)]" : address
        guard let pinned = components?.url else { throw MediaNetworkPolicyFailure.blockedDestination }
        return (pinned, host)
    }

    func validateRedirect(to url: URL, count: Int) throws {
        guard count < maxRedirects else { throw MediaNetworkPolicyFailure.tooManyRedirects }
        try validate(url)
    }

    func validate(response: HTTPURLResponse, prefix: Data, receivedBytes: Int64, expectedExtension: String? = nil) throws {
        guard (200..<300).contains(response.statusCode) else { throw MediaNetworkPolicyFailure.invalidStatus(response.statusCode) }
        if let length = response.value(forHTTPHeaderField: "Content-Length"), let length = Int64(length), length > maxBytes { throw MediaNetworkPolicyFailure.responseTooLarge }
        guard receivedBytes <= maxBytes else { throw MediaNetworkPolicyFailure.responseTooLarge }
        guard let mime = response.mimeType?.lowercased(), isMediaMIME(mime) else { throw MediaNetworkPolicyFailure.mimeMismatch }
        guard hasMediaSignature(prefix, extensionName: expectedExtension ?? response.url?.pathExtension) else { throw MediaNetworkPolicyFailure.invalidSignature }
    }

    func validate(response: HTTPURLResponse, body: Data, expectedExtension: String? = nil) throws {
        try validate(response: response, prefix: body.prefix(4096), receivedBytes: Int64(body.count), expectedExtension: expectedExtension)
        if let length = response.value(forHTTPHeaderField: "Content-Length"), let length = Int64(length), length > Int64(body.count) { throw MediaNetworkPolicyFailure.truncatedBody }
    }

    func validateStagedMedia(at url: URL, fileSystem: any MediaArtifactFileSystem) throws {
        let size = try fileSystem.fileSize(at: url)
        guard size > 0, size <= maxBytes else { throw MediaNetworkPolicyFailure.responseTooLarge }
        let extensionName = url.pathExtension.lowercased()
        guard Self.mediaMIMEs[extensionName] != nil else { throw MediaNetworkPolicyFailure.mimeMismatch }
        let data = try fileSystem.readData(at: url)
        guard hasMediaSignature(data.prefix(4096), extensionName: extensionName),
              signatureMatchesExtension(data, extensionName: extensionName) else {
            throw MediaNetworkPolicyFailure.invalidSignature
        }
    }

    func reserveDestination(named name: String, in folder: URL, fileSystem: any MediaArtifactFileSystem = FileManager.default) throws -> URL {
        try fileSystem.createDirectory(at: folder)
        let cleaned = sanitize(name)
        let source = URL(fileURLWithPath: cleaned)
        let stem = source.deletingPathExtension().lastPathComponent
        let ext = source.pathExtension
        for index in 0...10_000 {
            let candidateName = index == 0 ? cleaned : (ext.isEmpty ? "\(stem) (\(index))" : "\(stem) (\(index)).\(ext)")
            let candidate = folder.appendingPathComponent(candidateName)
            let key = candidate.standardizedFileURL.path
            let reserved = Self.reservations.reserve(key) {
                fileSystem.fileExists(at: candidate) == false
            }
            if reserved { return candidate }
        }
        throw MediaNetworkPolicyFailure.destinationUnavailable
    }

    func releaseDestination(_ destination: URL) {
        Self.reservations.release(destination.standardizedFileURL.path)
    }

    private func isPublic(host: String) -> Bool {
        if host.lowercased() == "localhost" || host.hasSuffix(".localhost") { return false }
        if Self.isBlockedIP(host) { return false }
        let addresses = locator.addresses(for: host)
        guard addresses.isEmpty == false else { return false }
        return addresses.allSatisfy { !Self.isBlockedIP($0) }
    }

    private static func isBlockedIP(_ value: String) -> Bool {
        var v4 = in_addr()
        if value.withCString({ inet_pton(AF_INET, $0, &v4) }) == 1 {
            let hostOrder = UInt32(bigEndian: v4.s_addr)
            let first = UInt8((hostOrder >> 24) & 255), second = UInt8((hostOrder >> 16) & 255)
            return hostOrder == 0 || first == 10 || first == 127 || (first == 169 && second == 254) || (first == 172 && (16...31).contains(second)) || (first == 192 && second == 168) || (first >= 224) || (first == 100 && (64...127).contains(second))
        }
        var v6 = in6_addr()
        if value.withCString({ inet_pton(AF_INET6, $0, &v6) }) == 1 {
            let bytes = withUnsafeBytes(of: v6) { Array($0) }
            return bytes.allSatisfy { $0 == 0 } || (bytes.dropLast().allSatisfy { $0 == 0 } && bytes.last == 1) || (bytes[0] & 0xfe) == 0xfc || (bytes[0] == 0xfe && (bytes[1] & 0xc0) == 0x80) || (bytes[0] & 0xff) == 0xff
        }
        return true
    }

    private func isMediaMIME(_ mime: String) -> Bool {
        mime.hasPrefix("video/") || mime.hasPrefix("audio/") || mime == "application/ogg" || mime == "application/octet-stream"
    }

    private static let mediaMIMEs: [String: Set<String>] = [
        "mp4": ["video/mp4"], "m4v": ["video/mp4"], "mov": ["video/quicktime"],
        "webm": ["video/webm"], "mkv": ["video/x-matroska"], "avi": ["video/x-msvideo"],
        "mp3": ["audio/mpeg"], "m4a": ["audio/mp4"], "aac": ["audio/aac"],
        "wav": ["audio/wav", "audio/x-wav"], "flac": ["audio/flac"], "ogg": ["audio/ogg", "application/ogg"],
        "opus": ["audio/opus"]
    ]

    private func signatureMatchesExtension(_ data: Data, extensionName: String) -> Bool {
        let bytes = [UInt8](data.prefix(32))
        switch extensionName {
        case "mp4", "m4v": return bytes.count >= 8 && String(decoding: bytes[4..<8], as: UTF8.self) == "ftyp"
        case "mov": return bytes.count >= 8 && String(decoding: bytes[4..<8], as: UTF8.self) == "ftyp"
        case "webm", "mkv": return bytes.starts(with: [0x1A, 0x45, 0xDF, 0xA3])
        case "ogg", "opus": return bytes.starts(with: [0x4F, 0x67, 0x67, 0x53])
        case "flac": return bytes.starts(with: [0x66, 0x4C, 0x61, 0x43])
        case "wav": return bytes.count >= 12 && bytes.starts(with: [0x52, 0x49, 0x46, 0x46]) && String(decoding: bytes[8..<12], as: UTF8.self) == "WAVE"
        case "mp3": return bytes.starts(with: [0x49, 0x44, 0x33]) || (bytes.count >= 2 && bytes[0] == 0xFF && (bytes[1] & 0xE0) == 0xE0)
        case "aac": return bytes.starts(with: [0xFF, 0xF1]) || bytes.starts(with: [0xFF, 0xF9])
        case "m4a": return bytes.count >= 8 && String(decoding: bytes[4..<8], as: UTF8.self) == "ftyp"
        case "avi": return bytes.count >= 12 && bytes.starts(with: [0x52, 0x49, 0x46, 0x46]) && String(decoding: bytes[8..<12], as: UTF8.self) == "AVI "
        default: return false
        }
    }

    private func hasMediaSignature(_ data: Data, extensionName: String?) -> Bool {
        let bytes = [UInt8](data)
        guard bytes.count >= 4 else { return false }
        if bytes.starts(with: [0x1A, 0x45, 0xDF, 0xA3]) || bytes.starts(with: [0x4F, 0x67, 0x67, 0x53]) || bytes.starts(with: [0x66, 0x4C, 0x61, 0x43]) || bytes.starts(with: [0x49, 0x44, 0x33]) { return true }
        if bytes.starts(with: [0x52, 0x49, 0x46, 0x46]) && bytes.count >= 12 && String(decoding: bytes[8..<12], as: UTF8.self) == "WAVE" { return true }
        if bytes.starts(with: [0x46, 0x4F, 0x52, 0x4D]) && bytes.count >= 12 && (String(decoding: bytes[8..<12], as: UTF8.self) == "AIFF" || String(decoding: bytes[8..<12], as: UTF8.self) == "AIFC") { return true }
        if bytes.starts(with: [0xFF, 0xF1]) || bytes.starts(with: [0xFF, 0xF9]) || (bytes.count >= 2 && bytes[0] == 0xFF && (bytes[1] & 0xE0) == 0xE0) { return true }
        return bytes.count >= 8 && String(decoding: bytes[4..<8], as: UTF8.self) == "ftyp"
    }

    private func sanitize(_ name: String) -> String {
        let components = name.split(separator: "/", omittingEmptySubsequences: false).map { component in
            component == ".." || component == "." ? "" : component
        }
        let forbidden = CharacterSet(charactersIn: ":\\?*\"<>|").union(.controlCharacters)
        let replaced = components.map { String($0).components(separatedBy: forbidden).joined(separator: "-") }.joined(separator: "-")
        let trimmed = replaced.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "media" : String(trimmed.prefix(240))
    }
}

private final class DestinationReservations: @unchecked Sendable {
    private let lock = NSLock()
    private var paths = Set<String>()

    func reserve(_ path: String, ifAvailable: () -> Bool) -> Bool {
        lock.withLock {
            guard ifAvailable() else { return false }
            return paths.insert(path).inserted
        }
    }

    func release(_ path: String) {
        _ = lock.withLock { paths.remove(path) }
    }
}
