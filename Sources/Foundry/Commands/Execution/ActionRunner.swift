import AppKit
import Carbon
import CoreAudio
import Foundation
import FoundryDomain
import FoundryServices
import UniformTypeIdentifiers

@MainActor
final class ActionRunner {
    private let diagnostics: DiagnosticsService
    private let snippetStore: any SnippetStore
    private let mediaDownloadService: any MediaDownloading
    private let mediaDownloadManager: MediaDownloadManager
    private let resetRanking: (String) -> Void
    private let confirmAction: (CommandActionDescriptor, CommandInvocationSource) -> Bool
    private let windowManager: any WindowManaging
    private let openURL: (URL) -> Bool
    private let openApplication: (URL, NSWorkspace.OpenConfiguration, @escaping @Sendable (NSRunningApplication?, Error?) -> Void) -> Void
    private let snippetContext: () -> SnippetRenderContext
    private let pasteboard: NSPasteboard
    let directPasteService: DirectPasteService
    private let scriptDirectories: ScriptDirectoryStore
    private let confirmScriptDirectory: @MainActor (String) -> Bool
    private let scriptTimeout: TimeInterval
    private let scriptOutputLimit: Int
    private var activeExecutionTasks: [UUID: Task<CommandOutcome, Never>] = [:]

    init(
        diagnostics: DiagnosticsService,
        snippetStore: any SnippetStore = FileSnippetStore(),
        mediaDownloadService: any MediaDownloading = MediaDownloadService(),
        mediaDownloadManager: MediaDownloadManager = MediaDownloadManager(),
        resetRanking: @escaping (String) -> Void = { _ in },
        confirmAction: @escaping (CommandActionDescriptor, CommandInvocationSource) -> Bool = { _, _ in true },
        windowManager: any WindowManaging = NativeWindowManager(),
        openURL: @escaping (URL) -> Bool = { NSWorkspace.shared.open($0) },
        openApplication: @escaping (URL, NSWorkspace.OpenConfiguration, @escaping @Sendable (NSRunningApplication?, Error?) -> Void) -> Void = { url, configuration, completion in
            NSWorkspace.shared.openApplication(at: url, configuration: configuration, completionHandler: completion)
        },
        directPasteService: DirectPasteService = .shared,
        pasteboard: NSPasteboard = .general,
        snippetContext: @escaping () -> SnippetRenderContext = { .current() },
        scriptDirectories: ScriptDirectoryStore = .shared,
        confirmScriptDirectory: @escaping @MainActor (String) -> Bool = ActionRunner.promptToTrustScriptDirectory,
        scriptTimeout: TimeInterval = 30,
        scriptOutputLimit: Int = 256 * 1024
    ) {
        self.scriptDirectories = scriptDirectories
        self.confirmScriptDirectory = confirmScriptDirectory
        self.scriptTimeout = scriptTimeout
        self.scriptOutputLimit = scriptOutputLimit
        self.diagnostics = diagnostics
        self.snippetStore = snippetStore
        self.mediaDownloadService = mediaDownloadService
        self.mediaDownloadManager = mediaDownloadManager
        self.resetRanking = resetRanking
        self.confirmAction = confirmAction
        self.windowManager = windowManager
        self.openURL = openURL
        self.openApplication = openApplication
        self.snippetContext = snippetContext
        self.pasteboard = pasteboard
        self.directPasteService = directPasteService
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
            let completion = ContinuationGate<CommandOutcome>()
            return await withTaskCancellationHandler(operation: {
                await withCheckedContinuation { continuation in
                    completion.install(continuation)
                    if Task.isCancelled {
                        completion.resume(.cancelled)
                        return
                    }
                    self.openApplication(URL(fileURLWithPath: path), configuration) { [diagnostics] _, error in
                    Task { @MainActor in
                        let outcome: CommandOutcome
                        if let error {
                            diagnostics.log("Failed to launch \(name): \(error.localizedDescription)")
                            outcome = .failure(message: "Could not open \(name)", retryable: true)
                        } else {
                            diagnostics.log("Launched app: \(name)")
                            outcome = .success(message: "Opened \(name)")
                        }
                        if completion.resume(outcome), case .failure = outcome {
                            emit(.feedback(.failure("Could not open \(name)")))
                        }
                    }
                }
                }
            }, onCancel: { completion.resume(.cancelled) })

        case let .openURL(urlString):
            guard let url = URL(string: urlString) else {
                diagnostics.log("Invalid URL: \(urlString)")
                return finish(.failure(message: "That link isn't a valid URL", retryable: false), feedback: .failure("That link isn't a valid URL"))
            }
            if openURL(url) == false {
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

        case let .openFileWithApp(path, appPath):
            if await Self.open([URL(fileURLWithPath: path)], withAppAt: URL(fileURLWithPath: appPath)) == false {
                return finish(.failure(message: "Could not open file with that app", retryable: true), feedback: .failure("Could not open file with that app"))
            }
            return .success(message: "Opened file")

        case let .openURLWithApp(urlString, bundleID):
            guard let url = URL(string: urlString) else {
                return finish(.failure(message: "That link isn't valid", retryable: false), feedback: .failure("That link isn't valid"))
            }
            guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
                return finish(.failure(message: "That app isn't installed", retryable: false), feedback: .failure("That app isn't installed"))
            }
            if await Self.open([url], withAppAt: appURL) == false {
                return finish(.failure(message: "Could not open link with that app", retryable: true), feedback: .failure("Could not open link with that app"))
            }
            return .success(message: "Opened link")

        case let .copyToClipboard(value):
            pasteboard.clearContents()
            pasteboard.setString(value, forType: .string)
            diagnostics.log("Copied to clipboard")
            return finish(.copied(content: value), feedback: .success(Self.copiedMessage(for: value)))

        case let .copyFile(path):
            let url = URL(fileURLWithPath: path)
            pasteboard.clearContents()
            pasteboard.writeObjects([url as NSURL])
            diagnostics.log("Copied file")
            return finish(.copied(content: path), feedback: .success("Copied \u{201C}\(url.lastPathComponent)\u{201D}"))

        case let .addToFileShelf(path):
            return .addToFileShelf(urls: [URL(fileURLWithPath: path)])

        case let .copySnippet(id):
            guard let snippet = snippetStore.load().first(where: { $0.id == id }) else { return .failure(message: "Snippet not found", retryable: false) }
            let rendered = SnippetRenderer.render(snippet.content, context: snippetContext())
            pasteboard.clearContents(); pasteboard.setString(rendered.text, forType: .string)
            return finish(.copied(content: rendered.text), feedback: .success("Copied to clipboard"))

        case let .deleteSnippet(id):
            let snippets = snippetStore.load()
            guard snippets.contains(where: { $0.id == id }) else { return .failure(message: "Snippet not found", retryable: false) }
            _ = snippetStore.save(snippets.filter { $0.id != id })
            return finish(.refreshResults(message: "Snippet deleted"), feedback: .success("Snippet deleted"))

        case let .deleteQuicklink(id):
            let store = QuicklinkStore.shared
            let links = store.load()
            guard links.contains(where: { $0.id == id }) else { return .failure(message: "Quicklink not found", retryable: false) }
            do {
                try store.save(links.filter { $0.id != id })
            } catch {
                return finish(.failure(message: "Quicklink could not be deleted", retryable: true), feedback: .failure("Quicklink could not be deleted"))
            }
            return finish(.refreshResults(message: "Quicklink deleted"), feedback: .success("Quicklink deleted"))

        case let .pasteSnippet(id):
            guard let snippet = snippetStore.load().first(where: { $0.id == id }) else { return .failure(message: "Snippet not found", retryable: false) }
            let rendered = SnippetRenderer.render(snippet.content, context: snippetContext())
            do {
                try directPasteService.stage(.text(rendered.text), cursorOffset: rendered.cursorOffsetFromEnd)
                return finish(.pasted(content: rendered.text), feedback: .success("Inserted snippet"))
            } catch DirectPasteError.missingTarget { return finish(.stayOpen(message: "No originating application is available"), feedback: .failure("No originating application is available")) }
            catch { return finish(.stayOpen(message: "Could not stage paste"), feedback: .failure("Could not stage paste")) }

        case let .pasteText(value, cursorOffset, _):
            do {
                try directPasteService.stage(.text(value), cursorOffset: cursorOffset)
                diagnostics.log("Staged direct paste")
                return finish(.pasted(content: value), feedback: .success("Inserted snippet"))
            } catch DirectPasteError.missingTarget {
                return finish(.stayOpen(message: "No originating application is available"), feedback: .failure("No originating application is available"))
            } catch {
                return finish(.stayOpen(message: "Could not stage paste"), feedback: .failure("Could not stage paste"))
            }

        case .createSnippetFromClipboard:
            guard let content = pasteboard.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines), content.isEmpty == false else {
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
            let concurrencyLimit = 3
            var nextIndex = 0
            var results: [MediaBatchResult] = []
            await withTaskGroup(of: MediaBatchResult.self) { group in
                for _ in 0..<min(concurrencyLimit, urls.count) {
                    let index = nextIndex
                    nextIndex += 1
                    group.addTask {
                        await self.downloadMediaBatchItem(urls[index], index: index, emit: emit)
                    }
                }

                while let result = await group.next() {
                    if result.status == .cancelled {
                        group.cancelAll()
                        results.append(result)
                        break
                    }
                    results.append(result)
                    if nextIndex < urls.count {
                        let index = nextIndex
                        nextIndex += 1
                        group.addTask {
                            await self.downloadMediaBatchItem(urls[index], index: index, emit: emit)
                        }
                    }
                }
            }
            if results.contains(where: { $0.status == .cancelled }) { return .cancelled }
            let completed = results.filter { $0.status.isCompleted }.count
            let failures = results
                .sorted { $0.index < $1.index }
                .compactMap { result -> String? in
                    guard case let .failed(message) = result.status else { return nil }
                    let url = urls[result.index]
                    return "\(URL(string: url)?.lastPathComponent ?? url): \(message)"
                }
            let message = failures.isEmpty
                ? "Downloaded \(completed) of \(urls.count) media links"
                : "Downloaded \(completed) of \(urls.count); failed: \(failures.joined(separator: "; "))"
            emit(.status(message))
            return .open(route: .mediaDownloads)

        case let .downloadMedia(urlString):
            diagnostics.log("Starting media download")
            mediaDownloadManager.setCapabilities(mediaDownloadService.mediaCapabilities())
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
                let message = error.localizedDescription
                mediaDownloadManager.fail(id: downloadID, message: message)
                diagnostics.log(message)
                return finish(.failure(message: message, retryable: (error as? MediaDownloadError)?.isRetryable ?? false), feedback: .failure(message))
            }
            guard Task.isCancelled == false else {
                mediaDownloadManager.cancel(id: downloadID)
                return .cancelled
            }
            emit(.status(result))
            diagnostics.log(result)
            mediaDownloadManager.complete(id: downloadID, message: result)
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

