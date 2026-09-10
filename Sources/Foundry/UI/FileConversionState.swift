import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers
import FoundryServices

@MainActor
final class FileConversionState: ObservableObject {
    @Published var sourceURLs: [URL] = []
    @Published var outputFolderURL: URL?
    @Published var availableTargets: [FileConversionTarget] = []
    @Published var selectedTargetID: String?
    @Published var status = ""
    @Published var isConverting = false
    @Published var outputURLs: [URL] = []
    @Published var outputURL: URL?
    @Published var dependencySetup: DependencySetup? = nil
    @Published private(set) var phase: OperationPhase = .assessing
    @Published private(set) var progress: OperationProgress?
    @Published private(set) var failure: OperationFailure?
    @Published private(set) var itemOutcomes: [FileConversionItemOutcome] = []
    @Published private(set) var capabilities: [String: FileConversionCapability] = [:]

    private var conversionTask: Task<Void, Never>?
    private let assess: @Sendable (FileConversionTarget) async -> CapabilityState
    private let provision: @Sendable (SetupPlan, String) async throws -> Void
    private let convertOperation: @Sendable (URL, FileConversionTarget, URL) async -> Result<URL, Error>
    private let operations: OperationCoordinator
    private var operationID: UUID?
    private var conversionGeneration = UUID()
    private var lastRequest: (sources: [URL], target: FileConversionTarget, folder: URL)?

    var currentOperationSnapshot: OperationSnapshot? {
        guard let operationID else { return nil }
        return operations.snapshot(id: operationID)
    }

    init(
        assess: @escaping @Sendable (FileConversionTarget) async -> CapabilityState = { await FileConversionService.assess($0) },
        provision: @escaping @Sendable (SetupPlan, String) async throws -> Void = { plan, fingerprint in
            let executor = ClosureProvisioningExecutor { command in
                _ = try await ProcessRunner.run(path: command.executable, arguments: command.arguments)
            }
            _ = try await DependencyProvisioner(executor: executor).provision(plan: plan, approvedFingerprint: fingerprint)
        },
        convert: @escaping @Sendable (URL, FileConversionTarget, URL) async -> Result<URL, Error> = { source, target, folder in
            await FileConversionService.convert(sourceURL: source, target: target, outputFolderURL: folder)
        },
        operations: OperationCoordinator = OperationCoordinator()
    ) {
        self.assess = assess; self.provision = provision; self.convertOperation = convert; self.operations = operations
    }

    var selectedTarget: FileConversionTarget? {
        availableTargets.first { $0.id == selectedTargetID } ?? availableTargets.first
    }

    var sourceURL: URL? {
        sourceURLs.first
    }

    func reset() {
        if let operationID {
            _ = operations.update(id: operationID, phase: .cancelled, progress: progress, failure: OperationFailure(message: "Conversion cancelled", retryable: true))
        }
        conversionGeneration = UUID()
        sourceURLs = []
        outputFolderURL = nil
        availableTargets = []
        selectedTargetID = nil
        status = ""
        isConverting = false
        outputURLs = []
        outputURL = nil
        dependencySetup = nil
        capabilities = [:]
        phase = .assessing; progress = nil; failure = nil; itemOutcomes = []; operationID = nil; lastRequest = nil
        conversionTask?.cancel()
        conversionTask = nil
    }

