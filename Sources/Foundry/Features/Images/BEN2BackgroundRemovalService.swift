import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers
import FoundryServices

struct BEN2BackgroundRemovalService: BackgroundRemoving, Sendable {
    static func assess(root: URL? = nil, executablePaths: [String: String] = [:]) -> BEN2Assessment {
        BEN2Runtime.assess(root: root, executablePaths: executablePaths)
    }

    static func removeData(root: URL? = nil) throws {
        try BEN2Runtime.removeData(root: root)
    }

    static func setup(root: URL? = nil, status: (@MainActor @Sendable (String) -> Void)? = nil) async throws {
        try await BEN2Runtime.shared.setup(root: root, status: status)
    }

    static func cancelSetup() {
        Task { await BEN2Runtime.shared.cancelSetup() }
    }
    func supports(_ sourceURL: URL) -> Bool {
        BackgroundRemovalFileSupport.supportsStillImage(sourceURL)
    }

    func removeBackground(from sourceURL: URL, destinationURL: URL? = nil) async throws -> URL {
        try await removeBackground(from: sourceURL, destinationURL: destinationURL, status: nil)
    }

    func removeBackground(
        from sourceURL: URL,
        destinationURL: URL?,
        status: (@MainActor @Sendable (String) -> Void)?
    ) async throws -> URL {
        guard supports(sourceURL) else { throw BackgroundRemovalError.unsupportedFile }
        return try await BEN2Runtime.shared.removeBackground(
            from: sourceURL,
            destinationURL: destinationURL,
            status: status
        )
    }
}

