import AppKit
import Carbon
import CoreAudio
import CoreImage
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
    private let localState: LocalStateStore
    private let confirmScriptDirectory: @MainActor (String) -> Bool
    private let offerQRSave: @MainActor (NSImage, String) -> Void
    private let scriptTimeout: TimeInterval
    private let scriptOutputLimit: Int
    private var activeExecutionTasks: [UUID: Task<CommandOutcome, Never>] = [:]
    var onQuickLook: (@MainActor (URL) -> Void)?

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
        localState: LocalStateStore = .shared,
        confirmScriptDirectory: @escaping @MainActor (String) -> Bool = ActionRunner.promptToTrustScriptDirectory,
        offerQRSave: @escaping @MainActor (NSImage, String) -> Void = ActionRunner.presentQRSaveOffer,
        scriptTimeout: TimeInterval = 30,
        scriptOutputLimit: Int = 256 * 1024
    ) {
        self.scriptDirectories = scriptDirectories
        self.localState = localState
        self.confirmScriptDirectory = confirmScriptDirectory
        self.offerQRSave = offerQRSave
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

        case let .revealFile(path):
            return .fileResults([URL(fileURLWithPath: path)])

        case let .compressFile(path):
            return await compressFile(path: path, emit: emit)

        case let .shareFile(path):
            return shareFile(path: path)

        case let .renameFile(path):
            return await renameFile(path: path, emit: emit)

        case let .moveToTrash(path):
            let url = URL(fileURLWithPath: path)
            do {
                try FileManager.default.trashItem(at: url, resultingItemURL: nil)
                diagnostics.log("Moved to Trash: \(path)")
                return finish(.refreshResults(message: "Moved to Trash"), feedback: .success("Moved \u{201C}\(url.lastPathComponent)\u{201D} to Trash"))
            } catch {
                diagnostics.log("Trash failed for \(path): \(error.localizedDescription)")
                return finish(.failure(message: "Could not move to Trash", retryable: true), feedback: .failure("Could not move to Trash"))
            }

        case let .addToFileShelf(path):
            return .addToFileShelf(urls: [URL(fileURLWithPath: path)])

        case let .copySnippet(id):
            guard let snippet = snippetStore.load().first(where: { $0.id == id }) else { return .failure(message: "Snippet not found", retryable: false) }
            let rendered = SnippetRenderer.render(snippet.content, context: snippetContext())
            pasteboard.clearContents(); pasteboard.setString(rendered.text, forType: .string)
            recordSnippetUse(id: id)
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
                recordSnippetUse(id: id)
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

        case .exportSnippets:
            let outcome = exportSnippets()
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

        case let .extractTextFromImage(path):
            return await extractTextFromImage(path: path, emit: emit)
        case let .previewExtractedText(path):
            return await previewExtractedText(path: path, emit: emit)

        case .pickColor:
            return await pickColor(emit: emit)

        case .generateQRCode:
            return generateQRCode(emit: emit)

        case .generateWiFiQRCode:
            return generateWiFiQRCode(emit: emit)

        case .readQRCode:
            return await readQRCode(emit: emit)

        case .recognizeScreenText:
            return await recognizeScreenText(emit: emit)

        case .emptyTrash:
            return await emptyTrash(emit: emit)

        case .toggleDesktopIcons:
            return await toggleDesktopIcons(emit: emit)

        case .pasteClipboardAsPlainText:
            guard let text = pasteboard.string(forType: .string), text.isEmpty == false else {
                return finish(.failure(message: "Clipboard has no text", retryable: false), feedback: .info("Clipboard has no text"))
            }
            do {
                try directPasteService.stage(.text(text), cursorOffset: 0)
                return finish(.pasted(content: text), feedback: .success("Pasted as plain text"))
            } catch DirectPasteError.missingTarget {
                return finish(.stayOpen(message: "No originating application is available"), feedback: .failure("No originating application is available"))
            } catch {
                return finish(.stayOpen(message: "Could not stage paste"), feedback: .failure("Could not stage paste"))
            }

        case .celebrate:
            return finish(.stayOpen(message: nil), feedback: .success("🎉"))

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

    private func exportSnippets() -> CommandOutcome {
        let snippets = snippetStore.load()
        guard snippets.isEmpty == false else {
            return .failure(message: "No snippets to export", retryable: false)
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "foundry-snippets.json"
        guard panel.runModal() == .OK, let url = panel.url else { return .cancelled }

        let exported = snippets.map { RaycastSnippetExport(name: $0.title, text: $0.content, keyword: $0.keyword.isEmpty ? nil : $0.keyword) }
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(exported).write(to: url, options: .atomic)
            let message = "Exported \(snippets.count) snippet\(snippets.count == 1 ? "" : "s")"
            diagnostics.log("\(message) to \(url.path)")
            return .success(message: message)
        } catch {
            diagnostics.log("Snippet export failed: \(error.localizedDescription)")
            return .failure(message: "Snippet export failed", retryable: true)
        }
    }

    private func recordSnippetUse(id: String) {
        var snippets = snippetStore.load()
        guard let index = snippets.firstIndex(where: { $0.id == id }) else { return }
        snippets[index].recordUse()
        _ = snippetStore.save(snippets)
    }

    private func pickImageFile(title: String) -> URL? {
        let panel = NSOpenPanel()
        panel.title = title
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        return panel.runModal() == .OK ? panel.url : nil
    }

    private func extractTextFromImage(path: String?, emit: @escaping @MainActor @Sendable (CommandExecutionEvent) -> Void) async -> CommandOutcome {
        let url = path.map { URL(fileURLWithPath: $0) } ?? pickImageFile(title: "Extract Text from Image")
        guard let url else { return .cancelled }
        do {
            emit(.status("Recognizing text…"))
            let lines = try await VisionText.recognizeText(at: url)
            let text = lines.joined(separator: "\n")
            guard text.isEmpty == false else {
                return .failure(message: "No text found in \(url.lastPathComponent)", retryable: false)
            }
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
            diagnostics.log("OCR extracted \(lines.count) lines from \(url.lastPathComponent)")
            return .copied(content: text)
        } catch {
            diagnostics.log("OCR failed: \(error.localizedDescription)")
            return .failure(message: "Could not extract text", retryable: true)
        }
    }

    /// OCR an image, stage the text as a temp file, and Quick Look it —
    /// the "result → quicklook" path for extracted text.
    private func previewExtractedText(path: String, emit: @escaping @MainActor @Sendable (CommandExecutionEvent) -> Void) async -> CommandOutcome {
        let url = URL(fileURLWithPath: path)
        do {
            emit(.status("Recognizing text…"))
            let lines = try await VisionText.recognizeText(at: url)
            guard try presentExtractedText(lines, sourceName: url.deletingPathExtension().lastPathComponent, suffix: "OCR", emit: emit) else {
                return .failure(message: "No text found in \(url.lastPathComponent)", retryable: false)
            }
            return onQuickLook == nil ? .success(message: nil) : .stayOpen(message: nil)
        } catch {
            diagnostics.log("OCR preview failed: \(error.localizedDescription)")
            return .failure(message: "Could not extract text", retryable: true)
        }
    }

    /// Stage extracted/decoded text as a temp file and present it via Quick
    /// Look (or open it when no panel is wired). Returns false when empty.
    private func presentExtractedText(_ lines: [String], sourceName: String, suffix: String, emit: @escaping @MainActor @Sendable (CommandExecutionEvent) -> Void) throws -> Bool {
        let text = lines.joined(separator: "\n")
        guard text.isEmpty == false else { return false }
        let preview = try stageTextPreview(text, named: "\(sourceName) — \(suffix)")
        if let onQuickLook {
            onQuickLook(preview)
        } else {
            NSWorkspace.shared.open(preview)
        }
        return true
    }

    private func stageTextPreview(_ text: String, named name: String) throws -> URL {
        let staging = FileManager.default.temporaryDirectory.appendingPathComponent("FoundryOCR", isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        let preview = staging.appendingPathComponent("\(name).txt")
        try text.write(to: preview, atomically: true, encoding: .utf8)
        return preview
    }

    private func cgImage(from data: Data) -> CGImage? {
        NSImage(data: data)?.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }

    /// OCR a clipboard image payload → stage → Quick Look. Returns false when
    /// no text is found.
    @MainActor
    func extractTextPreview(fromImageData data: Data, sourceName: String = "Clipboard image") async throws -> Bool {
        guard let image = cgImage(from: data) else { throw FileConversionError.unavailable("Could not decode image data") }
        let lines = try await VisionText.recognizeText(in: image)
        return try presentExtractedText(lines, sourceName: sourceName, suffix: "OCR", emit: { _ in })
    }

    /// Barcode/QR decode of a clipboard image payload → stage → Quick Look.
    @MainActor
    func decodeBarcodePreview(fromImageData data: Data, sourceName: String = "Clipboard image") async throws -> Bool {
        guard let image = cgImage(from: data) else { throw FileConversionError.unavailable("Could not decode image data") }
        let lines = try await VisionText.readBarcodes(in: image)
        return try presentExtractedText(lines, sourceName: sourceName, suffix: "Barcode", emit: { _ in })
    }

    /// Barcode/QR decode of an image file → stage → Quick Look (File Shelf).
    @MainActor
    func decodeBarcodePreview(at url: URL) async throws -> Bool {
        let lines = try await VisionText.readBarcodes(at: url)
        return try presentExtractedText(lines, sourceName: url.deletingPathExtension().lastPathComponent, suffix: "Barcode", emit: { _ in })
    }

    /// OCR of an image file → stage → Quick Look (File Shelf).
    @MainActor
    func extractTextPreview(at url: URL) async throws -> Bool {
        let lines = try await VisionText.recognizeText(at: url)
        return try presentExtractedText(lines, sourceName: url.deletingPathExtension().lastPathComponent, suffix: "OCR", emit: { _ in })
    }

    private func pickColor(emit: @escaping @MainActor @Sendable (CommandExecutionEvent) -> Void) async -> CommandOutcome {
        let color: NSColor? = await withCheckedContinuation { continuation in
            let sampler = UncheckedSampler(NSColorSampler())
            sampler.value.show { color in
                continuation.resume(returning: color)
                withExtendedLifetime(sampler) {}
            }
        }
        guard let color else { return .cancelled }
        let hex = Self.hexString(for: color)
        recordRecentColor(hex)
        let formats = Self.colorFormats(for: color)
        let recents = recentColors()
        if let chosen = chooseColorFormat(hex: hex, color: color, formats: formats, recents: recents) {
            pasteboard.clearContents()
            pasteboard.setString(chosen, forType: .string)
            emit(.feedback(.success("Copied \(chosen)")))
            return .copied(content: chosen)
        }
        pasteboard.clearContents()
        pasteboard.setString(hex, forType: .string)
        emit(.feedback(.success("Copied \(hex)")))
        return .copied(content: hex)
    }

    /// Format + recent-colors picker shown after the sampler. Returns the
    /// string to copy, or nil to fall back to hex.
    private func chooseColorFormat(hex: String, color: NSColor, formats: [(label: String, value: String)], recents: [String]) -> String? {
        let alert = NSAlert()
        alert.messageText = hex
        alert.informativeText = "Pick a format to copy.\n\(Self.contrastSummary(for: color))"
        alert.alertStyle = .informational
        let swatch = NSImageView(frame: NSRect(x: 0, y: 0, width: 40, height: 24))
        swatch.wantsLayer = true
        swatch.layer?.backgroundColor = color.cgColor
        swatch.layer?.cornerRadius = 5
        alert.accessoryView = swatch
        let formatPicker = NSPopUpButton(frame: NSRect(x: 48, y: 0, width: 190, height: 24), pullsDown: false)
        formatPicker.addItems(withTitles: formats.map(\.label))
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 238, height: 26))
        container.addSubview(swatch)
        container.addSubview(formatPicker)
        var chosenRecent: String?
        var retainedTarget: PopupTarget?
        defer { _ = retainedTarget }
        if recents.isEmpty == false {
            let recentPicker = NSPopUpButton(frame: NSRect(x: 0, y: 30, width: 238, height: 24), pullsDown: true)
            recentPicker.title = "Recent colors"
            for recent in recents { recentPicker.menu?.addItem(NSMenuItem(title: recent, action: nil, keyEquivalent: "")) }
            container.frame.size.height = 58
            swatch.frame.origin.y = 32
            formatPicker.frame.origin.y = 30
            container.addSubview(recentPicker)
            let target = PopupTarget { index in
                guard index > 0, index - 1 < recents.count else { return }
                chosenRecent = recents[index - 1]
            }
            recentPicker.target = target
            recentPicker.action = #selector(PopupTarget.changed(_:))
            retainedTarget = target
        }
        alert.accessoryView = container
        alert.addButton(withTitle: "Copy")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        if let chosenRecent { return chosenRecent }
        let index = formatPicker.indexOfSelectedItem
        guard formats.indices.contains(index) else { return nil }
        return formats[index].value
    }

    private static var colorTargetKey: UInt8 = 0

    private func recentColors() -> [String] {
        localState.get(\.colorPickerRecents)
    }

    private func recordRecentColor(_ hex: String) {
        localState.update { state in
            var recents = state.colorPickerRecents.filter { $0 != hex }
            recents.insert(hex, at: 0)
            state.colorPickerRecents = Array(recents.prefix(12))
        }
    }

    nonisolated static func colorFormats(for color: NSColor) -> [(label: String, value: String)] {
        guard let rgb = color.usingColorSpace(.sRGB) else {
            return [("Hex", "#000000")]
        }
        let r255 = Int((rgb.redComponent * 255).rounded())
        let g255 = Int((rgb.greenComponent * 255).rounded())
        let b255 = Int((rgb.blueComponent * 255).rounded())
        let alpha = rgb.alphaComponent
        let hex = String(format: "#%02X%02X%02X", r255, g255, b255)
        let rgbString = alpha < 1
            ? String(format: "rgba(%d, %d, %d, %.2f)", r255, g255, b255, alpha)
            : "rgb(\(r255), \(g255), \(b255))"
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0
        rgb.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: nil)
        let hueDegrees = Int((hue * 360).rounded()) % 360
        let hsl = hslString(hueDegrees: hueDegrees, saturation: saturation, brightness: brightness)
        let hsv = String(format: "hsv(%d, %.0f%%, %.0f%%)", hueDegrees, saturation * 100, brightness * 100)
        let oklch = oklchString(r: rgb.redComponent, g: rgb.greenComponent, b: rgb.blueComponent)
        return [
            ("Hex", hex),
            (alpha < 1 ? "RGBA" : "RGB", rgbString),
            ("HSL", hsl),
            ("HSV", hsv),
            ("OKLCH", oklch),
            ("NSColor", String(format: "NSColor(red: %.3f, green: %.3f, blue: %.3f, alpha: %.3f)", rgb.redComponent, rgb.greenComponent, rgb.blueComponent, alpha)),
        ]
    }

    /// WCAG 2.x contrast summary against white and black text, with the AA
    /// threshold (4.5:1 normal, 3:1 large) called out.
    nonisolated static func contrastSummary(for color: NSColor) -> String {
        guard let rgb = color.usingColorSpace(.sRGB) else { return "" }
        func luminance(_ c: NSColor) -> CGFloat {
            func channel(_ v: CGFloat) -> CGFloat { v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
            return 0.2126 * channel(c.redComponent) + 0.7152 * channel(c.greenComponent) + 0.0722 * channel(c.blueComponent)
        }
        func ratio(_ a: CGFloat, _ b: CGFloat) -> CGFloat { (max(a, b) + 0.05) / (min(a, b) + 0.05) }
        let l = luminance(rgb)
        let onWhite = ratio(l, luminance(.white))
        let onBlack = ratio(l, luminance(.black))
        func verdict(_ r: CGFloat) -> String { r >= 4.5 ? "AA" : (r >= 3 ? "AA large" : "fails") }
        return String(format: "On white %.1f:1 (%@) · on black %.1f:1 (%@)", onWhite, verdict(onWhite) as NSString, onBlack, verdict(onBlack) as NSString)
    }

    nonisolated private static func hslString(hueDegrees: Int, saturation: CGFloat, brightness: CGFloat) -> String {
        let l = brightness * (1 - saturation / 2)
        let s = (l == 0 || l == 1) ? 0 : (brightness - l) / min(l, 1 - l)
        return String(format: "hsl(%d, %.0f%%, %.0f%%)", hueDegrees, s * 100, l * 100)
    }

    nonisolated private static func oklchString(r: CGFloat, g: CGFloat, b: CGFloat) -> String {
        // sRGB → LMS via the OKLab M1 matrix, then polar lightness/chroma/hue.
        func cbrt(_ x: CGFloat) -> CGFloat { x < 0 ? -pow(-x, 1.0 / 3.0) : pow(x, 1.0 / 3.0) }
        func linear(_ c: CGFloat) -> CGFloat { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        let rl = linear(r), gl = linear(g), bl = linear(b)
        let l = cbrt(0.4122214708 * rl + 0.5363325363 * gl + 0.0514459929 * bl)
        let m = cbrt(0.2119034982 * rl + 0.6806995451 * gl + 0.1073969566 * bl)
        let s = cbrt(0.0883024619 * rl + 0.2817188376 * gl + 0.6299787005 * bl)
        let L = 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s
        let a = 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s
        let bb = 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s
        let C = sqrt(a * a + bb * bb)
        var h = atan2(bb, a) * 180 / .pi
        if h < 0 { h += 360 }
        return String(format: "oklch(%.3f %.3f %.1f)", L, C, h)
    }

    private func generateQRCode(emit: @escaping @MainActor @Sendable (CommandExecutionEvent) -> Void) -> CommandOutcome {
        guard let content = pasteboard.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines), content.isEmpty == false else {
            return .failure(message: "Clipboard has no text to encode", retryable: false)
        }
        guard let image = qrImage(for: content) else {
            return .failure(message: "Could not generate QR code", retryable: false)
        }
        pasteboard.clearContents()
        pasteboard.writeObjects([image])
        diagnostics.log("Generated QR code for \(content.count) characters")
        offerQRSave(image, content)
        emit(.feedback(.success("QR code copied to clipboard")))
        return .copied(content: content)
    }

    /// "Copied — save a PNG?" offer after QR generation. Injectable: modal
    /// UI must never run under tests.
    static func presentQRSaveOffer(_ image: NSImage, content: String) {
        let alert = NSAlert()
        alert.messageText = "QR code copied to clipboard"
        alert.informativeText = content.count > 120 ? String(content.prefix(120)) + "…" : content
        alert.addButton(withTitle: "Save as PNG…")
        alert.addButton(withTitle: "Done")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.png]
            panel.nameFieldStringValue = "QR Code.png"
            panel.canCreateDirectories = true
            if panel.runModal() == .OK, let destination = panel.url,
               let tiff = image.tiffRepresentation,
               let bitmap = NSBitmapImageRep(data: tiff),
               let png = bitmap.representation(using: .png, properties: [:]) {
                do {
                    try png.write(to: destination)
                } catch {
                    let failure = NSAlert()
                    failure.messageText = "Couldn't save the QR code"
                    failure.informativeText = error.localizedDescription
                    failure.alertStyle = .warning
                    failure.runModal()
                }
            }
        }
    }

    private func qrImage(for content: String) -> NSImage? {
        guard let data = content.data(using: .utf8),
              let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 12, y: 12))
        guard let cgImage = Self.qrContext.createCGImage(scaled, from: scaled.extent) else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: scaled.extent.width, height: scaled.extent.height))
    }

    private func generateWiFiQRCode(emit: @escaping @MainActor @Sendable (CommandExecutionEvent) -> Void) -> CommandOutcome {
        let alert = NSAlert()
        alert.messageText = "Wi-Fi QR Code"
        alert.informativeText = "Guests scan the code to join the network."
        let ssid = NSTextField(frame: NSRect(x: 0, y: 60, width: 260, height: 24))
        ssid.placeholderString = "Network name (SSID)"
        let password = NSSecureTextField(frame: NSRect(x: 0, y: 32, width: 260, height: 24))
        password.placeholderString = "Password"
        let security = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 260, height: 24), pullsDown: false)
        security.addItems(withTitles: ["WPA / WPA2 / WPA3", "WEP", "Open network"])
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 260, height: 88))
        container.addSubview(ssid)
        container.addSubview(password)
        container.addSubview(security)
        alert.accessoryView = container
        alert.addButton(withTitle: "Generate")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return .cancelled }
        let network = ssid.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard network.isEmpty == false else {
            return .failure(message: "Enter a network name", retryable: true)
        }
        let payload = Self.wifiQRPayload(ssid: network, password: password.stringValue, security: security.indexOfSelectedItem)
        guard let image = qrImage(for: payload) else {
            return .failure(message: "Could not generate QR code", retryable: false)
        }
        pasteboard.clearContents()
        pasteboard.writeObjects([image])
        emit(.feedback(.success("Wi-Fi QR code copied to clipboard")))
        return .copied(content: payload)
    }

    nonisolated static func wifiQRPayload(ssid: String, password: String, security: Int) -> String {
        func escaped(_ value: String) -> String {
            var result = ""
            for character in value {
                if "\\;,:\"".contains(character) { result.append("\\") }
                result.append(character)
            }
            return result
        }
        switch security {
        case 2:
            return "WIFI:T:nopass;S:\(escaped(ssid));;"
        default:
            let type = security == 1 ? "WEP" : "WPA"
            return "WIFI:T:\(type);S:\(escaped(ssid));P:\(escaped(password));;"
        }
    }

    private func recognizeScreenText(emit: @escaping @MainActor @Sendable (CommandExecutionEvent) -> Void) async -> CommandOutcome {
        emit(.status("Select a region…"))
        let temporary = FileManager.default.temporaryDirectory
            .appendingPathComponent("foundry-screen-ocr-\(UUID().uuidString).png")
        do {
            _ = try await ProcessRunner.run(path: "/usr/sbin/screencapture", arguments: ["-i", "-x", temporary.path], timeout: 120)
        } catch {
            return .failure(message: "Could not capture the screen", retryable: true)
        }
        defer { try? FileManager.default.removeItem(at: temporary) }
        guard FileManager.default.fileExists(atPath: temporary.path) else { return .cancelled }
        do {
            emit(.status("Recognizing text…"))
            let lines = try await VisionText.recognizeText(at: temporary)
            let text = lines.joined(separator: "\n")
            guard text.isEmpty == false else {
                return .failure(message: "No text found in the captured region", retryable: false)
            }
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
            diagnostics.log("Screen OCR captured \(lines.count) line(s)")
            emit(.feedback(.success("Copied \(lines.count) line(s) of text")))
            return .copied(content: text)
        } catch {
            diagnostics.log("Screen OCR failed: \(error.localizedDescription)")
            return .failure(message: "Could not extract text", retryable: true)
        }
    }

    private func emptyTrash(emit: @escaping @MainActor @Sendable (CommandExecutionEvent) -> Void) async -> CommandOutcome {
        let alert = NSAlert()
        alert.messageText = "Empty the Trash?"
        alert.informativeText = "Items in the Trash are permanently deleted. This cannot be undone."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Empty Trash")
        alert.addButton(withTitle: "Cancel")
        alert.buttons.first?.hasDestructiveAction = true
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return .cancelled }
        do {
            let result = try await ProcessRunner.run(
                path: "/usr/bin/osascript",
                arguments: ["-e", "tell application \"Finder\" to empty trash"],
                timeout: 60
            )
            guard result.succeeded else {
                return .failure(message: "Finder could not empty the Trash", retryable: true)
            }
            diagnostics.log("Emptied trash")
            emit(.feedback(.success("Trash emptied")))
            return .success(message: "Trash emptied")
        } catch {
            diagnostics.log("Empty Trash failed: \(error.localizedDescription)")
            return .failure(message: "Could not empty the Trash", retryable: true)
        }
    }

    private func toggleDesktopIcons(emit: @escaping @MainActor @Sendable (CommandExecutionEvent) -> Void) async -> CommandOutcome {
        let current = await BestEffort.attempt("read Finder CreateDesktop") {
            try await ProcessRunner.run(
                path: "/usr/bin/defaults",
                arguments: ["read", "com.apple.finder", "CreateDesktop"],
                timeout: 5
            )
        }
        let currentlyShown = current?.stdout.trimmingCharacters(in: .whitespacesAndNewlines) != "0"
        let next = currentlyShown ? "0" : "1"
        do {
            _ = try await ProcessRunner.run(
                path: "/usr/bin/defaults",
                arguments: ["write", "com.apple.finder", "CreateDesktop", "-bool", next == "1" ? "true" : "false"],
                timeout: 5
            )
            _ = try await ProcessRunner.run(path: "/usr/bin/killall", arguments: ["Finder"], timeout: 5)
            let message = currentlyShown ? "Desktop icons hidden" : "Desktop icons shown"
            diagnostics.log(message)
            emit(.feedback(.success(message)))
            return .success(message: message)
        } catch {
            diagnostics.log("Desktop icon toggle failed: \(error.localizedDescription)")
            return .failure(message: "Could not toggle desktop icons", retryable: true)
        }
    }

    private func readQRCode(emit: @escaping @MainActor @Sendable (CommandExecutionEvent) -> Void) async -> CommandOutcome {
        guard let url = pickImageFile(title: "Read QR Code") else { return .cancelled }
        do {
            emit(.status("Scanning image…"))
            let payloads = try await VisionText.readBarcodes(at: url)
            guard let payload = payloads.first else {
                return .failure(message: "No QR code found in \(url.lastPathComponent)", retryable: false)
            }
            pasteboard.clearContents()
            pasteboard.setString(payload, forType: .string)
            diagnostics.log("Decoded QR payload: \(payload)")
            emit(.feedback(.success("Copied \(payload)")))
            return .copied(content: payload)
        } catch {
            diagnostics.log("QR decode failed: \(error.localizedDescription)")
            return .failure(message: "Could not read QR code", retryable: true)
        }
    }

    private static let qrContext = CIContext()

    nonisolated private static func hexString(for color: NSColor) -> String {
        guard let rgb = color.usingColorSpace(.sRGB) else { return "#000000" }
        let r = Int((rgb.redComponent * 255).rounded())
        let g = Int((rgb.greenComponent * 255).rounded())
        let b = Int((rgb.blueComponent * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
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

extension ActionRunner {
    // MARK: - File actions

    private func compressFile(path: String, emit: @escaping @MainActor @Sendable (CommandExecutionEvent) -> Void) async -> CommandOutcome {
        let source = URL(fileURLWithPath: path)
        let destination = Self.uniqueArchiveDestination(for: source)
        do {
            _ = try await ProcessRunner.run(path: "/usr/bin/ditto", arguments: ["-c", "-k", "--keepParent", source.path, destination.path])
            diagnostics.log("Compressed \(source.lastPathComponent) → \(destination.lastPathComponent)")
            emit(.feedback(.success("Created \u{201C}\(destination.lastPathComponent)\u{201D}")))
            return .fileResults([destination])
        } catch is CancellationError {
            try? FileManager.default.removeItem(at: destination)
            return .cancelled
        } catch {
            try? FileManager.default.removeItem(at: destination)
            diagnostics.log("Compress failed for \(path): \(error.localizedDescription)")
            return .failure(message: "Could not compress \u{201C}\(source.lastPathComponent)\u{201D}", retryable: true)
        }
    }

    /// Present the share picker for a file URL — used by conversion results
    /// and any surface that already holds a URL (no command-result plumbing).
    @MainActor
    func shareFile(at url: URL) {
        _ = shareFile(path: url.path)
    }

    private func shareFile(path: String) -> CommandOutcome {
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: path) else {
            return .failure(message: "The file no longer exists", retryable: false)
        }
        // Anchor to the Foundry panel (or any app window) — the share picker
        // needs a live view to present from.
        guard let anchor = (NSApp.windows.first { $0 is FoundryPanel } ?? NSApp.keyWindow)?.contentView else {
            return .failure(message: "Could not open the share menu", retryable: false)
        }
        let picker = NSSharingServicePicker(items: [url])
        let rect = NSRect(x: anchor.bounds.midX, y: anchor.bounds.maxY - 40, width: 1, height: 1)
        picker.show(relativeTo: rect, of: anchor, preferredEdge: .minY)
        return .stayOpen(message: nil)
    }

    private func renameFile(path: String, emit: @escaping @MainActor @Sendable (CommandExecutionEvent) -> Void) async -> CommandOutcome {
        let source = URL(fileURLWithPath: path)
        let icon = await Task.detached(priority: .utility) {
            NSWorkspace.shared.icon(forFile: path)
        }.value
        let alert = NSAlert()
        alert.messageText = "Rename \u{201C}\(source.lastPathComponent)\u{201D}"
        alert.informativeText = "Enter a new name. The file stays in the same folder."
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")
        alert.icon = icon
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        field.stringValue = source.lastPathComponent
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return .cancelled }
        let newName = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard newName.isEmpty == false, newName != source.lastPathComponent else { return .cancelled }
        guard newName.contains("/") == false, newName.contains(":") == false else {
            emit(.feedback(.failure("Names can\u{2019}t contain / or :")))
            return .failure(message: "Invalid name", retryable: true)
        }
        let destination = source.deletingLastPathComponent().appendingPathComponent(newName)
        guard FileManager.default.fileExists(atPath: destination.path) == false else {
            emit(.feedback(.failure("\u{201C}\(newName)\u{201D} already exists")))
            return .failure(message: "A file with that name already exists", retryable: true)
        }
        do {
            try FileManager.default.moveItem(at: source, to: destination)
            diagnostics.log("Renamed \(source.lastPathComponent) → \(newName)")
            return .refreshResults(message: "Renamed to \u{201C}\(newName)\u{201D}")
        } catch {
            diagnostics.log("Rename failed for \(path): \(error.localizedDescription)")
            return .failure(message: "Could not rename file", retryable: true)
        }
    }

    private static func uniqueArchiveDestination(for source: URL) -> URL {
        let folder = source.deletingLastPathComponent()
        let base = source.lastPathComponent
        var candidate = folder.appendingPathComponent("\(base).zip")
        var counter = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = folder.appendingPathComponent("\(base) \(counter).zip")
            counter += 1
        }
        return candidate
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

private final class UncheckedSampler: @unchecked Sendable {
    let value: NSColorSampler
    init(_ value: NSColorSampler) { self.value = value }
}

private struct RaycastSnippetImport: Decodable {
    let name: String
    let text: String
    let keyword: String?
}

private struct RaycastSnippetExport: Encodable {
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

private final class PopupTarget: NSObject {
    private let handler: (Int) -> Void
    init(_ handler: @escaping (Int) -> Void) { self.handler = handler }
    @objc @MainActor func changed(_ sender: NSPopUpButton) { handler(sender.indexOfSelectedItem) }
}
