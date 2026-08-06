import AppKit
import Carbon
import CoreAudio
import Foundation
import FoundryDomain
import FoundryServices
import UniformTypeIdentifiers

@MainActor
final class ActionRunner: CommandExecuting {
    private let diagnostics: DiagnosticsService
    private let snippetStore: any SnippetStore
    private let mediaDownloadService: any MediaDownloading
    private let mediaDownloadManager: MediaDownloadManager
    private let resetRanking: (String) -> Void
    private let confirmAction: (CommandActionDescriptor, CommandInvocationSource) -> Bool
    private var activeExecutionTasks: [UUID: Task<CommandOutcome, Never>] = [:]

    init(
        diagnostics: DiagnosticsService,
        snippetStore: any SnippetStore = FileSnippetStore(),
        mediaDownloadService: any MediaDownloading = MediaDownloadService(),
        mediaDownloadManager: MediaDownloadManager = MediaDownloadManager(),
        resetRanking: @escaping (String) -> Void = { _ in },
        confirmAction: @escaping (CommandActionDescriptor, CommandInvocationSource) -> Bool = { _, _ in true }
    ) {
        self.diagnostics = diagnostics
        self.snippetStore = snippetStore
        self.mediaDownloadService = mediaDownloadService
        self.mediaDownloadManager = mediaDownloadManager
        self.resetRanking = resetRanking
        self.confirmAction = confirmAction
    }

    func execute(
        _ request: CommandExecutionRequest,
        emit: @escaping @MainActor @Sendable (CommandExecutionEvent) -> Void
    ) async -> CommandOutcome {
        let invocationID = request.invocation.cancellationID
        guard activeExecutionTasks[invocationID] == nil else {
            return .failure(message: "An action with this cancellation ID is already running", retryable: true)
        }
        let task = Task { @MainActor [weak self] in
            guard let self else { return CommandOutcome.cancelled }
            return await self.perform(request, emit: emit)
        }
        activeExecutionTasks[invocationID] = task
        let outcome = await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
        activeExecutionTasks.removeValue(forKey: invocationID)
        return outcome
    }

    private func perform(
        _ request: CommandExecutionRequest,
        emit: @escaping @MainActor @Sendable (CommandExecutionEvent) -> Void
    ) async -> CommandOutcome {
        func finish(_ outcome: CommandOutcome, feedback: ActionFeedback? = nil) -> CommandOutcome {
            if let feedback {
                emit(.feedback(feedback))
            }
            return outcome
        }

        if request.action.descriptor.confirmation != .never,
           confirmAction(request.action.descriptor, request.invocation.source) == false {
            return finish(.denied(message: "Action cancelled"), feedback: .info("Action cancelled"))
        }

        switch request.action.kind {
        case let .openQuickAI(prompt):
            return .open(route: .quickAI(initialPrompt: prompt))

        case let .openApp(path, name):
            let configuration = NSWorkspace.OpenConfiguration()
            return await withCheckedContinuation { continuation in
                NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: path), configuration: configuration) { [diagnostics] _, error in
                    Task { @MainActor in
                        if let error {
                            diagnostics.log("Failed to launch \(name): \(error.localizedDescription)")
                            emit(.feedback(.failure("Could not open \(name)")))
                            continuation.resume(returning: .failure(message: "Could not open \(name)", retryable: true))
                        } else {
                            diagnostics.log("Launched app: \(name)")
                            continuation.resume(returning: .success(message: "Opened \(name)"))
                        }
                    }
                }
            }

        case let .openURL(urlString):
            guard let url = URL(string: urlString) else {
                diagnostics.log("Invalid URL: \(urlString)")
                return finish(.failure(message: "Invalid URL", retryable: false), feedback: .failure("Invalid URL"))
            }
            if NSWorkspace.shared.open(url) == false {
                return finish(.failure(message: "Could not open link", retryable: true), feedback: .failure("Could not open link"))
            }
            return .success(message: "Opened link")