    func chooseSourceFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            setSource(url: url)
        }
    }

    func chooseOutputFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = outputFolderURL ?? sourceURL?.deletingLastPathComponent()
        if panel.runModal() == .OK, let url = panel.url {
            outputFolderURL = url
        }
    }

    func setSource(url: URL) {
        setSources(urls: [url])
    }

    func setSources(urls: [URL]) {
        var seen = Set<URL>()
        sourceURLs = urls.filter { $0.isFileURL && seen.insert($0).inserted }
        if outputFolderURL == nil {
            outputFolderURL = sourceURLs.first.map { $0.deletingLastPathComponent() }
        }
        availableTargets = commonTargets(for: sourceURLs)
        selectedTargetID = sourceURLs.first
            .flatMap { FileConversionService.defaultTargetID(for: $0, in: availableTargets) }
        outputURLs = []
        outputURL = nil
        capabilities = [:]
        if sourceURLs.isEmpty {
            status = ""
        } else if availableTargets.isEmpty {
            status = sourceURLs.count == 1
                ? "No local converter available for this file yet"
                : "No common conversion format for these files"
        } else {
            status = ""
        }
        Task { await refreshCapabilities() }
    }

    func convert() {
        guard sourceURLs.isEmpty == false, let target = selectedTarget else { return }
        guard let capability = capabilities[target.id] else { status = "Checking converter readiness…"; return }
        switch capability.state {
        case .ready: break
        case .setupRequired(let plan): dependencySetup = DependencySetup(target: target, plan: plan); return
        case .unavailable(let reason), .degraded(let reason): status = "\(target.title) unavailable: \(reason)"; return
        }
        startConversion(sourceURLs: sourceURLs, target: target)
    }

    func cancelDependencySetup() { dependencySetup = nil }

    func installToolAndConvert() async {
        guard let setup = dependencySetup, isCurrentSetup(setup) else { return }
        let id = beginProvisioning()
        let generation = conversionGeneration
        let sources = sourceURLs
        let folder = outputFolderURL
        dependencySetup = nil
        do {
            try await provision(setup.plan, setup.plan.fingerprint)
            guard Task.isCancelled == false,
                  conversionGeneration == generation,
                  sourceURLs == sources,
                  sources.isEmpty == false else { return }
            guard case .ready = await assess(setup.target) else { throw FileConversionError.unavailable("The installed converter is not ready yet") }
            guard Task.isCancelled == false,
                  conversionGeneration == generation,
                  sourceURLs == sources else { return }
            startConversion(sourceURLs: sources, target: setup.target, operationID: id, requestedOutputFolder: folder)
        } catch is CancellationError {
            guard conversionGeneration == generation else { return }
            phase = .cancelled; status = "Tool installation cancelled"
            operations.update(id: id, phase: .cancelled, progress: progress, failure: OperationFailure(message: "Tool installation cancelled", retryable: true))
        } catch {
            guard conversionGeneration == generation else { return }
            failProvisioning(operationID: id, error: error)
        }
    }

    func installTool() async {
        guard let setup = dependencySetup, isCurrentSetup(setup) else { return }
        let id = beginProvisioning()
        dependencySetup = nil
        do {
            try await provision(setup.plan, setup.plan.fingerprint)
            await refreshCapabilities()
            phase = .completed; progress = .items(completed: 1, total: 1); status = "Tool installed"
            operations.update(id: id, phase: .completed, progress: progress)
        } catch is CancellationError {
            phase = .cancelled; status = "Tool installation cancelled"
            operations.update(id: id, phase: .cancelled, progress: progress, failure: OperationFailure(message: "Tool installation cancelled", retryable: true))
        } catch { failProvisioning(operationID: id, error: error) }
    }

    func refreshCapabilities() async {
        var refreshed: [String: FileConversionCapability] = [:]
        for target in availableTargets { refreshed[target.id] = FileConversionCapability(state: await assess(target)) }
        capabilities = refreshed
    }

    func capability(for target: FileConversionTarget) -> FileConversionCapability? { capabilities[target.id] }

    func cancel() {
        conversionGeneration = UUID()
        conversionTask?.cancel()
        conversionTask = nil
        isConverting = false
        status = "Conversion cancelled"
        phase = .cancelled
        cancelRemaining(sourceURLs, operationID: operationID)
    }

    private func startConversion(sourceURLs: [URL], target: FileConversionTarget, operationID existingID: UUID? = nil, preservingCompleted: [FileConversionItemOutcome] = [], requestedOutputFolder: URL? = nil) {
        guard sourceURLs.isEmpty == false else { return }
        let outputFolderURL = requestedOutputFolder ?? self.outputFolderURL ?? sourceURLs[0].deletingLastPathComponent()
        let total = sourceURLs.count
        lastRequest = (sourceURLs, target, outputFolderURL)
        if existingID == nil {
            let completed = Dictionary(uniqueKeysWithValues: preservingCompleted.map { ($0.sourceURL, $0) })
            itemOutcomes = sourceURLs.map { completed[$0] ?? FileConversionItemOutcome(sourceURL: $0, state: .pending, outputURL: nil, failure: nil) }
        } else {
            for sourceURL in sourceURLs { setOutcome(sourceURL, state: .pending, outputURL: nil, failure: nil) }
        }
        failure = nil
        let operationID = existingID ?? operations.start(retryDescriptor: RetryDescriptor(maxAttempts: 3))
        self.operationID = operationID
        let generation = UUID()
        conversionGeneration = generation
        phase = .processing
        let completedBeforeStart = itemOutcomes.filter { $0.state == .completed }.count
        progress = .items(completed: completedBeforeStart, total: total)
        operations.update(id: operationID, phase: .processing, progress: progress)
        conversionTask?.cancel()
        isConverting = true
        outputURLs = itemOutcomes.compactMap(\.outputURL)
        outputURL = outputURLs.last
        status = total == 1
            ? (FileConversionService.preflightStatus(for: target) ?? "Converting to \(target.title)…")
            : "Preparing \(total) files..."

        conversionTask = Task { [weak self] in
            let workSources = sourceURLs.filter { url in
                self?.itemOutcomes.first(where: { $0.sourceURL == url })?.state != .completed
            }

            for (index, sourceURL) in workSources.enumerated() {
                guard Task.isCancelled == false else { await MainActor.run { self?.cancelRemaining(sourceURLs, generation: generation, operationID: operationID) }; return }
                await MainActor.run { self?.setOutcome(sourceURL, state: .processing, outputURL: nil, failure: nil) }
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    let prefix = total == 1 ? "" : "\(index + 1) of \(total): "
                    self.status = prefix + (FileConversionService.preflightStatus(for: target) ?? "Converting to \(target.title)…")
                }

                let result = await self?.convertOperation(sourceURL, target, outputFolderURL) ?? .failure(FileConversionError.cancelled)
                guard Task.isCancelled == false else { await MainActor.run { self?.cancelRemaining(sourceURLs, generation: generation, operationID: operationID) }; return }
                switch result {
                case let .success(outputURL):
                    await MainActor.run { self?.setOutcome(sourceURL, state: .completed, outputURL: outputURL, failure: nil) }
                case let .failure(error):
                    if error is CancellationError || self?.isCancellation(error) == true {
                        await MainActor.run { self?.cancelRemaining(sourceURLs, generation: generation, operationID: operationID) }
                        return
                    }
                    await MainActor.run { self?.setOutcome(sourceURL, state: .failed, outputURL: nil, failure: OperationFailure(message: error.localizedDescription, retryable: true)) }
                }
                await MainActor.run { [weak self] in
                    let completed = completedBeforeStart + index + 1
                    self?.progress = .items(completed: completed, total: total)
                    if let operationID = self?.operationID { self?.operations.updateProgress(id: operationID, progress: .items(completed: completed, total: total)) }
                }
            }

            await MainActor.run {
                guard let self else { return }
                guard self.conversionGeneration == generation, self.operationID == operationID, self.isConverting else { return }
                let outputs = self.itemOutcomes.compactMap(\.outputURL)
                let failures = self.itemOutcomes.compactMap { outcome -> String? in
                    guard outcome.state == .failed else { return nil }
                    return total == 1 ? outcome.failure?.message : "\(outcome.sourceURL.lastPathComponent): \(outcome.failure?.message ?? "Conversion failed")"
                }
                self.isConverting = false
                self.outputURLs = outputs
                self.outputURL = outputs.last
                self.phase = failures.isEmpty ? .completed : .failed
                self.failure = failures.isEmpty ? nil : OperationFailure(message: failures.joined(separator: "\n"), retryable: true)
                if let operationID = self.operationID {
                    if failures.isEmpty {
                        _ = self.operations.update(id: operationID, phase: .completed, progress: self.progress)
                    } else {
                        _ = self.operations.update(id: operationID, phase: .failed, progress: self.progress, failure: self.failure)
                    }
                }
                if failures.isEmpty {
                    self.status = outputs.count == 1
                        ? "Created \(outputs[0].lastPathComponent)"
                        : "Created \(outputs.count) files"
                } else if outputs.isEmpty {
                    self.status = failures.joined(separator: "\n")
                } else {
                    self.status = "Created \(outputs.count) of \(total) files; \(failures.count) failed"
                }
            }
        }
    }

    func retryFailed() {
        guard let request = lastRequest else { return }
        let failed = itemOutcomes.filter { $0.state == .failed || $0.state == .cancelled }.map(\.sourceURL)
        guard failed.isEmpty == false else { return }
        Task { [weak self] in
            guard let self else { return }
            switch await self.assess(request.target) {
            case .ready:
                break
            case let .setupRequired(plan):
                self.dependencySetup = DependencySetup(target: request.target, plan: plan)
                self.status = "Converter readiness changed; setup is required before retrying"
                return
            case let .unavailable(reason), let .degraded(reason):
                self.status = "Converter unavailable: \(reason)"
                return
            }
            let completed = self.itemOutcomes.filter { $0.state == .completed }
            self.startConversion(sourceURLs: request.sources, target: request.target, preservingCompleted: completed)
        }
    }

    private func setOutcome(_ sourceURL: URL, state: FileConversionItemState, outputURL: URL?, failure: OperationFailure?) {
        guard let index = itemOutcomes.firstIndex(where: { $0.sourceURL == sourceURL }) else { return }
        itemOutcomes[index] = FileConversionItemOutcome(sourceURL: sourceURL, state: state, outputURL: outputURL, failure: failure)
    }

    private func isCancellation(_ error: Error) -> Bool {
        guard let conversionError = error as? FileConversionError else { return false }
        if case .cancelled = conversionError { return true }
        return false
    }

    private func cancelRemaining(_ urls: [URL], generation: UUID? = nil, operationID: UUID? = nil) {
        if let generation, self.conversionGeneration != generation { return }
        if let operationID, self.operationID != operationID { return }
        for url in urls where itemOutcomes.first(where: { $0.sourceURL == url })?.state != .completed {
            setOutcome(url, state: .cancelled, outputURL: nil, failure: OperationFailure(message: "Cancelled", retryable: true))
        }
        let completed = itemOutcomes.filter { $0.state == .completed }.count
        outputURLs = itemOutcomes.compactMap(\.outputURL)
        outputURL = outputURLs.last
        progress = .items(completed: completed, total: itemOutcomes.count)
        status = "Conversion cancelled after creating \(completed) of \(itemOutcomes.count) files"
        phase = .cancelled; isConverting = false
        if let operationID { operations.update(id: operationID, phase: .cancelled, progress: progress, failure: OperationFailure(message: "Conversion cancelled", retryable: true)) }
    }

    private func isCurrentSetup(_ setup: DependencySetup) -> Bool {
        guard let target = selectedTarget, target.id == setup.target.id,
              case let .setupRequired(plan) = capabilities[target.id]?.state else { return false }
        return plan.fingerprint == setup.plan.fingerprint
    }

    private func beginProvisioning() -> UUID {
        let id = operations.start(retryDescriptor: RetryDescriptor(maxAttempts: 3))
        operationID = id; phase = .provisioning; progress = .items(completed: 0, total: 1)
        operations.update(id: id, phase: .provisioning, progress: progress)
        return id
    }

    private func failProvisioning(operationID: UUID, error: Error) {
        let typed = OperationFailure(message: error.localizedDescription, retryable: true)
        failure = typed; phase = .failed; status = "Tool installation failed: \(typed.message)"
        operations.update(id: operationID, phase: .failed, progress: progress, failure: typed)
    }

    func revealOutput() {
        guard outputURLs.isEmpty == false else { return }
        NSWorkspace.shared.activateFileViewerSelecting(outputURLs)
    }

    private func commonTargets(for urls: [URL]) -> [FileConversionTarget] {
        guard let firstURL = urls.first else { return [] }
        let firstTargets = FileConversionService.availableTargets(for: firstURL)
        guard urls.count > 1 else { return firstTargets }

        let remainingTargets = urls.dropFirst().map { FileConversionService.availableTargets(for: $0) }
        return firstTargets.filter { target in
            remainingTargets.allSatisfy { targets in
                targets.contains { $0.id == target.id && $0.family == target.family }
            }
        }
    }
}

