import Foundation

struct AvailableUpdate: Equatable, Sendable {
    let version: String
    let pageURL: URL
}

enum UpdateCheck {
    static let interval: TimeInterval = 24 * 60 * 60
    static let retryInterval: TimeInterval = 60 * 60
    static let installedVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String

    @Sendable static func latestRelease() async -> Data? {
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/hridaya423/foundry/releases/latest")!, timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Foundry", forHTTPHeaderField: "User-Agent")
        let session = URLSession(configuration: .ephemeral)
        defer { session.finishTasksAndInvalidate() }
        guard let (data, response) = try? await session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return data
    }

    static func update(in release: Data, newerThan installed: String) -> AvailableUpdate? {
        guard let release = try? JSONDecoder().decode(Release.self, from: release) else { return nil }
        let version = String(release.tagName.trimmingPrefix("v"))
        guard version.compare(installed, options: .numeric) == .orderedDescending else { return nil }
        return AvailableUpdate(version: version, pageURL: release.htmlURL)
    }

    private struct Release: Decodable {
        let tagName: String
        let htmlURL: URL

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlURL = "html_url"
        }
    }
}