        case .openSettings, .openCommandSettings:
            return .open(route: .settings)

        case .openWelcomeGuide:
            return .open(route: .welcomeGuide)

        case let .fillQuery(text):
            return .open(route: .query(text))

        case .openHome:
            return .open(route: .home)

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

        case let .forceQuitApplication(bundleID, name):
            guard let running = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleID && bundleID != nil || $0.localizedName == name }) else {
                return .failure(message: "\(name) is not running", retryable: false)
            }
            return running.forceTerminate()
                ? finish(.success(message: "Force quit \(name)"), feedback: .success("Force quit \(name)"))
                : finish(.failure(message: "Could not force quit \(name)", retryable: true), feedback: .failure("Could not force quit \(name)"))

        case let .hideApplication(bundleID, name):
            let hidden = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).map { $0.hide() }.contains(true)
            return hidden ? finish(.success(message: "Hid \(name)"), feedback: .success("Hid \(name)")) : .failure(message: "\(name) is not running", retryable: false)

        case .quitAllApplications:
            let spared: Set<String> = [Bundle.main.bundleIdentifier ?? "", "com.apple.finder"]
            let targets = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular && spared.contains($0.bundleIdentifier ?? "") == false }
            let quit = targets.filter { $0.terminate() }.count
            return finish(.success(message: "Asked \(quit) apps to quit"), feedback: .success("Asked \(quit) apps to quit"))

        case .toggleKeepAwake:
            do {
                let state = try KeepAwakeController.toggle()
                diagnostics.log(state ? "Keep Awake enabled" : "Keep Awake disabled")
                return finish(.success(message: state ? "Keep Awake enabled" : "Keep Awake disabled"), feedback: .success(state ? "Keep Awake enabled" : "Keep Awake disabled"))
            } catch {
                diagnostics.log("Could not update Keep Awake: \(error.localizedDescription)")
                return finish(.failure(message: "Could not update Keep Awake", retryable: true), feedback: .failure("Could not update Keep Awake"))
            }

        case let .terminatePort(port):
            do {
                let lookup = try await ProcessRunner.run(path: "/usr/sbin/lsof", arguments: ["-ti", "tcp:\(port)"], timeout: 3)
                let pids = lookup.stdout.split(whereSeparator: \.isNewline).map(String.init)
                guard lookup.succeeded, pids.isEmpty == false else {
                    let message = "No process is listening on port \(port)"
                    diagnostics.log(message)
                    return finish(.failure(message: message, retryable: true), feedback: .failure(message))
                }
                var failed = false
                for pid in pids {
                    let result = try await ProcessRunner.run(path: "/bin/kill", arguments: [pid], timeout: 3)
                    failed = failed || !result.succeeded
                }
                let message = failed ? "Couldn't stop the process on port \(port)" : "Stopped port \(port)"
                diagnostics.log(message)
                return finish(failed ? .failure(message: message, retryable: true) : .success(message: message), feedback: failed ? .failure(message) : .success(message))
            } catch {
                if Self.isCancellation(error) {
                    return .cancelled
                }
                diagnostics.log("Failed to stop port \(port): \(error.localizedDescription)")
                return finish(.failure(message: "Couldn't stop the process on port \(port)", retryable: true), feedback: .failure("Couldn't stop the process on port \(port)"))
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

        case .toggleFavorite:
            return .stayOpen(message: nil)

        case .rebuildApp:
            #if DEBUG
            guard let sourceRoot = SourceRootLocator.locate() else {
                diagnostics.log("Cannot rebuild Foundry: source root is unavailable")
                return .failure(message: "Cannot rebuild Foundry", retryable: false)
            }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.currentDirectoryURL = sourceRoot
            process.arguments = ["-lc", "INSTALL_APP=1 ./scripts/build-app.sh", "foundry-rebuild"]
            do {
                try process.run()
                diagnostics.log("Started Foundry app rebuild")
                return .success(message: "Started Foundry app rebuild")
            } catch {
                diagnostics.log("Failed to rebuild Foundry app: \(error.localizedDescription)")
                return .failure(message: "Failed to rebuild Foundry app", retryable: true)
            }
            #else
            diagnostics.log("Cannot rebuild Foundry outside a debug build")
            return .failure(message: "Cannot rebuild Foundry", retryable: false)
            #endif

        case let .runProcess(path, arguments):
            do {
                let result = try await ProcessRunner.run(path: path, arguments: arguments)
                let shortcut = path == ShortcutsProvider.cliPath ? arguments.last : nil
                guard result.succeeded else {
                    diagnostics.log("Failed to run \(path)")
                    return .failure(message: shortcut.map { "“\($0)” failed: \(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))" } ?? "Failed to run process", retryable: true)
                }
                return .success(message: shortcut.map { "Ran “\($0)”" } ?? "Process completed")
            } catch {
                if Self.isCancellation(error) {
                    return .cancelled
                }
                diagnostics.log("Failed to run \(path): \(error.localizedDescription)")
                return .failure(message: "Failed to run process", retryable: true)
            }

        case let .runScript(path, arguments, mode):
            let directory = (path as NSString).deletingLastPathComponent
            if scriptDirectories.isTrusted(directory) == false {
                guard confirmScriptDirectory(directory) else {
                    return finish(.denied(message: "Scripts in this folder are not trusted"), feedback: .info("Script not run"))
                }
                scriptDirectories.setTrusted(true, for: directory)
            }
            let name = (path as NSString).lastPathComponent
            do {
                let result = try await ProcessRunner.run(path: path, arguments: arguments, timeout: scriptTimeout, outputLimit: scriptOutputLimit, currentDirectoryURL: URL(fileURLWithPath: directory))
                let lastLine = { (text: String) in text.split(whereSeparator: \.isNewline).last.map(String.init) }
                if result.timedOut {
                    return finish(.failure(message: "\(name) timed out after \(Int(scriptTimeout)) s", retryable: true), feedback: .failure("\(name) timed out"))
                }
                guard result.succeeded else {
                    let message = lastLine(result.stderr) ?? lastLine(result.stdout) ?? "\(name) exited with code \(result.exitCode)"
                    return finish(.failure(message: message, retryable: true), feedback: .failure(message))
                }
                switch mode {
                case .silent:
                    return .success(message: nil)
                case .compact, .inline:
                    return finish(.success(message: lastLine(result.stdout) ?? "Ran \(name)"), feedback: .success(lastLine(result.stdout) ?? "Ran \(name)"))
                case .fullOutput:
                    let url = FileManager.default.temporaryDirectory.appendingPathComponent("Foundry \(name) output.txt")
                    try Data((result.stdout + result.stderr).utf8).write(to: url, options: .atomic)
                    _ = openURL(url)
                    return .success(message: "Opened output of \(name)")
                }
            } catch {
                if Self.isCancellation(error) { return .cancelled }
                return finish(.failure(message: "Could not run \(name): \(error.localizedDescription)", retryable: true), feedback: .failure("Could not run \(name)"))
            }

        case let .tileWindow(placement):
            switch await windowManager.apply(placement) {
            case let .tiled(resultPlacement):
                let message = WindowPlacementMetadata(resultPlacement).successMessage
                return finish(.success(message: message), feedback: .success(message))
            case let .constrained(resultPlacement):
                let message = "Window was constrained while applying \(WindowPlacementMetadata(resultPlacement).title.lowercased())"
                return finish(.success(message: message), feedback: .info(message))
            case .restored:
                return finish(.success(message: "Restored previous window frame"), feedback: .success("Restored previous window frame"))
            case .needsAccessibilityPermission:
                return finish(
                    .stayOpen(message: "Accessibility permission required for window control"),
                    feedback: .failure("Grant Accessibility access in System Settings to control windows")
                )
            case let .failed(message):
                return finish(.failure(message: message, retryable: false), feedback: .failure(message))
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

    private static func open(_ urls: [URL], withAppAt appURL: URL) async -> Bool {
        await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            NSWorkspace.shared.open(urls, withApplicationAt: appURL, configuration: NSWorkspace.OpenConfiguration()) { _, error in
                continuation.resume(returning: error == nil)
            }
        }
    }

    nonisolated private static func snippetTitle(from content: String) -> String {
        let firstLine = content.split(separator: "\n").first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return firstLine.isEmpty ? "Clipboard Snippet" : String(firstLine.prefix(60))
    }

    nonisolated private static func isCancellation(_ error: Error) -> Bool {
        if Task.isCancelled { return true }
        return (error as? ProcessRunnerError) == .cancelled
    }

    private func downloadMediaBatchItem(
        _ url: String,
        index: Int,
        emit: @escaping @MainActor @Sendable (CommandExecutionEvent) -> Void
    ) async -> MediaBatchResult {
        let id = UUID()
        mediaDownloadManager.start(id: id, sourceURL: url)
        do {
            let result = try await mediaDownloadService.download(urlString: url, status: { emit(.status($0)) }, progress: {
                self.mediaDownloadManager.update(id: id, progress: $0)
                emit(.downloadProgress($0))
            })
            mediaDownloadManager.complete(id: id, message: result)
            return MediaBatchResult(index: index, status: .completed)
        } catch {
            guard Self.isCancellation(error) else {
                let message = error.localizedDescription
                mediaDownloadManager.fail(id: id, message: message)
                return MediaBatchResult(index: index, status: .failed(message))
            }
            mediaDownloadManager.cancel(id: id)
            return MediaBatchResult(index: index, status: .cancelled)
        }
    }

    static func promptToTrustScriptDirectory(_ directory: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = "Run scripts from “\((directory as NSString).lastPathComponent)”?"
        alert.informativeText = "Scripts in \(directory) can run any command as you. Only trust folders whose scripts you wrote or reviewed. Foundry will not ask again for this folder."
        alert.addButton(withTitle: "Trust and Run")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }
}