        case .openConfigFolder:
            let folder = ConfigService.configURL.deletingLastPathComponent()
            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                if NSWorkspace.shared.open(folder) == false {
                    return finish(.failure(message: "Could not open Foundry folder", retryable: true), feedback: .failure("Could not open Foundry folder"))
                }
                return .success(message: "Opened Foundry folder")
            } catch {
                return finish(.failure(message: "Could not create Foundry folder", retryable: true), feedback: .failure("Could not create Foundry folder"))
            }

        case let .revealInFinder(path):
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
            diagnostics.log("Revealed in Finder: \(path)")
            return .success(message: "Revealed in Finder")

        case let .copyToClipboard(value):
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(value, forType: .string)
            diagnostics.log("Copied to clipboard")
            return finish(.copied(content: value), feedback: .success("Copied to clipboard"))

        case let .pasteText(value):
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(value, forType: .string)
            try? await Task.sleep(for: .milliseconds(120))
            guard Task.isCancelled == false else { return .cancelled }
            Self.sendPasteShortcut()
            diagnostics.log("Inserted snippet")
            return finish(.pasted(content: value), feedback: .success("Inserted snippet"))

        case .createSnippetFromClipboard:
            guard let content = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines), content.isEmpty == false else {
                diagnostics.log("Clipboard is empty")
                return finish(.failure(message: "Clipboard is empty", retryable: false), feedback: .info("Clipboard is empty"))
            }
            var snippets = snippetStore.load()
            snippets.insert(StoredSnippet(title: Self.snippetTitle(from: content), content: String(content.prefix(Self.snippetLimit))), at: 0)
            if case let .failure(error) = snippetStore.save(snippets) {
                diagnostics.log("Failed to save clipboard snippet: \(error.localizedDescription)")
                return finish(.failure(message: "Could not save snippet", retryable: true), feedback: .failure("Could not save snippet"))
            }
            diagnostics.log("Created snippet from clipboard")
            return finish(.success(message: "Created snippet"), feedback: .success("Created snippet"))

        case .importSnippets:
            let outcome = importSnippets()
            if case let .success(message) = outcome, let message {
                emit(.feedback(.success(message)))
            }
            return outcome

        case let .downloadMediaBatch(urls):
            for url in urls {
                let childRequest = CommandExecutionRequest(
                    commandID: request.invocation.commandID,
                    action: CommandAction(
                        id: "media.download.batch.\(UUID().uuidString)",
                        title: "Download",
                        kind: .downloadMedia(url: url)
                    ),
                    source: request.invocation.source,
                    context: request.invocation.context
                )
                Task { @MainActor [weak self] in
                    _ = await self?.execute(childRequest, emit: emit)
                }
            }
            return .open(route: .mediaDownloads)

        case let .downloadMedia(urlString):
            diagnostics.log("Starting media download")
            let downloadID = request.invocation.cancellationID
            mediaDownloadManager.start(id: downloadID, sourceURL: urlString)
            let result: String
            do {
                result = try await mediaDownloadService.download(
                    urlString: urlString,
                    status: { status in emit(.status(status)) },
                    progress: { progress in
                        self.mediaDownloadManager.update(id: downloadID, progress: progress)
                        emit(.downloadProgress(progress))
                    }
                )
            } catch {
                if Self.isCancellation(error) {
                    mediaDownloadManager.cancel(id: downloadID)
                    return .cancelled
                }
                let message = "Media download failed: \(error.localizedDescription)"
                mediaDownloadManager.fail(id: downloadID, message: message)
                diagnostics.log(message)
                return finish(.stayOpen(message: message), feedback: .failure(message))
            }
            guard Task.isCancelled == false else {
                mediaDownloadManager.cancel(id: downloadID)
                return .cancelled
            }
            emit(.status(result))
            diagnostics.log(result)
            let failed = Self.isMediaDownloadFailure(result)
            if failed {
                mediaDownloadManager.fail(id: downloadID, message: result)
            } else {
                mediaDownloadManager.complete(id: downloadID, message: result)
            }
            let outcome: CommandOutcome = .stayOpen(message: result)
            return outcome

        case .chooseMediaDownloadFolder:
            let panel = NSOpenPanel()
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.allowsMultipleSelection = false
            panel.directoryURL = MediaDownloadDestination.folder
            guard panel.runModal() == .OK, let url = panel.url else { return .cancelled }
                MediaDownloadDestination.setFolder(url)
                emit(.status("Downloads will save to \(url.lastPathComponent)"))
                diagnostics.log("Media download folder changed: \(url.path)")
            return finish(.refreshResults(message: "Download folder changed"), feedback: .success("Download folder changed"))

        case .openEmojiPicker:
            return .open(route: .emojiPicker)

        case .openFileShelf:
            return .open(route: .fileShelf)

        case .openClipboardHistory:
            return .open(route: .clipboardHistory)

        case .openSnippets:
            return .open(route: .snippets)

        case let .openFileConverter(path):
            return .open(route: .fileConversion(path: path))

        case .openCamera:
            return .open(route: .camera)

        case let .openTranslator(text, language):
            return .open(route: .translator(text: text, language: language))

        case let .openDeveloperTools(tool):
            return .open(route: .developerTools(tool: tool))

        case .openSettings:
            return .open(route: .settings)

        case .openDashboard:
            return .open(route: .dashboard)

        case .openMediaDownloads:
            return .open(route: .mediaDownloads)

        case let .terminateProcess(pid):
            do {
                if kill(pid, SIGTERM) == 0 {
                    diagnostics.log("Terminated process \(pid)")
                    return finish(.success(message: "Terminated process"), feedback: .success("Terminated process"))
                } else {
                    throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EPERM)
                }
            } catch {
                if Self.isCancellation(error) {
                    return .cancelled
                }
                diagnostics.log("Failed to terminate process \(pid): \(error.localizedDescription)")
                return finish(.failure(message: "Could not terminate process", retryable: true), feedback: .failure("Could not terminate process"))
            }

        case let .quitApplication(bundleID, name):
            let running = NSWorkspace.shared.runningApplications.first {
                ($0.bundleIdentifier == bundleID && bundleID != nil)
                    || $0.localizedName == name
            }
            if let running {
                if running.terminate() || running.forceTerminate() {
                    diagnostics.log("Quit \(name)")
                    return finish(.success(message: "Quit \(name)"), feedback: .success("Quit \(name)"))
                } else {
                    diagnostics.log("Failed to quit \(name)")
                    return finish(.failure(message: "Could not quit \(name)", retryable: true), feedback: .failure("Could not quit \(name)"))
                }
            } else {
                diagnostics.log("\(name) is not running")
                return .failure(message: "\(name) is not running", retryable: false)
            }

        case .toggleKeepAwake:
            let state = KeepAwakeController.toggle()
            diagnostics.log(state ? "Keep Awake enabled" : "Keep Awake disabled")
            return finish(.success(message: state ? "Keep Awake enabled" : "Keep Awake disabled"), feedback: .success(state ? "Keep Awake enabled" : "Keep Awake disabled"))

        case let .terminatePort(port):
            let command = "lsof -ti tcp:\(port) | xargs -r kill"
            do {
                let result = try await ProcessRunner.run(path: "/bin/zsh", arguments: ["-lc", command], timeout: 3)
                let message = result.succeeded ? "Stopped port \(port)" : "Failed to stop port \(port)"
                diagnostics.log(message)
                return finish(result.succeeded ? .success(message: message) : .failure(message: message, retryable: true), feedback: result.succeeded ? .success(message) : .failure(message))
            } catch {
                if Self.isCancellation(error) {
                    return .cancelled
                }
                diagnostics.log("Failed to stop port \(port): \(error.localizedDescription)")
                return finish(.failure(message: "Failed to stop port \(port)", retryable: true), feedback: .failure("Failed to stop port \(port)"))
            }

        case let .setAudioDevice(id, kind):
            do {
                try AudioDeviceController.setDevice(id: id, kind: kind)
                diagnostics.log("Updated \(kind == .output ? "output" : "input") audio device")
                return finish(.success(message: "Audio device updated"), feedback: .success("Audio device updated"))
            } catch {
                diagnostics.log("Failed to switch audio device: \(error.localizedDescription)")
                return finish(.failure(message: "Could not switch audio device", retryable: true), feedback: .failure("Could not switch audio device"))
            }

        case let .resetRanking(commandID):
            resetRanking(commandID)
            return finish(.stayOpen(message: "Ranking reset"), feedback: .success("Ranking reset"))

        case .rebuildApp:
            guard let sourceRoot = Bundle.main.object(forInfoDictionaryKey: "FoundrySourceRoot") as? String else {
                diagnostics.log("Cannot rebuild Foundry: source root is unavailable")
                return .failure(message: "Cannot rebuild Foundry", retryable: false)
            }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-lc", "cd -- \"$1\" && ./scripts/build-app.sh", "foundry-rebuild", sourceRoot]
            do {
                try process.run()
                diagnostics.log("Started Foundry app rebuild")
                return .success(message: "Started Foundry app rebuild")
            } catch {
                diagnostics.log("Failed to rebuild Foundry app: \(error.localizedDescription)")
                return .failure(message: "Failed to rebuild Foundry app", retryable: true)
            }

        case let .runProcess(path, arguments):
            do {
                let result = try await ProcessRunner.run(path: path, arguments: arguments)
                guard result.succeeded else {
                    diagnostics.log("Failed to run \(path)")
                    return .failure(message: "Failed to run process", retryable: true)
                }
                return .success(message: "Process completed")
            } catch {
                if Self.isCancellation(error) {
                    return .cancelled
                }
                diagnostics.log("Failed to run \(path): \(error.localizedDescription)")
                return .failure(message: "Failed to run process", retryable: true)
            }

        case .quit:
            NSApp.terminate(nil)
            return .success(message: "Quitting Foundry")

        case let .log(message):
            diagnostics.log(message)
            return .success(message: nil)
        }
    }

    func cancel(_ cancellationID: UUID) {
        activeExecutionTasks[cancellationID]?.cancel()
    }

    nonisolated private static let snippetLimit = 65_536

    private func importSnippets() -> CommandOutcome {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return .cancelled }

        do {
            let data = try Data(contentsOf: url)
            let imported = try JSONDecoder().decode([RaycastSnippetImport].self, from: data)
            var snippets = snippetStore.load()
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

            if case let .failure(error) = snippetStore.save(snippets) {
                diagnostics.log("Failed to save imported snippets: \(error.localizedDescription)")
                return .failure(message: "Could not save imported snippets", retryable: true)
            }
            let message = "Imported \(added) snippets, skipped \(skipped) duplicates"
            diagnostics.log(message)
            return .success(message: message)
        } catch {
            diagnostics.log("Snippet import failed: \(error.localizedDescription)")
            return .failure(message: "Snippet import failed", retryable: false)
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

    nonisolated private static func isCancellation(_ error: Error) -> Bool {
        if Task.isCancelled { return true }
        return (error as? ProcessRunnerError) == .cancelled
    }

    nonisolated private static func isMediaDownloadFailure(_ result: String) -> Bool {
        let normalized = result.lowercased()
        return normalized.contains("media download failed") || normalized.contains("invalid media url")
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
