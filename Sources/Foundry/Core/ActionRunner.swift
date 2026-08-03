import AppKit
import Carbon
import CoreAudio
import Foundation
import UniformTypeIdentifiers

@MainActor
final class ActionRunner {
    private let diagnostics: DiagnosticsService
    private var mediaTask: Task<Void, Never>?
    var mediaStatusHandler: (@MainActor @Sendable (String) -> Void)?
    var feedbackHandler: (@MainActor @Sendable (ActionFeedback) -> Void)?

    init(diagnostics: DiagnosticsService) {
        self.diagnostics = diagnostics
    }

    func perform(_ action: CommandAction) {
        switch action.kind {
        case .openQuickAI:
            diagnostics.log("Quick AI should be opened by panel state")

        case let .openApp(path, name):
            let configuration = NSWorkspace.OpenConfiguration()
            let feedback = feedbackHandler
            NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: path), configuration: configuration) { [diagnostics, feedback] _, error in
                if let error {
                    diagnostics.log("Failed to launch \(name): \(error.localizedDescription)")
                    Task { @MainActor in feedback?(.failure("Could not open \(name)")) }
                } else {
                    diagnostics.log("Launched app: \(name)")
                }
            }

        case let .openURL(urlString):
            guard let url = URL(string: urlString) else {
                diagnostics.log("Invalid URL: \(urlString)")
                feedbackHandler?(.failure("Invalid URL"))
                return
            }
            if NSWorkspace.shared.open(url) == false {
                feedbackHandler?(.failure("Could not open link"))
            }

