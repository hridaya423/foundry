import AppKit
import Foundation
import UniformTypeIdentifiers
import FoundryServices
import Observation

@MainActor
@Observable
final class FileConversionState {
    var sourceURLs: [URL] = []
    var outputFolderURL: URL?
    var availableTargets: [FileConversionTarget] = []
    var selectedTargetID: String?
    var options = ConversionOptions.standard
    var status = ""
    var isConverting = false
    var outputURLs: [URL] = []
    var outputURL: URL?
    var dependencySetup: DependencySetup? = nil
    private(set) var phase: OperationPhase = .assessing
    private(set) var progress: OperationProgress?
    private(set) var failure: OperationFailure?
    private(set) var itemOutcomes: [FileConversionItemOutcome] = []
    private(set) var capabilities: [String: FileConversionCapability] = [:]

    private var conversionTask: Task<Void, Never>?

    /// Fired once ever when the first batch completes cleanly — lets the
    /// panel celebrate without FileConversionState owning motion.
    var onFirstSuccess: (() -> Void)?
    /// Fired on every cleanly completed batch — the panel maps this to a
    /// gated haptic.
    var onConversionCompleted: (() -> Void)?
    /// Result-row affordances — wired by the owning panel state.
    var onQuickLookOutput: ((URL) -> Void)?
    var onShareOutput: ((URL) -> Void)?
    private let assess: @Sendable (FileConversionTarget, [String]) async -> CapabilityState
    private let provision: @Sendable (SetupPlan, String) async throws -> Void
    private let convertOperation: @Sendable (URL, FileConversionTarget, URL, ConversionOptions) async -> Result<URL, Error>
    private let operations: OperationCoordinator
    private let localState: LocalStateStore
    private var operationID: UUID?
    private var conversionGeneration = UUID()
    private var lastRequest: (sources: [URL], target: FileConversionTarget, folder: URL)?

    var currentOperationSnapshot: OperationSnapshot? {
        guard let operationID else { return nil }
        return operations.snapshot(id: operationID)
    }

    init(
        assess: @escaping @Sendable (FileConversionTarget, [String]) async -> CapabilityState = { target, inputExts in
            await FileConversionService.assess(target: target.outputExtension, forInputExts: inputExts)
        },
        provision: @escaping @Sendable (SetupPlan, String) async throws -> Void = { plan, fingerprint in
            let executor = ClosureProvisioningExecutor { command in
                _ = try await ProcessRunner.run(path: command.executable, arguments: command.arguments)
            }
            _ = try await DependencyProvisioner(executor: executor).provision(plan: plan, approvedFingerprint: fingerprint)
        },
        convert: @escaping @Sendable (URL, FileConversionTarget, URL, ConversionOptions) async -> Result<URL, Error> = { source, target, folder, options in
            await FileConversionService.convert(sourceURL: source, target: target, outputFolderURL: folder, options: options)
        },
        operations: OperationCoordinator = OperationCoordinator(),
        localState: LocalStateStore = .shared
    ) {
        self.assess = assess; self.provision = provision; self.convertOperation = convert; self.operations = operations
        self.localState = localState
    }

    var selectedTarget: FileConversionTarget? {
        availableTargets.first { $0.id == selectedTargetID } ?? availableTargets.first
    }

    var sourceURL: URL? {
        sourceURLs.first
    }