private struct MediaBatchResult: Sendable {
    enum Status: Sendable, Equatable {
        case completed
        case failed(String)
        case cancelled

        var isCompleted: Bool {
            if case .completed = self { return true }
            return false
        }
    }

    let index: Int
    let status: Status
}

protocol KeepAwakeProcessHandle: AnyObject {
    var isRunning: Bool { get }
    func stop()
}

final class KeepAwakeProcessOwner: @unchecked Sendable {
    private let lock = NSLock()
    private var process: (any KeepAwakeProcessHandle)?

    var isActive: Bool {
        lock.withLock { process?.isRunning == true }
    }

    func toggle(launch: () throws -> any KeepAwakeProcessHandle) throws -> Bool {
        try lock.withLock {
            if let process, process.isRunning {
                process.stop()
                self.process = nil
                return false
            }
            process = nil
            let launched = try launch()
            process = launched
            return true
        }
    }

    func stop() {
        lock.withLock {
            if process?.isRunning == true { process?.stop() }
            process = nil
        }
    }
}

final class NativeKeepAwakeProcess: KeepAwakeProcessHandle {
    private let process: Process

    init() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate")
        process.arguments = Self.arguments(parentProcessID: ProcessInfo.processInfo.processIdentifier)
        try process.run()
        self.process = process
    }

    static func arguments(parentProcessID: Int32) -> [String] {
        ["-dimsu", "-w", String(parentProcessID)]
    }

    var isRunning: Bool { process.isRunning }

    func stop() {
        process.terminate()
    }
}