        case .openConfigFolder:
            let folder = ConfigService.configURL.deletingLastPathComponent()
            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                if NSWorkspace.shared.open(folder) == false {
                    feedbackHandler?(.failure("Could not open Foundry folder"))
                }
            } catch {
                feedbackHandler?(.failure("Could not create Foundry folder"))
            }

        case let .revealInFinder(path):
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
            diagnostics.log("Revealed in Finder: \(path)")

        case let .copyToClipboard(value):
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(value, forType: .string)
            diagnostics.log("Copied to clipboard")
            feedbackHandler?(.success("Copied to clipboard"))

        case let .pasteText(value):
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(value, forType: .string)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                Self.sendPasteShortcut()
            }
            diagnostics.log("Inserted snippet")
            feedbackHandler?(.success("Inserted snippet"))

        case .createSnippetFromClipboard:
            guard let content = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines), content.isEmpty == false else {
                diagnostics.log("Clipboard is empty")
                return
            }
            var snippets = LibraryPersistence.loadSnippets()
            snippets.insert(StoredSnippet(title: Self.snippetTitle(from: content), content: String(content.prefix(Self.snippetLimit))), at: 0)
                if case let .failure(error) = LibraryPersistence.saveSnippets(snippets) {
                    diagnostics.log("Failed to save clipboard snippet: \(error.localizedDescription)")
                    feedbackHandler?(.failure("Could not save snippet"))
                } else {
                    feedbackHandler?(.success("Created snippet"))
                }
            diagnostics.log("Created snippet from clipboard")

        case .importSnippets:
            importSnippets()

        case let .downloadMedia(urlString):
            diagnostics.log("Starting media download")
            let statusHandler = mediaStatusHandler
            let feedback = feedbackHandler
            mediaTask?.cancel()
            mediaTask = Task.detached { [diagnostics, feedback] in
                let result = await Self.downloadMedia(urlString: urlString, status: statusHandler)
                guard Task.isCancelled == false else { return }
                await MainActor.run {
                    statusHandler?(result)
                    diagnostics.log(result)
                    feedback?(result.lowercased().contains("failed") ? .failure(result) : .success(result))
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

        case .openDeveloperTools:
            diagnostics.log("Developer Tools should be opened by panel state")

        case .openSettings:
            diagnostics.log("Settings should be opened by panel state")

        case .openDashboard:
            diagnostics.log("Dashboard should be opened by panel state")

        case let .terminateProcess(pid):
            do {
                if kill(pid, SIGTERM) == 0 {
                    diagnostics.log("Terminated process \(pid)")
                    feedbackHandler?(.success("Terminated process"))
                } else {
                    throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EPERM)
                }
            } catch {
                diagnostics.log("Failed to terminate process \(pid): \(error.localizedDescription)")
                feedbackHandler?(.failure("Could not terminate process"))
            }

        case let .quitApplication(bundleID, name):
            let running = NSWorkspace.shared.runningApplications.first {
                ($0.bundleIdentifier == bundleID && bundleID != nil)
                    || $0.localizedName == name
            }
            if let running {
                if running.terminate() || running.forceTerminate() {
                    diagnostics.log("Quit \(name)")
                    feedbackHandler?(.success("Quit \(name)"))
                } else {
                    diagnostics.log("Failed to quit \(name)")
                    feedbackHandler?(.failure("Could not quit \(name)"))
                }
            } else {
                diagnostics.log("\(name) is not running")
            }

        case .toggleKeepAwake:
            let state = KeepAwakeController.toggle()
            diagnostics.log(state ? "Keep Awake enabled" : "Keep Awake disabled")

        case let .terminatePort(port):
            let command = "lsof -ti tcp:\(port) | xargs -r kill"
            DispatchQueue.global(qos: .userInitiated).async {
                let result = ProcessRunner.runSynchronously(path: "/bin/zsh", arguments: ["-lc", command], timeout: 3)
                DispatchQueue.main.async {
                    self.diagnostics.log(result?.succeeded == true ? "Stopped port \(port)" : "Failed to stop port \(port)")
                }
            }

        case let .setAudioDevice(id, kind):
            do {
                try AudioDeviceController.setDevice(id: id, kind: kind)
                diagnostics.log("Updated \(kind == .output ? "output" : "input") audio device")
            } catch {
                diagnostics.log("Failed to switch audio device: \(error.localizedDescription)")
                feedbackHandler?(.failure("Could not switch audio device"))
            }

        case .resetRanking:
            diagnostics.log("Ranking reset is handled by the command registry")

        case .rebuildApp:
            guard let sourceRoot = Bundle.main.object(forInfoDictionaryKey: "FoundrySourceRoot") as? String else {
                diagnostics.log("Cannot rebuild Foundry: source root is unavailable")
                return
            }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-lc", "cd -- \"$1\" && ./scripts/build-app.sh", "foundry-rebuild", sourceRoot]
            do {
                try process.run()
                diagnostics.log("Started Foundry app rebuild")
            } catch {
                diagnostics.log("Failed to rebuild Foundry app: \(error.localizedDescription)")
            }

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

    func cancelMediaDownload() {
        mediaTask?.cancel()
        mediaTask = nil
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

            if case let .failure(error) = LibraryPersistence.saveSnippets(snippets) {
                diagnostics.log("Failed to save imported snippets: \(error.localizedDescription)")
            }
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
                try await runYTDLP(executable, url: url)
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
        let destination = uniqueDestination(for: name)
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
        let destination = uniqueDestination(for: fallbackName)
        try FileManager.default.moveItem(at: temporaryURL, to: destination)
        return destination
    }

    nonisolated private static func runYTDLP(_ path: String, url: URL) async throws {
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
        guard let result = ProcessRunner.runSynchronously(path: path, arguments: arguments, timeout: 5 * 60, outputLimit: 8 * 1024 * 1024), result.succeeded else {
            throw MediaDownloadError.message("Process failed: \(path)")
        }
        return result.stdout
    }

    nonisolated private static func uniqueDestination(for name: String) -> URL {
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

    nonisolated private static func safeFilename(_ name: String) -> String {
        let invalid = CharacterSet(charactersIn: "/:")
        let cleaned = name.components(separatedBy: invalid).joined(separator: "-")
        return cleaned.isEmpty ? "media-\(Int(Date().timeIntervalSince1970))" : cleaned
    }
}

enum KeepAwakeController {
    private static let marker = "foundry.keepawake"
    private static let processSnapshotProvider = NativeProcessSnapshotProvider()

    static func toggle() -> Bool {
        if let pid = currentPID() {
            kill(pid, SIGTERM)
            return false
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate")
        process.arguments = ["-dimsu"]
        process.environment = ProcessInfo.processInfo.environment.merging(["FOUNDRY_KEEP_AWAKE": marker]) { _, new in new }
        try? process.run()
        return true
    }

    static func isActive() -> Bool {
        currentPID() != nil
    }

    private static func currentPID() -> Int32? {
        processSnapshotProvider.capture()
            .first { $0.executableName == "caffeinate" && $0.args.contains("-dimsu") }
            .flatMap { Int32($0.pid) }
    }
}

private enum AudioDeviceController {
    static func setDevice(id: AudioDeviceID, kind: AudioDeviceKind) throws {
        var device = id
        var address = AudioObjectPropertyAddress(
            mSelector: kind == .output ? kAudioHardwarePropertyDefaultOutputDevice : kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, UInt32(MemoryLayout<AudioDeviceID>.size), &device)
        guard status == noErr else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
    }
}

private struct RaycastSnippetImport: Decodable {
    let name: String
    let text: String
    let keyword: String?
}

private enum MediaDownloadError: LocalizedError {
    case message(String)

    var errorDescription: String? {
        switch self {
        case let .message(message): message
        }
    }
}
