import Foundation

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

    func results(matching query: String) async -> [CommandResult] {
        guard let url = Self.mediaURL(in: query) else { return [] }
        let isYouTube = Self.isYouTube(url)
        let isDirectFile = Self.isDirectMediaFile(url)
        let isPlaylist = Self.isPlaylist(url)
        let metadata = isYouTube ? await Self.youtubeMetadata(for: url) : nil
        let title = isPlaylist ? "Download Playlist" : "Download Media"
        let detail = metadata?.title ?? (isPlaylist ? "all videos in this playlist" : url.lastPathComponent)
        let service = isYouTube ? "yt-dlp" : (isDirectFile ? "direct link" : "cobalt")
        return [
            CommandResult(
                id: "media.download.\(url.absoluteString)",
                title: title,
                subtitle: "\(detail) · save via \(service) to \(MediaDownloadDestination.folder.lastPathComponent)",
                icon: CommandIcon(fallback: "DL", systemName: "arrow.down.circle", thumbnailURL: metadata?.thumbnailURL),
                score: 10_000,
                primaryAction: CommandAction(id: "media.download.perform", title: "Download", kind: .downloadMedia(url: url.absoluteString)),
                secondaryActions: [
                    CommandAction(id: "media.download.open-folder", title: "Open Download Folder", kind: .openURL(MediaDownloadDestination.folder.absoluteString)),
                    CommandAction(id: "media.download.choose-folder", title: "Change Download Folder", kind: .chooseMediaDownloadFolder),
                    CommandAction(id: "media.download.copy-url", title: "Copy URL", kind: .copyToClipboard(url.absoluteString))
                ]
            )
        ]
    }

    private static func mediaURL(in value: String) -> URL? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return nil }
        let range = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
        return detector.matches(in: trimmed, range: range).compactMap(\.url).first { url in
            guard let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme), let host = url.host?.lowercased() else { return false }
            return isDirectMediaFile(url) || mediaHosts.contains { host == $0 || host.hasSuffix("." + $0) }
        }
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

    static func isDirectMediaFile(_ url: URL) -> Bool {
        directMediaExtensions.contains(url.pathExtension.lowercased())
    }

    private static func youtubeMetadata(for url: URL) async -> YouTubeMetadata? {
        var components = URLComponents(string: "https://www.youtube.com/oembed")
        components?.queryItems = [
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "url", value: url.absoluteString)
        ]
        guard let metadataURL = components?.url,
              let (data, _) = try? await URLSession.shared.data(from: metadataURL),
              let response = try? JSONDecoder().decode(YouTubeOEmbedResponse.self, from: data) else { return nil }
        return YouTubeMetadata(title: response.title, thumbnailURL: URL(string: response.thumbnailURL))
    }

    private static let mediaHosts: Set<String> = [
        "youtube.com", "youtu.be",
        "instagram.com", "tiktok.com", "x.com", "twitter.com",
        "reddit.com", "pinterest.com", "soundcloud.com",
        "vimeo.com", "facebook.com", "threads.net", "bsky.app"
    ]

    private static let directMediaExtensions: Set<String> = ["mp3", "m4a", "wav", "aac", "flac", "ogg", "mp4", "mov", "webm", "mkv"]
}

private struct YouTubeMetadata {
    let title: String
    let thumbnailURL: URL?
}

private struct YouTubeOEmbedResponse: Decodable {
    let title: String
    let thumbnailURL: String

    enum CodingKeys: String, CodingKey {
        case title
        case thumbnailURL = "thumbnail_url"
    }
}
