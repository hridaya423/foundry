import AppKit
import Carbon
import Foundation
import UniformTypeIdentifiers

@MainActor
final class ActionRunner {
    private let diagnostics: DiagnosticsService
    var mediaStatusHandler: (@MainActor @Sendable (String) -> Void)?

    init(diagnostics: DiagnosticsService) {
        self.diagnostics = diagnostics
    }

    func perform(_ action: CommandAction) {
        switch action.kind {
        case let .openApp(path, name):
            let configuration = NSWorkspace.OpenConfiguration()
            NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: path), configuration: configuration) { [diagnostics] _, error in
                if let error {
                    diagnostics.log("Failed to launch \(name): \(error.localizedDescription)")
                } else {
                    diagnostics.log("Launched app: \(name)")
                }
            }

        case let .openURL(urlString):
            guard let url = URL(string: urlString) else {
                diagnostics.log("Invalid URL: \(urlString)")
                return
            }
            NSWorkspace.shared.open(url)

        case .openConfigFolder:
            let folder = ConfigService.configURL.deletingLastPathComponent()
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            NSWorkspace.shared.open(folder)

        case let .revealInFinder(path):
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
            diagnostics.log("Revealed in Finder: \(path)")

        case let .copyToClipboard(value):
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(value, forType: .string)
            diagnostics.log("Copied to clipboard")

