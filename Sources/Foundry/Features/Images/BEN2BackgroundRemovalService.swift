import CryptoKit
import Foundation
import FoundryServices

struct BEN2BackgroundRemovalService: BackgroundRemoving, Sendable {
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

    func removeBackground(
        from sourceURL: URL,
        destinationURL preferredDestination: URL?,
        status: (@MainActor @Sendable (String) -> Void)?
    ) async throws -> URL {
        try Task.checkCancellation()
        let paths = try await prepare(status: status)
        let outputURL = BackgroundRemovalFileSupport.destinationURL(
            for: sourceURL,
            preferredURL: preferredDestination,
            defaultStemSuffix: " - background removed (BEN2)"
        )
        let folder = outputURL.deletingLastPathComponent()
        guard FileManager.default.fileExists(atPath: folder.path) else {
            throw BackgroundRemovalError.destinationNotWritable
        }

        let temporaryURL = folder.appendingPathComponent(
            ".foundry-ben2-background-removal-\(UUID().uuidString).png"
        )
        defer { try? FileManager.default.removeItem(at: temporaryURL) }

        report("Running BEN2...", status)
        do {
            let result = try await ProcessRunner.run(
                path: paths.python.path,
                arguments: [
                    paths.script.path,
                    "--model", paths.model.path,
                    "--input", sourceURL.path,
                    "--output", temporaryURL.path
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
            try FileManager.default.moveItem(at: temporaryURL, to: outputURL)
        } catch {
            throw BackgroundRemovalError.destinationNotWritable
        }
        return outputURL
    }

    private func prepare(status: (@MainActor @Sendable (String) -> Void)?) async throws -> Paths {
        if let preparedPaths, pathsExist(preparedPaths) {
            return preparedPaths
        }

        guard let uv = firstExecutable([
            "/opt/homebrew/bin/uv",
            "/usr/local/bin/uv",
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin/uv").path
        ]) else {
            throw BackgroundRemovalError.modelUnavailable(
                "BEN2 needs uv to install its local runtime. Install uv with Homebrew, then try again."
            )
        }
        guard let script = Bundle.module.url(
            forResource: "background_removal_worker",
            withExtension: "py",
            subdirectory: "BackgroundRemoval"
        ) ?? Bundle.module.url(forResource: "background_removal_worker", withExtension: "py") else {
            throw BackgroundRemovalError.modelSetupFailed("The bundled background-removal worker script is missing.")
        }

        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Foundry/BackgroundRemoval", isDirectory: true)
        let models = root.appendingPathComponent("models", isDirectory: true)
        let modelURL = models.appendingPathComponent(BEN2Artifact.filename)
        let runtime = root.appendingPathComponent("runtime", isDirectory: true)
        let python = runtime.appendingPathComponent("bin/python")
        let marker = runtime.appendingPathComponent(".foundry-runtime-version")

        do {
            try FileManager.default.createDirectory(at: models, withIntermediateDirectories: true)
            if await isValidModel(at: modelURL) == false {
                try? FileManager.default.removeItem(at: modelURL)
                report("Downloading BEN2 (about 223 MB)...", status)
                try await downloadModel(to: modelURL)
            }
            if isRuntimeReady(python: python, marker: marker) == false {
                report("Installing local ONNX runtime...", status)
                try? FileManager.default.removeItem(at: runtime)
                try await run(uv: uv, arguments: ["venv", "--python", "3.13", runtime.path])
                try await run(
                    uv: uv,
                    arguments: [
                        "pip", "install", "--python", python.path,
                        "onnxruntime==1.24.2",
                        "numpy==2.5.1",
                        "Pillow==11.3.0"
                    ]
                )
                try Data(BEN2Artifact.runtimeMarker.utf8).write(to: marker, options: .atomic)
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as BackgroundRemovalError {
            throw error
        } catch {
            throw BackgroundRemovalError.modelSetupFailed(error.localizedDescription)
        }

        let paths = Paths(python: python, model: modelURL, script: script)
        preparedPaths = paths
        return paths
    }

    private func pathsExist(_ paths: Paths) -> Bool {
        FileManager.default.fileExists(atPath: paths.python.path)
            && FileManager.default.fileExists(atPath: paths.model.path)
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

    private func isRuntimeReady(python: URL, marker: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: python.path),
              let markerContents = try? String(contentsOf: marker, encoding: .utf8) else {
            return false
        }
        return markerContents == BEN2Artifact.runtimeMarker
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

    private func report(_ message: String, _ status: (@MainActor @Sendable (String) -> Void)?) {
        guard let status else { return }
        Task { @MainActor in status(message) }
    }

    private func firstExecutable(_ paths: [String]) -> String? {
        paths.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    private struct Paths: Sendable {
        let python: URL
        let model: URL
        let script: URL
    }
}

private enum BEN2Artifact {
    static let revision = "e48a20765fb421d19dcdb0bf3cc61e802ca5ec8f"
    static let filename = "ben2_base.onnx"
    static let byteSize: Int64 = 222_932_053
    static let sha256 = "22cea62108ff53b7ccc20f7a008bf30494228d84b1687f29ecbe76936a998101"
    static let runtimeMarker = "foundry-ben2-onnx-runtime-4"
    static let downloadURL = URL(string: "https://huggingface.co/PramaLLC/BEN2/resolve/\(revision)/BEN2_Base.onnx?download=true")!

    static func sha256(at url: URL) throws -> String {
        var digest = SHA256()
        let handle = try FileHandle(forReadingFrom: url)
        while let chunk = try handle.read(upToCount: 4 * 1024 * 1024), chunk.isEmpty == false {
            digest.update(data: chunk)
        }
        return digest.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