    func reset() {
        if let operationID {
            _ = operations.update(id: operationID, phase: .cancelled, progress: progress, failure: OperationFailure(message: "Conversion cancelled"))
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
        panel.allowsMultipleSelection = true
        panel.prompt = sourceURLs.isEmpty ? "Choose" : "Add"
        if panel.runModal() == .OK, panel.urls.isEmpty == false {
            addSources(urls: panel.urls)
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

    /// Merge additional files into the current batch (drop / "Add Files").
    func addSources(urls: [URL]) {
        guard urls.isEmpty == false else { return }
        setSources(urls: sourceURLs + urls)
    }

    func removeSource(url: URL) {
        guard sourceURLs.contains(url) else { return }
        if sourceURLs.count == 1 {
            startOver()
        } else {
            setSources(urls: sourceURLs.filter { $0 != url })
        }
    }

    /// Clear the batch and results while keeping the pane open.
    func startOver() {
        conversionGeneration = UUID()
        conversionTask?.cancel()
        conversionTask = nil
        if let operationID {
            _ = operations.update(id: operationID, phase: .cancelled, progress: progress, failure: OperationFailure(message: "Conversion cancelled"))
        }
        sourceURLs = []
        outputFolderURL = nil
        availableTargets = []
        selectedTargetID = nil
        options = .standard
        status = ""
        isConverting = false
        outputURLs = []
        outputURL = nil
        dependencySetup = nil
        capabilities = [:]
        phase = .assessing; progress = nil; failure = nil; itemOutcomes = []; operationID = nil; lastRequest = nil
    }

    func setSources(urls: [URL]) {
        if isConverting {
            // A new source set invalidates the in-flight batch — cancel it so
            // late results can't write outcomes for a batch the user replaced.
            conversionGeneration = UUID()
            conversionTask?.cancel()
            conversionTask = nil
            isConverting = false
            if let operationID {
                _ = operations.update(id: operationID, phase: .cancelled, progress: progress, failure: OperationFailure(message: "Conversion cancelled"))
            }
        }
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
            guard case .ready = await assess(setup.target, sourceURLs.map { ConversionGraph.normalizedExtension(of: $0) }) else { throw FileConversionError.unavailable("The installed converter is not ready yet") }
            guard Task.isCancelled == false,
                  conversionGeneration == generation,
                  sourceURLs == sources else { return }
            startConversion(sourceURLs: sources, target: setup.target, operationID: id, requestedOutputFolder: folder)
        } catch is CancellationError {
            guard conversionGeneration == generation else { return }
            phase = .cancelled; status = "Tool installation cancelled"
            operations.update(id: id, phase: .cancelled, progress: progress, failure: OperationFailure(message: "Tool installation cancelled"))
        } catch {
            guard conversionGeneration == generation else { return }
            failProvisioning(operationID: id, error: error)
        }
    }

    func installTool() async {
        guard let setup = dependencySetup, isCurrentSetup(setup) else { return }
        let id = beginProvisioning()
        let generation = conversionGeneration
        dependencySetup = nil
        do {
            try await provision(setup.plan, setup.plan.fingerprint)
            await refreshCapabilities()
            guard conversionGeneration == generation else { return }
            phase = .completed; progress = .items(completed: 1, total: 1); status = "Tool installed"
            operations.update(id: id, phase: .completed, progress: progress)
        } catch is CancellationError {
            guard conversionGeneration == generation else { return }
            phase = .cancelled; status = "Tool installation cancelled"
            operations.update(id: id, phase: .cancelled, progress: progress, failure: OperationFailure(message: "Tool installation cancelled"))
        } catch {
            guard conversionGeneration == generation else { return }
            failProvisioning(operationID: id, error: error)
        }
    }

    func refreshCapabilities() async {
        let inputExts = sourceURLs.map { ConversionGraph.normalizedExtension(of: $0) }
        var refreshed: [String: FileConversionCapability] = [:]
        for target in availableTargets { refreshed[target.id] = FileConversionCapability(state: await assess(target, inputExts)) }
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
        let preserved = Dictionary(uniqueKeysWithValues: preservingCompleted.map { ($0.sourceURL, $0) })
        itemOutcomes = sourceURLs.map { preserved[$0] ?? FileConversionItemOutcome(sourceURL: $0, state: .pending, outputURL: nil, failure: nil) }
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
            ? "Converting to \(target.title)…"
            : "Preparing \(total) files…"

        conversionTask = Task { [weak self] in
            let workSources = sourceURLs.filter { url in
                self?.itemOutcomes.first(where: { $0.sourceURL == url })?.state != .completed
            }

            // Merge path: several pdfs/images sharing the pdf target produce
            // one combined document instead of per-file outputs.
            if FileConversionService.shouldMergeForPDFTarget(sources: workSources, target: target) {
                await MainActor.run { [weak self] in
                    self?.status = "Merging \(workSources.count) files into one PDF…"
                }
                let snapshot = self?.options ?? .standard
                let destination = FileConversionService.destination(
                    for: workSources[0], ext: "pdf", in: outputFolderURL, options: snapshot)
                do {
                    try await FileConversionService.mergeToPDF(sources: workSources, into: destination, options: snapshot)
                    await MainActor.run { [weak self] in
                        guard let self else { return }
                        for sourceURL in workSources {
                            self.setOutcome(sourceURL, state: .completed, outputURL: destination, failure: nil)
                        }
                        self.progress = .items(completed: completedBeforeStart + workSources.count, total: total)
                    }
                } catch {
                    let isCancel = error is CancellationError
                    await MainActor.run { [weak self] in
                        guard let self else { return }
                        if isCancel {
                            self.cancelRemaining(sourceURLs, generation: generation, operationID: operationID)
                        } else {
                            for sourceURL in workSources {
                                self.setOutcome(sourceURL, state: .failed, outputURL: nil, failure: OperationFailure(message: error.localizedDescription))
                            }
                        }
                    }
                    if isCancel { return }
                }
                await MainActor.run { [weak self] in
                    self?.finishConversion(generation: generation, operationID: operationID, total: total)
                }
                return
            }

            if target.externalEngines.isEmpty == false, workSources.count > 1 {
                // External engines (ffmpeg/magick/pandoc/soffice) are
                // process-based and safe to overlap — cap at 2 concurrent.
                let completedRun = await self?.runExternalBatch(
                    workSources,
                    target: target,
                    outputFolderURL: outputFolderURL,
                    generation: generation,
                    operationID: operationID,
                    completedBeforeStart: completedBeforeStart,
                    total: total,
                    allSources: sourceURLs
                ) ?? true
                if completedRun == false { return }
            } else {
                for (index, sourceURL) in workSources.enumerated() {
                    guard Task.isCancelled == false else { await MainActor.run { self?.cancelRemaining(sourceURLs, generation: generation, operationID: operationID) }; return }
                    await MainActor.run { self?.setOutcome(sourceURL, state: .processing, outputURL: nil, failure: nil) }
                    await MainActor.run { [weak self] in
                        guard let self else { return }
                        let prefix = total == 1 ? "" : "\(index + 1) of \(total): "
                        self.status = prefix + "Converting to \(target.title)…"
                    }

                    let snapshot = self?.options ?? .standard
                    let result = await self?.convertOperation(sourceURL, target, outputFolderURL, snapshot) ?? .failure(FileConversionError.cancelled)
                    guard Task.isCancelled == false else { await MainActor.run { self?.cancelRemaining(sourceURLs, generation: generation, operationID: operationID) }; return }
                    if await self?.recordConversionResult(result, for: sourceURL, sourceURLs: sourceURLs, generation: generation, operationID: operationID) == false { return }
                    await MainActor.run { [weak self] in
                        let completed = completedBeforeStart + index + 1
                        self?.progress = .items(completed: completed, total: total)
                        if let operationID = self?.operationID { self?.operations.updateProgress(id: operationID, progress: .items(completed: completed, total: total)) }
                    }
                }
            }

            await MainActor.run {
                self?.finishConversion(generation: generation, operationID: operationID, total: total)
            }
        }
    }

    /// Record a per-file conversion result. Returns false when cancellation
    /// should abort the batch.
    private func recordConversionResult(_ result: Result<URL, Error>, for sourceURL: URL, sourceURLs: [URL], generation: UUID, operationID: UUID) async -> Bool {
        switch result {
        case let .success(outputURL):
            await MainActor.run { self.setOutcome(sourceURL, state: .completed, outputURL: outputURL, failure: nil) }
            return true
        case let .failure(error):
            if error is CancellationError || isCancellation(error) {
                await MainActor.run { self.cancelRemaining(sourceURLs, generation: generation, operationID: operationID) }
                return false
            }
            await MainActor.run { self.setOutcome(sourceURL, state: .failed, outputURL: nil, failure: OperationFailure(message: error.localizedDescription)) }
            return true
        }
    }

    /// Overlap external-engine conversions (ffmpeg/magick/pandoc/soffice) with
    /// a sliding window of at most two in flight. Returns false when the batch
    /// was cancelled — `cancelRemaining` has already finalized the operation.
    private func runExternalBatch(_ workSources: [URL], target: FileConversionTarget, outputFolderURL: URL, generation: UUID, operationID: UUID, completedBeforeStart: Int, total: Int, allSources: [URL]) async -> Bool {
        let snapshot = options
        await MainActor.run { [weak self] in
            self?.status = "Converting \(workSources.count) files to \(target.title)…"
        }
        var completedCount = 0
        var cancelled = false
        await withTaskGroup(of: (URL, Result<URL, Error>).self) { group in
            var pending = workSources.makeIterator()
            for _ in 0..<2 {
                guard let next = pending.next() else { break }
                group.addTask { [weak self] in await self?.convertOne(next, target: target, folder: outputFolderURL, options: snapshot) ?? (next, .failure(FileConversionError.cancelled)) }
            }
            while let (sourceURL, result) = await group.next() {
                completedCount += 1
                if cancelled { continue }
                if Task.isCancelled || conversionGeneration != generation {
                    cancelled = true
                    group.cancelAll()
                    pending = [].makeIterator()
                    continue
                }
                if await self.recordConversionResult(result, for: sourceURL, sourceURLs: allSources, generation: generation, operationID: operationID) == false {
                    cancelled = true
                    group.cancelAll()
                    pending = [].makeIterator()
                    continue
                }
                await MainActor.run { [weak self] in
                    let completed = completedBeforeStart + completedCount
                    self?.progress = .items(completed: completed, total: total)
                    if let operationID = self?.operationID { self?.operations.updateProgress(id: operationID, progress: .items(completed: completed, total: total)) }
                }
                if let next = pending.next() {
                    group.addTask { [weak self] in await self?.convertOne(next, target: target, folder: outputFolderURL, options: snapshot) ?? (next, .failure(FileConversionError.cancelled)) }
                }
            }
        }
        return cancelled == false
    }

    /// One batch item: mark processing, run the conversion, hand back the result.
    private func convertOne(_ sourceURL: URL, target: FileConversionTarget, folder: URL, options: ConversionOptions) async -> (URL, Result<URL, Error>) {
        if Task.isCancelled == false {
            setOutcome(sourceURL, state: .processing, outputURL: nil, failure: nil)
        }
        let result = await convertOperation(sourceURL, target, folder, options)
        return (sourceURL, result)
    }

    /// Shared completion for the per-file loop and the merge path: collapses
    /// item outcomes into phase/status/operation updates.
    private func finishConversion(generation: UUID, operationID: UUID, total: Int) {
        guard self.conversionGeneration == generation, self.operationID == operationID, self.isConverting else { return }
        let outputs = Array(NSOrderedSet(array: self.itemOutcomes.compactMap(\.outputURL))) as? [URL] ?? self.itemOutcomes.compactMap(\.outputURL)
        let failures = self.itemOutcomes.compactMap { outcome -> String? in
            guard outcome.state == .failed else { return nil }
            return total == 1 ? outcome.failure?.message : "\(outcome.sourceURL.lastPathComponent): \(outcome.failure?.message ?? "Conversion failed")"
        }
        self.isConverting = false
        self.outputURLs = outputs
        self.outputURL = outputs.last
        self.phase = failures.isEmpty ? .completed : .failed
        self.failure = failures.isEmpty ? nil : OperationFailure(message: failures.joined(separator: "\n"))
        if failures.isEmpty {
            _ = self.operations.update(id: operationID, phase: .completed, progress: self.progress)
            self.status = outputs.count == 1
                ? "Created \(outputs[0].lastPathComponent)"
                : "Created \(outputs.count) files"
            if localState.get(\.conversionFirstSuccessCelebrated) == false {
                localState.set(\.conversionFirstSuccessCelebrated, true)
                onFirstSuccess?()
            } else {
                onConversionCompleted?()
            }
        } else {
            _ = self.operations.update(id: operationID, phase: .failed, progress: self.progress, failure: self.failure)
            self.status = outputs.isEmpty
                ? failures.joined(separator: "\n")
                : "Created \(outputs.count) of \(total) files; \(failures.count) failed"
        }
    }

    func retryFailed() {
        guard let request = lastRequest else { return }
        let failed = itemOutcomes.filter { $0.state == .failed || $0.state == .cancelled }.map(\.sourceURL)
        guard failed.isEmpty == false else { return }
        Task { [weak self] in
            guard let self else { return }
            switch await self.assess(request.target, request.sources.map { ConversionGraph.normalizedExtension(of: $0) }) {
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
            setOutcome(url, state: .cancelled, outputURL: nil, failure: OperationFailure(message: "Cancelled"))
        }
        let completed = itemOutcomes.filter { $0.state == .completed }.count
        outputURLs = itemOutcomes.compactMap(\.outputURL)
        outputURL = outputURLs.last
        progress = .items(completed: completed, total: itemOutcomes.count)
        status = "Conversion cancelled after creating \(completed) of \(itemOutcomes.count) files"
        phase = .cancelled; isConverting = false
        if let operationID { operations.update(id: operationID, phase: .cancelled, progress: progress, failure: OperationFailure(message: "Conversion cancelled")) }
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
        let typed = OperationFailure(message: error.localizedDescription)
        failure = typed; phase = .failed; status = "Tool installation failed: \(typed.message)"
        operations.update(id: operationID, phase: .failed, progress: progress, failure: typed)
    }

    func revealOutput() {
        guard outputURLs.isEmpty == false else { return }
        NSWorkspace.shared.activateFileViewerSelecting(outputURLs)
    }

    /// Shared output formats across all sources. Compared by output extension
    /// only — each file re-resolves its own route at convert time, so a mixed
    /// batch (jpg + docx → PDF) shares one target with different routes.
    private func commonTargets(for urls: [URL]) -> [FileConversionTarget] {
        guard let firstURL = urls.first else { return [] }
        let firstTargets = FileConversionService.availableTargets(for: firstURL)
        guard urls.count > 1 else { return firstTargets }

        let remainingExts = urls.dropFirst().map {
            Set(FileConversionService.availableTargets(for: $0).map(\.outputExtension))
        }
        return firstTargets.filter { target in
            remainingExts.allSatisfy { $0.contains(target.outputExtension) }
        }
    }
}

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