enum KeepAwakeController {
    private static let owner = KeepAwakeProcessOwner()

    static func toggle() throws -> Bool {
        try owner.toggle { try NativeKeepAwakeProcess() }
    }

    static func isActive() -> Bool {
        owner.isActive
    }

    static func stop() {
        owner.stop()
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

private final class ContinuationGate<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Never>?
    private var result: Value?

    func install(_ continuation: CheckedContinuation<Value, Never>) {
        var pending: Value?
        lock.withLock {
            if self.result != nil {
                pending = self.result
                self.result = nil
                return
            }
            self.continuation = continuation
        }
        if let pending { continuation.resume(returning: pending) }
    }

    @discardableResult
    func resume(_ result: Value) -> Bool {
        var continuation: CheckedContinuation<Value, Never>?
        lock.withLock {
            guard self.result == nil else { return }
            guard let installed = self.continuation else {
                self.result = result
                return
            }
            self.continuation = nil
            continuation = installed
        }
        guard let continuation else { return false }
        continuation.resume(returning: result)
        return true
    }
}

extension ActionRunner {
    static func copiedMessage(for value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false, trimmed.count <= 32, trimmed.contains(where: \.isNewline) == false else { return "Copied to clipboard" }
        return "Copied \(trimmed)"
    }
}