private actor BEN2Runtime {
    static let shared = BEN2Runtime()

    private var preparedPaths: Paths?
    private var setupTask: Task<Void, Error>?

    nonisolated static func assess(root: URL?, executablePaths: [String: String]) -> BEN2Assessment {
        let root = root ?? BEN2Artifact.defaultRoot
        let fm = FileManager.default
        let model = root.appendingPathComponent("models/\(BEN2Artifact.filename)")
        let runtime = root.appendingPathComponent("runtime")
        let modelState: BEN2ComponentState = fm.fileExists(atPath: model.path)
            ? ((try? BEN2Artifact.sha256(at: model)) == BEN2Artifact.sha256 ? .ready : .invalid)
            : .missing
        let runtimeManifest = runtime.appendingPathComponent("runtime-manifest.json")
        let runtimeState: BEN2ComponentState = fm.fileExists(atPath: runtimeManifest.path)
            ? (BEN2Runtime.isRuntimeReady(python: runtime.appendingPathComponent("bin/python"), manifest: runtimeManifest) ? .ready : .invalid)
            : .missing
        let uv = executablePaths["uv"] ?? ["/opt/homebrew/bin/uv", "/usr/local/bin/uv", fm.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin/uv").path].first(where: fm.isExecutableFile(atPath:))
        let plan = SetupPlan(
            commands: [],
            artifacts: [Artifact(origin: BEN2Artifact.downloadURL.absoluteString + " (Apache-2.0; PramaLLC/BEN2)", destination: model.path, downloadBytes: BEN2Artifact.byteSize, installBytes: BEN2Artifact.byteSize, integrityExpectation: "sha256:\(BEN2Artifact.sha256)")],
            estimatedDownloadBytes: BEN2Artifact.byteSize,
            estimatedInstallBytes: BEN2Artifact.byteSize + 180_000_000,
            mutationScope: "Application Support/Foundry/BackgroundRemoval only after explicit Set Up BEN2",
            cleanupOwnership: "Foundry; Remove BEN2 Data deletes model and runtime",
            disclosure: "Pinned BEN2 model is 223 MB from Hugging Face (PramaLLC/BEN2), licensed Apache-2.0, SHA-256 verified, installed at Application Support/Foundry/BackgroundRemoval. Setup creates a Python 3.13 runtime with hash-pinned onnxruntime==1.24.2, numpy==2.5.1, and Pillow==11.3.0; estimated installed size is about 384 MB. uv is required for provisioning."
        )
        let visionState: BEN2ComponentState = { if #available(macOS 14.0, *) { return .ready }; return .unavailable("BEN2 requires macOS 14 or newer Vision support.") }()
        return BEN2Assessment(visionState: visionState, modelState: modelState, runtimeState: runtimeState, provisioningState: uv == nil ? .unavailable("uv is not installed") : .available, setupPlan: plan)
    }

    nonisolated static func removeData(root: URL?) throws {
        let root = root ?? BEN2Artifact.defaultRoot
        if FileManager.default.fileExists(atPath: root.path) { try FileManager.default.removeItem(at: root) }
    }

    func setup(root: URL?, status: (@MainActor @Sendable (String) -> Void)?) async throws {
        try Task.checkCancellation()
        let root = root ?? BEN2Artifact.defaultRoot
        let task: Task<Void, Error>
        if let existingTask = setupTask {
            task = existingTask
        } else {
            task = Task { [self] in
                defer { setupTask = nil }
                try await performSetup(root: root, status: status)
            }
            setupTask = task
        }
        try await withTaskCancellationHandler {
            try await task.value
            try Task.checkCancellation()
        } onCancel: {
            // A caller leaving its wait must not cancel setup shared by other callers.
        }
    }

    func cancelSetup() {
        setupTask?.cancel()
    }

    private func performSetup(root: URL, status: (@MainActor @Sendable (String) -> Void)?) async throws {
        guard let uv = firstExecutable(["/opt/homebrew/bin/uv", "/usr/local/bin/uv", FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin/uv").path]) else { throw BackgroundRemovalError.modelUnavailable("BEN2 needs uv to install its local runtime. Install uv with Homebrew, then try again.") }
        guard let script = Bundle.module.url(forResource: "background_removal_worker", withExtension: "py") else { throw BackgroundRemovalError.modelSetupFailed("The bundled background-removal worker script is missing.") }
        let staging = root.deletingLastPathComponent().appendingPathComponent(".foundry-ben2-staging-\(UUID().uuidString)")
        let stagedModel = staging.appendingPathComponent("models/\(BEN2Artifact.filename)")
        let stagedRuntime = staging.appendingPathComponent("runtime")
        defer { try? FileManager.default.removeItem(at: staging) }
        try FileManager.default.createDirectory(at: stagedModel.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: stagedRuntime.deletingLastPathComponent(), withIntermediateDirectories: true)
        await report("Downloading BEN2 (about 223 MB)...", status)
        try await downloadModel(to: stagedModel)
        await report("Installing Python 3.13 runtime...", status)
        try await run(uv: uv, arguments: ["venv", "--python", "3.13", stagedRuntime.path])
        let python = stagedRuntime.appendingPathComponent("bin/python")
        try await run(uv: uv, arguments: ["pip", "install", "--require-hashes", "--python", python.path,
            "onnxruntime==1.24.2", "--hash=sha256:038ebcd8363c3835ea83eed66129e1d11d8219438892dfb7dc7656c4d4dfa1f9",
            "numpy==2.5.1", "--hash=sha256:30b44a6b53a7ae63c54c089a8726e5563ed302716c5b7ccc85afade40b0e7ff6",
            "Pillow==11.3.0", "--hash=sha256:7db51d222548ccfd274e4572fdbf3e810a5e66b00608862f947b163e613b67dd"])
        try writeManifest(runtime: stagedRuntime)
        guard Self.isRuntimeReady(python: python, manifest: stagedRuntime.appendingPathComponent("runtime-manifest.json")) else { throw BackgroundRemovalError.modelSetupFailed("Runtime manifest verification failed.") }
        try Task.checkCancellation()
        try promote(staging: staging, destination: root)
        try Task.checkCancellation()
        preparedPaths = Paths(python: root.appendingPathComponent("runtime/bin/python"), model: root.appendingPathComponent("models/\(BEN2Artifact.filename)"), script: script)
    }

    func removeBackground(
        from sourceURL: URL,
        destinationURL preferredDestination: URL?,
        status: (@MainActor @Sendable (String) -> Void)?
    ) async throws -> URL {
        try Task.checkCancellation()
        guard #available(macOS 14.0, *) else { throw BackgroundRemovalError.unavailable("BEN2 requires macOS 14 or newer Vision support.") }
        guard let paths = try verifiedPaths(root: BEN2Artifact.defaultRoot) else { throw BackgroundRemovalError.setupRequired }
        let outputURL = BackgroundRemovalFileSupport.destinationURL(
            for: sourceURL,
            preferredURL: preferredDestination,
            defaultStemSuffix: " - background removed (BEN2)"
        )
        let folder = outputURL.deletingLastPathComponent()
        guard FileManager.default.fileExists(atPath: folder.path) else {
            throw BackgroundRemovalError.destinationNotWritable
        }

        let artifactStore = ArtifactStore()
        let staged = try artifactStore.stage(for: outputURL)
        defer { try? FileManager.default.removeItem(at: staged.url) }

        await report("Running BEN2...", status)
        do {
            let result = try await ProcessRunner.run(
                path: paths.python.path,
                arguments: [
                    paths.script.path,
                    "--worker-sha256", BEN2Artifact.workerSHA256,
                    "--model", paths.model.path,
                    "--input", sourceURL.path,
                    "--output", staged.url.path
                ],
                timeout: 30 * 60,
                outputLimit: 8 * 1024 * 1024
            )
            guard result.succeeded else {
                let details = result.stderr.isEmpty ? result.stdout : result.stderr
                let message = details.trimmingCharacters(in: .whitespacesAndNewlines)
                throw BackgroundRemovalError.processingFailed(
                    message.isEmpty ? "BEN2 could not process this image." : "BEN2 failed: \(message)"
                )
            }
        } catch ProcessRunnerError.cancelled {
            throw CancellationError()
        } catch let error as BackgroundRemovalError {
            throw error
        } catch {
            throw BackgroundRemovalError.processingFailed(error.localizedDescription)
        }

        try Task.checkCancellation()
        do {
            guard isPNG(at: staged.url) else { throw BackgroundRemovalError.processingFailed("BEN2 produced an invalid PNG.") }
            _ = try artifactStore.commit(staged) { [self] url in isPNG(at: url) }
        } catch let error as BackgroundRemovalError {
            throw error
        } catch {
            throw BackgroundRemovalError.destinationNotWritable
        }
        return outputURL
    }

    private func verifiedPaths(root: URL) throws -> Paths? {
        guard let script = Bundle.module.url(forResource: "background_removal_worker", withExtension: "py"),
              (try? BEN2Artifact.sha256(at: script)) == BEN2Artifact.workerSHA256 else { return nil }
        let model = root.appendingPathComponent("models/\(BEN2Artifact.filename)")
        let python = root.appendingPathComponent("runtime/bin/python")
        guard isValidModelSync(at: model), Self.isRuntimeReady(python: python, manifest: root.appendingPathComponent("runtime/runtime-manifest.json")) else { return nil }
        return Paths(python: python, model: model, script: script)
    }

    private func isValidModelSync(at url: URL) -> Bool {
        guard let size = try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber,
              size.int64Value == BEN2Artifact.byteSize else { return false }
        return (try? BEN2Artifact.sha256(at: url)) == BEN2Artifact.sha256
    }

    private func isPNG(at url: URL) -> Bool {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let type = CGImageSourceGetType(source),
              let contentType = UTType(type as String) else { return false }
        return contentType.conforms(to: .png) && CGImageSourceGetCount(source) == 1
    }

    private func downloadModel(to destination: URL) async throws {
        let temporaryURL = destination.deletingLastPathComponent()
            .appendingPathComponent(".\(destination.lastPathComponent).download")
        try? FileManager.default.removeItem(at: temporaryURL)
        defer { try? FileManager.default.removeItem(at: temporaryURL) }

        let (downloadedURL, response) = try await URLSession.shared.download(from: BEN2Artifact.downloadURL)
        if let response = response as? HTTPURLResponse, response.statusCode != 200 {
            throw BackgroundRemovalError.modelSetupFailed(
                "BEN2 download returned HTTP \(response.statusCode)."
            )
        }
        try FileManager.default.moveItem(at: downloadedURL, to: temporaryURL)
        guard await isValidModel(at: temporaryURL) else {
            throw BackgroundRemovalError.modelSetupFailed("The downloaded BEN2 model failed its checksum.")
        }
        try FileManager.default.moveItem(at: temporaryURL, to: destination)
    }

    private func isValidModel(at url: URL) async -> Bool {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? NSNumber,
              size.int64Value == BEN2Artifact.byteSize else {
            return false
        }

        return (try? await Task.detached {
            try BEN2Artifact.sha256(at: url) == BEN2Artifact.sha256
        }.value) ?? false
    }

    nonisolated static func isRuntimeReady(python: URL, manifest: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: python.path),
              let contents = try? String(contentsOf: manifest, encoding: .utf8) else { return false }
        guard let data = contents.data(using: .utf8),
              let manifest = try? JSONDecoder().decode(RuntimeManifest.self, from: data),
               manifest.python == "3.13",
               manifest.packages == BEN2Artifact.packages,
               (try? BEN2Artifact.sha256(at: python)) == manifest.pythonSHA256,
               let inventory = try? runtimeInventory(at: python.deletingLastPathComponent().deletingLastPathComponent()),
               inventory == manifest.inventory else { return false }
        return inventory.isEmpty == false
    }

    private func writeManifest(runtime: URL) throws {
        let python = runtime.appendingPathComponent("bin/python")
        let manifest = RuntimeManifest(python: "3.13", pythonSHA256: try BEN2Artifact.sha256(at: python), packages: BEN2Artifact.packages, inventory: try Self.runtimeInventory(at: runtime))
        try JSONEncoder().encode(manifest).write(to: runtime.appendingPathComponent("runtime-manifest.json"), options: .atomic)
    }

    nonisolated static func runtimeInventory(at runtime: URL) throws -> [RuntimeFile] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: runtime, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey], options: []) else { return [] }
        var files = [RuntimeFile]()
        for case let url as URL in enumerator {
            if url.lastPathComponent == "runtime-manifest.json" { continue }
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values.isRegularFile == true else { continue }
            let relative = String(url.path.dropFirst(runtime.path.count + 1))
            files.append(RuntimeFile(path: relative, size: Int64(values.fileSize ?? 0), sha256: try BEN2Artifact.sha256(at: url)))
        }
        return files.sorted { $0.path < $1.path }
    }

    private func promote(staging: URL, destination: URL) throws {
        let fm = FileManager.default
        let backup = destination.deletingLastPathComponent().appendingPathComponent(".\(destination.lastPathComponent).backup-\(UUID().uuidString)")
        if fm.fileExists(atPath: destination.path) { try fm.moveItem(at: destination, to: backup) }
        do {
            try fm.moveItem(at: staging, to: destination)
            try? fm.removeItem(at: backup)
        } catch {
            try? fm.removeItem(at: destination)
            if fm.fileExists(atPath: backup.path) { try? fm.moveItem(at: backup, to: destination) }
            throw error
        }
    }

    private func run(uv: String, arguments: [String]) async throws {
        let result = try await ProcessRunner.run(
            path: uv,
            arguments: arguments,
            timeout: 30 * 60,
            outputLimit: 8 * 1024 * 1024
        )
        guard result.succeeded else {
            let details = result.stderr.isEmpty ? result.stdout : result.stderr
            let message = details.trimmingCharacters(in: .whitespacesAndNewlines)
            throw BackgroundRemovalError.modelSetupFailed(
                message.isEmpty ? "The local dependency command failed." : message
            )
        }
    }

    private func report(_ message: String, _ status: (@MainActor @Sendable (String) -> Void)?) async {
        guard let status else { return }
        guard Task.isCancelled == false else { return }
        await status(message)
    }

    private func firstExecutable(_ paths: [String]) -> String? {
        paths.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    private struct Paths: Sendable {
        let python: URL
        let model: URL
        let script: URL
    }

    private struct RuntimeManifest: Codable {
        let python: String
        let pythonSHA256: String
        let packages: [String: String]
        let inventory: [RuntimeFile]
    }

    struct RuntimeFile: Codable, Equatable {
        let path: String
        let size: Int64
        let sha256: String
    }
}

private enum BEN2Artifact {
    static let revision = "e48a20765fb421d19dcdb0bf3cc61e802ca5ec8f"
    static let filename = "ben2_base.onnx"
    static let byteSize: Int64 = 222_932_053
    static let sha256 = "22cea62108ff53b7ccc20f7a008bf30494228d84b1687f29ecbe76936a998101"
    static let packages = [
        "onnxruntime": "1.24.2#sha256=038ebcd8363c3835ea83eed66129e1d11d8219438892dfb7dc7656c4d4dfa1f9",
        "numpy": "2.5.1#sha256=30b44a6b53a7ae63c54c089a8726e5563ed302716c5b7ccc85afade40b0e7ff6",
        "Pillow": "11.3.0#sha256=7db51d222548ccfd274e4572fdbf3e810a5e66b00608862f947b163e613b67dd"
    ]
    static let workerSHA256 = "8cf214b9d16e6a28329824f6533fc3acf7831d79f51270565d77d9d4d6875b10"
    static let downloadURL = URL(string: "https://huggingface.co/PramaLLC/BEN2/resolve/\(revision)/BEN2_Base.onnx?download=true")!
    static let defaultRoot = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Foundry/BackgroundRemoval", isDirectory: true)

    static func sha256(at url: URL) throws -> String {
        var digest = SHA256()
        let handle = try FileHandle(forReadingFrom: url)
        while let chunk = try handle.read(upToCount: 4 * 1024 * 1024), chunk.isEmpty == false {
            digest.update(data: chunk)
        }
        return digest.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
