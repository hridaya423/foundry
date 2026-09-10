import Foundation
import FoundryDomain

enum MediaDownloadDestination {
    private static let key = "mediaDownloadFolder"

    static var folder: URL {
        if let path = UserDefaults.standard.string(forKey: key), path.isEmpty == false {
            return URL(fileURLWithPath: path)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
    }

    static func setFolder(_ url: URL) {
        UserDefaults.standard.set(url.path, forKey: key)
    }
}

final class MediaDownloadProvider: CommandProvider {
    let id = "foundry.media-download"

    var searchPolicy: CommandProviderSearchPolicy { CommandProviderSearchPolicy(tier: .deferred) }

    func isActive(for query: String) -> Bool {
        Self.mediaURLs(in: query).isEmpty == false
    }

    func search(_ request: CommandSearchRequest) async -> [CommandResult] {
        let urls = Self.mediaURLs(in: request.query)
        guard let url = urls.first else { return [] }
        let isYouTube = Self.isYouTube(url)
        let isDirectFile = Self.isDirectMediaFile(url)
        let isPlaylist = Self.isPlaylist(url)
        let isBatch = urls.count > 1
        let title = isBatch ? "Download \(urls.count) Media Links" : (isPlaylist ? "Download Playlist" : "Download Media")
        let detail = isBatch ? "add all links to the download queue" : (isPlaylist ? "all videos in this playlist" : url.lastPathComponent)
        let service = isBatch ? "parallel downloads" : (isYouTube ? "YouTube · yt-dlp (automatic setup)" : (isDirectFile ? "Direct link · stays on this Mac" : "supported media · yt-dlp"))
        let primaryKind: CommandActionKind = isBatch
            ? .downloadMediaBatch(urls: urls.map(\.absoluteString))
            : .downloadMedia(url: url.absoluteString)
        let thumbnailURL = isYouTube ? Self.youtubeThumbnailURL(for: url) : nil
        return [
            CommandResult(
                id: "media.download.\(url.absoluteString)",
                title: title,
                subtitle: "\(url.absoluteString)\n\(detail) · save via \(service) to \(MediaDownloadDestination.folder.lastPathComponent)",
                icon: CommandIcon(fallback: "DL", systemName: "arrow.down.circle", thumbnailURL: thumbnailURL),
                route: .mediaDownload,
                primaryAction: CommandAction(id: "media.download.perform", title: isBatch ? "Download All" : "Download", kind: primaryKind),
                secondaryActions: [
                    CommandAction(id: "media.download.open-manager", title: "View Downloads", kind: .openMediaDownloads),
                    CommandAction(id: "media.download.open-folder", title: "Open Download Folder", kind: .openURL(MediaDownloadDestination.folder.absoluteString)),
                    CommandAction(id: "media.download.choose-folder", title: "Change Download Folder", kind: .chooseMediaDownloadFolder),
                    CommandAction(id: "media.download.copy-url", title: "Copy URL", kind: .copyToClipboard(url.absoluteString))
                ]
            )
        ]
    }

    static func mediaURLs(in value: String) -> [URL] {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return [] }
        let range = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
        var seen = Set<String>()
        return detector.matches(in: trimmed, range: range).compactMap(\.url).filter { url in
            guard let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme), let host = url.host?.lowercased() else { return false }
            guard isDirectMediaFile(url) || mediaHosts.contains(where: { host == $0 || host.hasSuffix("." + $0) }) else { return false }
            return seen.insert(url.absoluteString).inserted
        }
    }

    static func remainingInput(after value: String) -> String {
        var remaining = value
        for url in mediaURLs(in: value) {
            remaining = remaining.replacingOccurrences(of: url.absoluteString, with: "")
        }
        return remaining.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isYouTube(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return host == "youtu.be" || host.hasSuffix(".youtube.com") || host == "youtube.com"
    }

    private static func isPlaylist(_ url: URL) -> Bool {
        guard isYouTube(url), let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return false }
        if url.path == "/playlist" { return true }
        return components.queryItems?.contains { $0.name == "list" && ($0.value?.isEmpty == false) } == true
    }

    private static func youtubeThumbnailURL(for url: URL) -> URL? {
        let pathComponents = url.pathComponents.dropFirst()
        let videoID: String?
        if url.host?.lowercased() == "youtu.be" {
            videoID = pathComponents.first
        } else if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                  let queryID = components.queryItems?.first(where: { $0.name == "v" })?.value {
            videoID = queryID
        } else if let markerIndex = pathComponents.firstIndex(where: { ["shorts", "embed", "live"].contains($0.lowercased()) }),
                  pathComponents.index(after: markerIndex) < pathComponents.endIndex {
            videoID = pathComponents[pathComponents.index(after: markerIndex)]
        } else {
            videoID = nil
        }

        guard let videoID,
              videoID.isEmpty == false,
              videoID.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }) else { return nil }
        return URL(string: "https://i.ytimg.com/vi/\(videoID)/hqdefault.jpg")
    }

    static func isDirectMediaFile(_ url: URL) -> Bool {
        directMediaExtensions.contains(url.pathExtension.lowercased())
    }

    private static let mediaHosts: Set<String> = [
        "youtube.com", "youtu.be",
        "instagram.com", "tiktok.com", "x.com", "twitter.com",
        "reddit.com", "pinterest.com", "soundcloud.com",
        "vimeo.com", "facebook.com", "threads.net", "bsky.app"
    ]

    private static let directMediaExtensions: Set<String> = ["mp3", "m4a", "wav", "aac", "flac", "ogg", "mp4", "mov", "webm", "mkv"]
}
