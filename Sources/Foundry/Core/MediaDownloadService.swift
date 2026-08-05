import Foundation
import FoundryServices

protocol MediaDownloading: Sendable {
    var downloadFolder: URL { get }

    func download(
        urlString: String,
        status: (@MainActor @Sendable (String) -> Void)?
    ) async throws -> String
}

final class MediaDownloadService: MediaDownloading, @unchecked Sendable {
    var downloadFolder: URL {
        MediaDownloadDestination.folder
    }

    func download(
        urlString: String,
        status: (@MainActor @Sendable (String) -> Void)? = nil
    ) async throws -> String {
        guard let url = URL(string: urlString) else { return "Invalid media URL" }

        do {
            try FileManager.default.createDirectory(at: downloadFolder, withIntermediateDirectories: true)
            if MediaDownloadProvider.isDirectMediaFile(url) {
                let file = try await downloadDirectFile(url, status: status)
                return "Downloaded \(file.lastPathComponent)"
            }

            if isYouTube(url) {
                report("Preparing yt-dlp", status)
                let executable = try installYTDLPIfNeeded()
                let playlistLabel = isPlaylist(url) ? "playlist" : "media"
                report("Downloading \(playlistLabel)", status)
                try await runYTDLP(executable, url: url)
                return "Downloaded YouTube media to \(downloadFolder.path)"
            }

            let file = try await downloadWithCobalt(url, status: status)
            return "Downloaded \(file.lastPathComponent)"
        } catch {
            if Task.isCancelled {
                throw CancellationError()
            }
            return "Media download failed: \(error.localizedDescription)"
        }
    }

    private func downloadDirectFile(_ sourceURL: URL, status: (@MainActor @Sendable (String) -> Void)?) async throws -> URL {
        report("Downloading \(sourceURL.lastPathComponent)", status)
        let (temporaryURL, response) = try await URLSession.shared.download(from: sourceURL)
        let fallbackName = response.suggestedFilename ?? sourceURL.lastPathComponent
        let name = fallbackName.isEmpty ? "media-\(Int(Date().timeIntervalSince1970)).\(sourceURL.pathExtension)" : fallbackName
        let destination = uniqueDestination(for: name)
        try FileManager.default.moveItem(at: temporaryURL, to: destination)
        return destination
    }

    private func isYouTube(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return host == "youtu.be" || host == "youtube.com" || host.hasSuffix(".youtube.com")
    }

    private func isPlaylist(_ url: URL) -> Bool {
        guard isYouTube(url), let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return false }
        if url.path == "/playlist" { return true }
        return components.queryItems?.contains { $0.name == "list" && ($0.value?.isEmpty == false) } == true
    }

    private func installYTDLPIfNeeded() throws -> String {
        if let existing = firstExistingPath(["/opt/homebrew/bin/yt-dlp", "/usr/local/bin/yt-dlp"]) { return existing }
        if let found = try? runAndCapture("/usr/bin/which", ["yt-dlp"]).trimmingCharacters(in: .whitespacesAndNewlines), found.isEmpty == false {
            return found
        }

        guard let brew = firstExistingPath(["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]) else {
            throw MediaDownloadError.message("yt-dlp is missing and Homebrew was not found")
        }

        try run(brew, ["install", "yt-dlp"])
        if let installed = firstExistingPath(["/opt/homebrew/bin/yt-dlp", "/usr/local/bin/yt-dlp"]) { return installed }
        throw MediaDownloadError.message("yt-dlp install finished, but yt-dlp was not found")
    }

    private func downloadWithCobalt(_ sourceURL: URL, status: (@MainActor @Sendable (String) -> Void)?) async throws -> URL {
        report("Requesting media link from cobalt", status)
        var request = URLRequest(url: URL(string: "https://api.cobalt.tools/")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["url": sourceURL.absoluteString])

        let (data, _) = try await URLSession.shared.data(for: request)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw MediaDownloadError.message("invalid cobalt response")
        }

        if let error = json["error"] as? [String: Any], let code = error["code"] as? String {
            throw MediaDownloadError.message("cobalt error: \(code)")
        }

        let downloadURLString = json["url"] as? String
            ?? json["tunnel"] as? String
            ?? (json["picker"] as? [[String: Any]])?.compactMap { $0["url"] as? String ?? $0["tunnel"] as? String }.first

        guard let downloadURLString, let downloadURL = URL(string: downloadURLString) else {
            throw MediaDownloadError.message("cobalt did not return a downloadable file")
        }

        report("Downloading media", status)
        let (temporaryURL, response) = try await URLSession.shared.download(from: downloadURL)
        let fallbackName = response.suggestedFilename ?? "media-\(Int(Date().timeIntervalSince1970))"
        let destination = uniqueDestination(for: fallbackName)
        try FileManager.default.moveItem(at: temporaryURL, to: destination)
        return destination
    }

    private func runYTDLP(_ path: String, url: URL) async throws {
        let result = try await ProcessRunner.run(
            path: path,
            arguments: ["--newline", "-P", downloadFolder.path, "-o", "%(title).200B [%(id)s].%(ext)s", url.absoluteString],
            timeout: 30 * 60,
            outputLimit: 8 * 1024 * 1024
        )
        guard result.succeeded else {
            throw MediaDownloadError.message(result.stderr.isEmpty ? result.stdout.trimmingCharacters(in: .whitespacesAndNewlines) : result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    private func report(_ message: String, _ status: (@MainActor @Sendable (String) -> Void)?) {
        guard let status else { return }
        Task { await status(message) }
    }

    private func firstExistingPath(_ paths: [String]) -> String? {
        paths.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    private func run(_ path: String, _ arguments: [String]) throws {
        _ = try runAndCapture(path, arguments)
    }

    private func runAndCapture(_ path: String, _ arguments: [String]) throws -> String {
        guard let result = ProcessRunner.runSynchronously(path: path, arguments: arguments, timeout: 5 * 60, outputLimit: 8 * 1024 * 1024), result.succeeded else {
            throw MediaDownloadError.message("Process failed: \(path)")
        }
        return result.stdout
    }

    private func uniqueDestination(for name: String) -> URL {
        let baseName = safeFilename(name)
        let folder = downloadFolder
        let original = folder.appendingPathComponent(baseName)
        guard FileManager.default.fileExists(atPath: original.path) else { return original }
        let url = URL(fileURLWithPath: baseName)
        let stem = url.deletingPathExtension().lastPathComponent
        let extensionName = url.pathExtension
        for index in 1...10_000 {
            let candidateName = extensionName.isEmpty ? "\(stem) (\(index))" : "\(stem) (\(index)).\(extensionName)"
            let candidate = folder.appendingPathComponent(candidateName)
            if FileManager.default.fileExists(atPath: candidate.path) == false { return candidate }
        }
        return folder.appendingPathComponent("media-\(UUID().uuidString).\(extensionName)")
    }

    private func safeFilename(_ name: String) -> String {
        let invalid = CharacterSet(charactersIn: "/:")
        let cleaned = name.components(separatedBy: invalid).joined(separator: "-")
        return cleaned.isEmpty ? "media-\(Int(Date().timeIntervalSince1970))" : cleaned
    }
}

private enum MediaDownloadError: LocalizedError {
    case message(String)

    var errorDescription: String? {
        switch self {
        case let .message(message): message
        }
    }
}