        case let .pasteText(value):
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(value, forType: .string)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                Self.sendPasteShortcut()
            }
            diagnostics.log("Inserted snippet")

        case .createSnippetFromClipboard:
            guard let content = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines), content.isEmpty == false else {
                diagnostics.log("Clipboard is empty")
                return
            }
            var snippets = LibraryPersistence.loadSnippets()
            snippets.insert(StoredSnippet(title: Self.snippetTitle(from: content), content: String(content.prefix(Self.snippetLimit))), at: 0)
            LibraryPersistence.saveSnippets(snippets)
            diagnostics.log("Created snippet from clipboard")

        case .importSnippets:
            importSnippets()

        case let .downloadMedia(urlString):
            diagnostics.log("Starting media download")
            let statusHandler = mediaStatusHandler
            Task.detached { [diagnostics] in
                let result = await Self.downloadMedia(urlString: urlString, status: statusHandler)
                await MainActor.run {
                    statusHandler?(result)
                    diagnostics.log(result)
                    NSWorkspace.shared.open(Self.downloadFolder)
                }
            }

        case .chooseMediaDownloadFolder:
            let panel = NSOpenPanel()
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.allowsMultipleSelection = false
            panel.directoryURL = MediaDownloadDestination.folder
            if panel.runModal() == .OK, let url = panel.url {
                MediaDownloadDestination.setFolder(url)
                mediaStatusHandler?("Downloads will save to \(url.lastPathComponent)")
                diagnostics.log("Media download folder changed: \(url.path)")
            }

        case .openActivityMonitor:
            diagnostics.log("Activity Monitor should be opened by panel state")

        case .openEmojiPicker:
            diagnostics.log("Emoji Picker should be opened by panel state")

        case .openFileShelf:
            diagnostics.log("File Shelf should be opened by panel state")

        case .openClipboardHistory:
            diagnostics.log("Clipboard History should be opened by panel state")

        case .openSnippets:
            diagnostics.log("Snippets should be opened by panel state")

        case .openFileConverter:
            diagnostics.log("File Converter should be opened by panel state")

        case .openCamera:
            diagnostics.log("Camera should be opened by panel state")

        case .openTranslator:
            diagnostics.log("Translator should be opened by panel state")

        case .openSettings:
            diagnostics.log("Settings should be opened by panel state")

        case let .runProcess(path, arguments):
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: path)
                process.arguments = arguments

                do {
                    try process.run()
                } catch {
                    self.diagnostics.log("Failed to run \(path): \(error.localizedDescription)")
                }
            }

        case .quit:
            NSApp.terminate(nil)

        case let .log(message):
            diagnostics.log(message)
        }
    }

    nonisolated private static let downloadFolder = MediaDownloadDestination.folder
    nonisolated private static let snippetLimit = 65_536

    private func importSnippets() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let data = try Data(contentsOf: url)
            let imported = try JSONDecoder().decode([RaycastSnippetImport].self, from: data)
            var snippets = LibraryPersistence.loadSnippets()
            var added = 0
            var skipped = 0

            for item in imported {
                let title = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
                let content = item.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard title.isEmpty == false, content.isEmpty == false else { skipped += 1; continue }
                if snippets.contains(where: { $0.title == title && $0.content == content }) {
                    skipped += 1
                    continue
                }
                snippets.insert(StoredSnippet(title: title, content: String(content.prefix(Self.snippetLimit)), keyword: item.keyword ?? ""), at: 0)
                added += 1
            }

            LibraryPersistence.saveSnippets(snippets)
            diagnostics.log("Imported \(added) snippets, skipped \(skipped) duplicates")
        } catch {
            diagnostics.log("Snippet import failed: \(error.localizedDescription)")
        }
    }

    nonisolated private static func sendPasteShortcut() {
        guard let source = CGEventSource(stateID: .hidSystemState) else { return }
        let down = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cgAnnotatedSessionEventTap)
        up?.post(tap: .cgAnnotatedSessionEventTap)
    }

    nonisolated private static func snippetTitle(from content: String) -> String {
        let firstLine = content.split(separator: "\n").first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return firstLine.isEmpty ? "Clipboard Snippet" : String(firstLine.prefix(60))
    }

    nonisolated private static func downloadMedia(urlString: String, status: (@MainActor @Sendable (String) -> Void)?) async -> String {
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
                try runYTDLP(executable, url: url, status: status)
                return "Downloaded YouTube media to \(downloadFolder.path)"
            }

            let file = try await downloadWithCobalt(url, status: status)
            return "Downloaded \(file.lastPathComponent)"
        } catch {
            return "Media download failed: \(error.localizedDescription)"
        }
    }

    nonisolated private static func downloadDirectFile(_ sourceURL: URL, status: (@MainActor @Sendable (String) -> Void)?) async throws -> URL {
        report("Downloading \(sourceURL.lastPathComponent)", status)
        let (temporaryURL, response) = try await URLSession.shared.download(from: sourceURL)
        let fallbackName = response.suggestedFilename ?? sourceURL.lastPathComponent
        let name = fallbackName.isEmpty ? "media-\(Int(Date().timeIntervalSince1970)).\(sourceURL.pathExtension)" : fallbackName
        let destination = downloadFolder.appendingPathComponent(safeFilename(name))
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: temporaryURL, to: destination)
        return destination
    }

    nonisolated private static func isYouTube(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return host == "youtu.be" || host == "youtube.com" || host.hasSuffix(".youtube.com")
    }

    nonisolated private static func isPlaylist(_ url: URL) -> Bool {
        guard isYouTube(url), let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return false }
        if url.path == "/playlist" { return true }
        return components.queryItems?.contains { $0.name == "list" && ($0.value?.isEmpty == false) } == true
    }

    nonisolated private static func installYTDLPIfNeeded() throws -> String {
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

    nonisolated private static func downloadWithCobalt(_ sourceURL: URL, status: (@MainActor @Sendable (String) -> Void)?) async throws -> URL {
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
        let destination = downloadFolder.appendingPathComponent(safeFilename(fallbackName))
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: temporaryURL, to: destination)
        return destination
    }

    nonisolated private static func runYTDLP(_ path: String, url: URL, status: (@MainActor @Sendable (String) -> Void)?) throws {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = ["--newline", "-P", downloadFolder.path, "-o", "%(title).200B [%(id)s].%(ext)s", url.absoluteString]
        process.standardOutput = pipe
        process.standardError = pipe

        let output = MediaDownloadOutput()
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard data.isEmpty == false, let chunk = String(data: data, encoding: .utf8) else { return }
            output.append(chunk, status: status)
        }

        try process.run()
        process.waitUntilExit()
        pipe.fileHandleForReading.readabilityHandler = nil
        if process.terminationStatus != 0 {
            throw MediaDownloadError.message(output.text.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    nonisolated fileprivate static func playlistItemLabel(in line: String) -> String? {
        guard let range = line.range(of: "Downloading item ") else { return nil }
        let suffix = line[range.upperBound...]
        let label = suffix.split(separator: " ").prefix(3).joined(separator: " ")
        return label.isEmpty ? nil : label
    }

    nonisolated fileprivate static func downloadPercent(in line: String) -> String? {
        guard line.contains("[download]") else { return nil }
        let parts = line.split(separator: " ").map(String.init)
        return parts.first { $0.hasSuffix("%") }
    }

    nonisolated fileprivate static func report(_ message: String, _ status: (@MainActor @Sendable (String) -> Void)?) {
        guard let status else { return }
        Task { await status(message) }
    }

    nonisolated private static func firstExistingPath(_ paths: [String]) -> String? {
        paths.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    nonisolated private static func run(_ path: String, _ arguments: [String]) throws {
        _ = try runAndCapture(path, arguments)
    }

    nonisolated private static func runAndCapture(_ path: String, _ arguments: [String]) throws -> String {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        guard process.terminationStatus == 0 else {
            throw MediaDownloadError.message(output.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return output
    }

    nonisolated private static func safeFilename(_ name: String) -> String {
        let invalid = CharacterSet(charactersIn: "/:")
        let cleaned = name.components(separatedBy: invalid).joined(separator: "-")
        return cleaned.isEmpty ? "media-\(Int(Date().timeIntervalSince1970))" : cleaned
    }
}

private struct RaycastSnippetImport: Decodable {
    let name: String
    let text: String
    let keyword: String?
}

private final class MediaDownloadOutput: @unchecked Sendable {
    private let lock = NSLock()
    private var value = ""
    private var currentItem: String?

    var text: String {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func append(_ chunk: String, status: (@MainActor @Sendable (String) -> Void)?) {
        lock.lock()
        value += chunk
        let lines = chunk.components(separatedBy: .newlines)
        lock.unlock()

        for line in lines {
            if let item = ActionRunner.playlistItemLabel(in: line) {
                lock.lock()
                currentItem = item
                lock.unlock()
                ActionRunner.report("Downloading \(item)", status)
            } else if let percent = ActionRunner.downloadPercent(in: line) {
                lock.lock()
                let item = currentItem
                lock.unlock()
                let prefix = item.map { "Downloading \($0)" } ?? "Downloading"
                ActionRunner.report("\(prefix) · \(percent)", status)
            }
        }
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