struct FileConversionTarget: Identifiable, Hashable {
    enum Category: String, Hashable, CaseIterable {
        case photo = "Photo"
        case icon = "Icon"
        case document = "Document"
        case pdf = "PDF"
        case music = "Music"
        case video = "Video"
    }

    enum Family: Hashable {
        case image
        case text
        case mediaFFmpeg
        case imageMagick
        case pandoc
        case soffice
    }

    let id: String
    let title: String
    let outputExtension: String
    let category: Category
    let family: Family
}

enum FileConversionError: Error { case unavailable(String), cancelled }
enum FileConversionItemState: Equatable { case pending, processing, completed, failed, cancelled }
struct FileConversionItemOutcome: Identifiable, Equatable {
    let sourceURL: URL
    let state: FileConversionItemState
    let outputURL: URL?
    let failure: OperationFailure?
    var id: URL { sourceURL }
}
struct DependencySetup: Identifiable { let target: FileConversionTarget; let plan: SetupPlan; var id: String { plan.fingerprint } }
struct FileConversionCapability {
    let state: CapabilityState
    var isSetupRequired: Bool { if case .setupRequired = state { return true }; return false }
    var readinessLabel: String { switch state { case .ready: return "Ready"; case .setupRequired: return "Setup required"; case .unavailable: return "Unavailable"; case .degraded: return "Degraded" } }
}
private struct ClosureProvisioningExecutor: ProvisioningExecutor {
    let body: @Sendable (ExactCommand) async throws -> Void
    func execute(_ command: ExactCommand) async throws { try await body(command) }
}

enum FileConversionService {
    static func assess(_ target: FileConversionTarget) async -> CapabilityState {
        await assess(target, locator: ExecutableLocator(), environment: ProcessInfo.processInfo.environment)
    }

    static func assess(_ target: FileConversionTarget, locator: ExecutableLocator, environment: [String: String]) async -> CapabilityState {
        let requirement: CapabilityRequirement?
        switch target.family {
        case .mediaFFmpeg: requirement = try? CapabilityRequirement(executableName: "ffmpeg", explicitPaths: ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg"])
        case .imageMagick: requirement = try? CapabilityRequirement(executableName: "magick", explicitPaths: ["/opt/homebrew/bin/magick", "/usr/local/bin/magick"])
        case .pandoc: requirement = try? CapabilityRequirement(executableName: "pandoc", explicitPaths: ["/opt/homebrew/bin/pandoc", "/usr/local/bin/pandoc"])
        case .soffice: requirement = try? CapabilityRequirement(executableName: "soffice", explicitPaths: ["/Applications/LibreOffice.app/Contents/MacOS/soffice", "/opt/homebrew/bin/soffice", "/usr/local/bin/soffice"])
        default: return .ready
        }
        guard let requirement else { return .unavailable("Missing dependency: \(missingDependencyName(for: target) ?? "converter")") }
        let assessment = (try? await CapabilityAssessor(locator: locator, versionProbe: VersionProbe(), environment: environment).assess(requirement)) ?? .unavailable("Capability assessment failed")
        guard case .setupRequired = assessment else { return assessment }
        guard let brew = (try? locator.locate(name: "brew", candidates: ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"], environment: environment)) ?? nil else {
            return .unavailable("Homebrew is required to install \(missingDependencyName(for: target) ?? "the converter")")
        }
        guard let plan = setupPlan(for: target, homebrewPath: brew.path) else {
            return .unavailable("No setup plan exists for \(missingDependencyName(for: target) ?? "the converter")")
        }
        return .setupRequired(plan)
    }

    private static func setupPlan(for target: FileConversionTarget, homebrewPath: String) -> SetupPlan? {
        let command: ExactCommand
        switch target.family {
        case .mediaFFmpeg: command = ExactCommand(executable: homebrewPath, arguments: ["install", "ffmpeg"])
        case .imageMagick: command = ExactCommand(executable: homebrewPath, arguments: ["install", "imagemagick"])
        case .pandoc: command = ExactCommand(executable: homebrewPath, arguments: ["install", "pandoc"])
        case .soffice: command = ExactCommand(executable: homebrewPath, arguments: ["install", "--cask", "libreoffice"])
        default: return nil
        }
        return SetupPlan(commands: [command], artifacts: [], mutationScope: "Homebrew installs the required tool for this user", cleanupOwnership: "Homebrew owns the installed package", disclosure: "Network access to Homebrew is required; disk impact varies by package.")
    }
    static func missingDependencyName(for target: FileConversionTarget) -> String? {
        switch target.family {
        case .mediaFFmpeg: return "ffmpeg"
        case .imageMagick: return "magick"
        case .pandoc: return "pandoc"
        case .soffice: return "soffice"
        default: return nil
        }
    }

    static func availableTargets(for url: URL) -> [FileConversionTarget] {
        let ext = url.pathExtension.lowercased()
        var targets: [FileConversionTarget] = []
        let imageMetadata = imageMetadata(for: url)

        if imageExtensions.contains(ext) {
            targets.append(contentsOf: [
                target("png", category: .photo, family: .image),
                target("jpg", title: "JPEG", category: .photo, family: .image),
                target("heic", title: "HEIC", category: .photo, family: .image),
                target("tiff", title: "TIFF", category: .photo, family: .image),
                target("gif", title: "GIF", category: .photo, family: .image),
                target("bmp", title: "BMP", category: .photo, family: .image)
            ].filter { $0.outputExtension != ext })
            targets.append(contentsOf: [
                target("webp", title: "WEBP", category: .photo, family: .imageMagick),
                target("avif", title: "AVIF", category: .photo, family: .imageMagick),
                target("jp2", title: "JPEG 2000", category: .photo, family: .imageMagick),
            ].filter { $0.outputExtension != ext })
            if imageMetadata?.isIconCandidate == true {
                targets.append(contentsOf: [
                    target("ico", title: "ICO", category: .icon, family: .imageMagick),
                    target("icns", title: "ICNS", category: .icon, family: .imageMagick)
                ])
            }
        }

        if textDocumentExtensions.contains(ext) {
            targets.append(contentsOf: [
                target("txt", title: "Plain Text", category: .document, family: .text),
                target("rtf", title: "Rich Text", category: .document, family: .text),
                target("html", title: "HTML", category: .document, family: .text),
                target("doc", title: "Word .doc", category: .document, family: .text),
                target("docx", title: "Word .docx", category: .document, family: .text),
                target("odt", title: "OpenDocument", category: .document, family: .text),
                target("wordml", title: "Word XML", category: .document, family: .text)
            ].filter { $0.outputExtension != ext })
            targets.append(contentsOf: [
                target("md", title: "Markdown", category: .document, family: .pandoc),
                target("epub", title: "EPUB", category: .document, family: .pandoc),
                target("rst", title: "reStructuredText", category: .document, family: .pandoc),
                target("latex", title: "LaTeX", category: .document, family: .pandoc),
                target("docbook", title: "DocBook", category: .document, family: .pandoc)
            ].filter { $0.outputExtension != ext })
        }

        if officeDocumentExtensions.contains(ext) {
            targets.append(contentsOf: [
                target("pdf", title: "PDF", category: .pdf, family: .soffice),
                target("docx", title: "Word .docx", category: .document, family: .soffice),
                target("odt", title: "OpenDocument Text", category: .document, family: .soffice),
                target("html", title: "HTML", category: .document, family: .soffice),
                target("txt", title: "Plain Text", category: .document, family: .soffice),
                target("rtf", title: "Rich Text", category: .document, family: .soffice)
            ].filter { $0.outputExtension != ext })
        }

        if pdfExtensions.contains(ext) {
            targets.append(contentsOf: [
                target("docx", title: "Word .docx", category: .document, family: .soffice),
                target("odt", title: "OpenDocument Text", category: .document, family: .soffice),
                target("rtf", title: "Rich Text", category: .document, family: .soffice),
                target("txt", title: "Plain Text", category: .document, family: .soffice)
            ])
        }

        if mediaExtensions.contains(ext) {
            let mediaTargets = audioExtensions.contains(ext)
                ? [target("mp3", category: .music, family: .mediaFFmpeg), target("m4a", category: .music, family: .mediaFFmpeg), target("wav", category: .music, family: .mediaFFmpeg), target("flac", category: .music, family: .mediaFFmpeg), target("ogg", category: .music, family: .mediaFFmpeg), target("aac", category: .music, family: .mediaFFmpeg)]
                : [target("mp4", category: .video, family: .mediaFFmpeg), target("mov", category: .video, family: .mediaFFmpeg), target("mkv", category: .video, family: .mediaFFmpeg), target("webm", category: .video, family: .mediaFFmpeg), target("mp3", title: "MP3 audio", category: .music, family: .mediaFFmpeg), target("gif", title: "GIF", category: .photo, family: .mediaFFmpeg)]
            targets.append(contentsOf: mediaTargets.filter { $0.outputExtension != ext })
        }

        return sortTargets(dedupeTargets(targets))
    }

    static func defaultTargetID(for url: URL, in targets: [FileConversionTarget]) -> String? {
        let ext = url.pathExtension.lowercased()
        let preferred: String?
        switch ext {
        case "png": preferred = "jpg"
        case "jpg", "jpeg", "heic", "heif", "tif", "tiff", "bmp", "gif", "webp": preferred = "png"
        case "pdf": preferred = "docx"
        case "doc", "docx", "odt", "rtf", "wordml", "pages", "html", "htm": preferred = "pdf"
        case "txt", "md", "markdown": preferred = "pdf"
        default:
            if audioExtensions.contains(ext) { preferred = "mp3" }
            else if videoExtensions.contains(ext) { preferred = "mp4" }
            else { preferred = nil }
        }
        if let preferred, let match = targets.first(where: { $0.id == preferred }) {
            return match.id
        }
        return targets.first?.id
    }

    static func convert(sourceURL: URL, target: FileConversionTarget, outputFolderURL: URL) async -> Result<URL, Error> {
        do {
            try Task.checkCancellation()
            try FileManager.default.createDirectory(at: outputFolderURL, withIntermediateDirectories: true)
            let destination = uniqueDestination(for: sourceURL, target: target, in: outputFolderURL)
            let artifactStore = ArtifactStore()
            let staged = try artifactStore.stage(for: destination)
            defer { artifactStore.discard(staged) }

            switch target.family {
            case .image:
                try await run("/usr/bin/sips", ["-s", "format", target.outputExtension == "jpg" ? "jpeg" : target.outputExtension, sourceURL.path, "--out", staged.url.path])
            case .text:
                try await run("/usr/bin/textutil", ["-convert", target.outputExtension, "-output", staged.url.path, sourceURL.path])
            case .mediaFFmpeg:
                let ffmpeg = try await executable(named: "ffmpeg", target: target)
                try await run(ffmpeg, ["-y", "-i", sourceURL.path, staged.url.path])
            case .imageMagick:
                let magick = try await executable(named: "magick", target: target)
                try await run(magick, [sourceURL.path, staged.url.path])
            case .pandoc:
                let pandoc = try await executable(named: "pandoc", target: target)
                try await run(pandoc, [sourceURL.path, "-o", staged.url.path])
            case .soffice:
                let soffice = try await executable(named: "soffice", target: target)
                let temporaryFolder = FileManager.default.temporaryDirectory.appendingPathComponent("Foundry-Conversion-\(UUID().uuidString)")
                try FileManager.default.createDirectory(at: temporaryFolder, withIntermediateDirectories: true)
                defer { try? FileManager.default.removeItem(at: temporaryFolder) }
                try await run(soffice, ["--headless", "--convert-to", sofficeFormat(target.outputExtension), "--outdir", temporaryFolder.path, sourceURL.path])
                let generated = temporaryFolder.appendingPathComponent(sourceURL.deletingPathExtension().lastPathComponent + "." + target.outputExtension)
                guard FileManager.default.fileExists(atPath: generated.path) else {
                    throw NSError(domain: "FoundryConversion", code: 2, userInfo: [NSLocalizedDescriptionKey: "LibreOffice did not produce the expected output."])
                }
                try FileManager.default.removeItem(at: staged.url)
                try FileManager.default.moveItem(at: generated, to: staged.url)
            }
            let committed = try artifactStore.commit(staged) { url in
                (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue ?? 0 > 0
            }
            return .success(committed)
        } catch {
            return .failure(error)
        }
    }

    private static func target(_ ext: String, title: String? = nil, category: FileConversionTarget.Category, family: FileConversionTarget.Family) -> FileConversionTarget {
        FileConversionTarget(id: ext, title: title ?? ext.uppercased(), outputExtension: ext, category: category, family: family)
    }

    private static func uniqueDestination(for sourceURL: URL, target: FileConversionTarget, in folder: URL) -> URL {
        let original = sourceURL.deletingPathExtension().lastPathComponent
        let extensionName = target.outputExtension
        var index = 1
        while true {
            let suffix = index == 1 ? "" : " \(index)"
            let candidate = folder.appendingPathComponent("\(original)\(suffix).\(extensionName)")
            if FileManager.default.fileExists(atPath: candidate.path) == false { return candidate }
            index += 1
        }
    }

    private static func run(_ path: String, _ arguments: [String]) async throws {
        let result = try await ProcessRunner.run(path: path, arguments: arguments, timeout: 30 * 60)
        guard result.succeeded else {
            if result.timedOut {
                throw NSError(domain: "FoundryConversion", code: 124, userInfo: [NSLocalizedDescriptionKey: "Conversion timed out."])
            }
            let output = result.stderr.isEmpty ? result.stdout : result.stderr
            let message = output.trimmingCharacters(in: .whitespacesAndNewlines)
            throw NSError(domain: "FoundryConversion", code: Int(result.exitCode), userInfo: [NSLocalizedDescriptionKey: message.isEmpty ? "Conversion failed" : message])
        }
    }

    private static func firstExecutable(_ paths: [String]) -> String? {
        paths.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    private static func executable(named name: String, target: FileConversionTarget) async throws -> String {
        if case .ready = await assess(target) {
            let paths = ["/opt/homebrew/bin/\(name)", "/usr/local/bin/\(name)", "/Applications/LibreOffice.app/Contents/MacOS/\(name)"]
            if let path = firstExecutable(paths) { return path }
        }
        throw FileConversionError.unavailable("Required converter is not ready")
    }

    static func preflightStatus(for target: FileConversionTarget) -> String? {
        nil
    }

    private static func sofficeFormat(_ ext: String) -> String {
        switch ext {
        case "pdf": return "pdf"
        case "docx": return "docx"
        case "odt": return "odt"
        case "html": return "html"
        case "txt": return "txt:Text"
        default: return ext
        }
    }

    private static func dedupeTargets(_ targets: [FileConversionTarget]) -> [FileConversionTarget] {
        var seen = Set<String>()
        return targets.filter { seen.insert($0.id).inserted }
    }

    private static func sortTargets(_ targets: [FileConversionTarget]) -> [FileConversionTarget] {
        targets.sorted { lhs, rhs in
            let left = categoryOrder[lhs.category] ?? 99
            let right = categoryOrder[rhs.category] ?? 99
            if left == right {
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
            return left < right
        }
    }

    private static func imageMetadata(for url: URL) -> ImageMetadata? {
        guard imageExtensions.contains(url.pathExtension.lowercased()),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? CGFloat,
              let height = properties[kCGImagePropertyPixelHeight] as? CGFloat else {
            return nil
        }
        return ImageMetadata(width: width, height: height)
    }

    private static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "heic", "tif", "tiff", "gif", "bmp", "webp"]
    private static let textDocumentExtensions: Set<String> = ["txt", "rtf", "rtfd", "html", "htm", "doc", "docx", "odt", "wordml", "webarchive"]
    private static let officeDocumentExtensions: Set<String> = ["doc", "docx", "odt", "rtf", "ppt", "pptx", "odp", "xls", "xlsx", "ods"]
    private static let pdfExtensions: Set<String> = ["pdf"]
    private static let audioExtensions: Set<String> = ["mp3", "m4a", "wav", "aif", "aiff", "caf", "aac", "flac", "ogg"]
    private static let videoExtensions: Set<String> = ["mp4", "mov", "m4v", "mkv", "webm", "avi", "mpeg", "mpg"]
    private static let mediaExtensions = audioExtensions.union(videoExtensions)
    private static let categoryOrder: [FileConversionTarget.Category: Int] = [
        .photo: 0,
        .icon: 1,
        .document: 2,
        .pdf: 3,
        .music: 4,
        .video: 5
    ]
}

private struct ImageMetadata {
    let width: CGFloat
    let height: CGFloat

    var isIconCandidate: Bool {
        abs(width - height) < 0.5 && width <= 2048 && height <= 2048
    }
}
