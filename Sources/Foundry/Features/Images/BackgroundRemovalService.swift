import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers
import Vision
import FoundryServices

enum BEN2ComponentState: Equatable, Sendable { case missing, ready, invalid, unavailable(String) }
enum BEN2ProvisioningState: Equatable, Sendable { case available, unavailable(String) }
struct BEN2Assessment: Equatable, Sendable {
    let visionState: BEN2ComponentState
    let modelState: BEN2ComponentState
    let runtimeState: BEN2ComponentState
    let provisioningState: BEN2ProvisioningState
    let setupPlan: SetupPlan?
}

protocol BackgroundRemoving: Sendable {
    func supports(_ sourceURL: URL) -> Bool
    func removeBackground(from sourceURL: URL, destinationURL: URL?) async throws -> URL
    func removeBackground(
        from sourceURL: URL,
        destinationURL: URL?,
        status: (@MainActor @Sendable (String) -> Void)?
    ) async throws -> URL
}

extension BackgroundRemoving {
    func removeBackground(
        from sourceURL: URL,
        destinationURL: URL?,
        status _: (@MainActor @Sendable (String) -> Void)?
    ) async throws -> URL {
        try await removeBackground(from: sourceURL, destinationURL: destinationURL)
    }
}

enum BackgroundRemovalError: LocalizedError, Equatable {
    case unsupportedFile
    case animatedImage
    case unreadableImage
    case noForegroundFound
    case destinationNotWritable
    case modelUnavailable(String)
    case modelSetupFailed(String)
    case processingFailed(String)
    case setupRequired
    case unavailable(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedFile:
            "Background removal is available for still images only."
        case .animatedImage:
            "Animated images are not supported yet."
        case .unreadableImage:
            "Foundry could not read this image."
        case .noForegroundFound:
            "Foundry could not find a separable foreground in this image."
        case .destinationNotWritable:
            "Foundry could not save the result beside the original file."
        case let .modelUnavailable(message):
            message
        case let .modelSetupFailed(message):
            "Background-removal model setup failed: \(message)"
        case let .processingFailed(message):
            message
        case .setupRequired:
            "Set up BEN2 before processing images."
        case let .unavailable(message):
            message
        }
    }
}

struct VisionBackgroundRemovalService: BackgroundRemoving, Sendable {
    func supports(_ sourceURL: URL) -> Bool {
        BackgroundRemovalFileSupport.supportsStillImage(sourceURL)
    }

    func removeBackground(from sourceURL: URL, destinationURL: URL? = nil) async throws -> URL {
        try Task.checkCancellation()

        let cancellation = RequestCancellation()
        let work = Task.detached(priority: .userInitiated) {
            try Self.process(sourceURL: sourceURL, destinationURL: destinationURL, cancellation: cancellation)
        }

        do {
            let outputURL = try await withTaskCancellationHandler {
                try await work.value
            } onCancel: {
                cancellation.cancel()
                work.cancel()
            }
            do {
                try Task.checkCancellation()
            } catch {
                try? FileManager.default.removeItem(at: outputURL)
                throw error
            }
            return outputURL
        } catch {
            work.cancel()
            throw error
        }
    }

    static func destinationURL(for sourceURL: URL, preferredURL: URL? = nil) -> URL {
        BackgroundRemovalFileSupport.destinationURL(for: sourceURL, preferredURL: preferredURL)
    }

    private static func process(
        sourceURL: URL,
        destinationURL preferredDestination: URL?,
        cancellation: RequestCancellation
    ) throws -> URL {
        try Task.checkCancellation()
        if cancellation.isCancelled { throw CancellationError() }

        guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil) else {
            throw BackgroundRemovalError.unreadableImage
        }
        guard CGImageSourceGetCount(source) == 1 else {
            throw BackgroundRemovalError.animatedImage
        }
        guard let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw BackgroundRemovalError.unreadableImage
        }

        let outputURL = destinationURL(
            for: sourceURL,
            preferredURL: preferredDestination
        )
        let folder = outputURL.deletingLastPathComponent()
        guard FileManager.default.fileExists(atPath: folder.path) else {
            throw BackgroundRemovalError.destinationNotWritable
        }

        let orientation = imageOrientation(source)
        let request = VNGenerateForegroundInstanceMaskRequest()
        request.preferBackgroundProcessing = true
        cancellation.register(request)
        defer { cancellation.clear() }
        let handler = VNImageRequestHandler(cgImage: image, orientation: orientation, options: [:])

        do {
            try handler.perform([request])
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            if cancellation.isCancelled || Task.isCancelled {
                throw CancellationError()
            }
            throw BackgroundRemovalError.processingFailed(error.localizedDescription)
        }

        try Task.checkCancellation()
        if cancellation.isCancelled { throw CancellationError() }

        guard let observation = request.results?.first else {
            throw BackgroundRemovalError.noForegroundFound
        }
        guard observation.allInstances.isEmpty == false else {
            throw BackgroundRemovalError.noForegroundFound
        }

        let maskedImage: CVPixelBuffer
        do {
            maskedImage = try observation.generateMaskedImage(
                ofInstances: observation.allInstances,
                from: handler,
                croppedToInstancesExtent: false
            )
        } catch {
            if cancellation.isCancelled || Task.isCancelled {
                throw CancellationError()
            }
            throw BackgroundRemovalError.processingFailed(error.localizedDescription)
        }

        let temporaryURL = folder.appendingPathComponent(".foundry-background-removal-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: temporaryURL) }

        do {
            try writePNG(maskedImage, to: temporaryURL)
            try Task.checkCancellation()
            try FileManager.default.moveItem(at: temporaryURL, to: outputURL)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as BackgroundRemovalError {
            throw error
        } catch {
            throw mapWriteError(error)
        }

        return outputURL
    }

    private static func writePNG(_ pixelBuffer: CVPixelBuffer, to url: URL) throws {
        let image = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext()
        guard let outputImage = context.createCGImage(image, from: image.extent) else {
            throw BackgroundRemovalError.processingFailed("Foundry could not encode the transparent image.")
        }
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw BackgroundRemovalError.destinationNotWritable
        }

        CGImageDestinationAddImage(
            destination,
            outputImage,
            [kCGImagePropertyOrientation: 1] as CFDictionary
        )
        guard CGImageDestinationFinalize(destination) else {
            throw BackgroundRemovalError.destinationNotWritable
        }
    }

    private static func imageOrientation(_ source: CGImageSource) -> CGImagePropertyOrientation {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let value = properties[kCGImagePropertyOrientation] as? NSNumber,
              let orientation = CGImagePropertyOrientation(rawValue: value.uint32Value) else {
            return .up
        }
        return orientation
    }

    private static func mapWriteError(_ error: Error) -> Error {
        let cocoaError = error as NSError
        let writeErrors: Set<Int> = [
            NSFileWriteNoPermissionError,
            NSFileWriteVolumeReadOnlyError,
            NSFileWriteOutOfSpaceError,
            NSFileWriteInvalidFileNameError
        ]
        if cocoaError.domain == NSCocoaErrorDomain, writeErrors.contains(cocoaError.code) {
            return BackgroundRemovalError.destinationNotWritable
        }
        return BackgroundRemovalError.processingFailed(error.localizedDescription)
    }
}

enum BackgroundRemovalFileSupport {
    static func supportsStillImage(_ sourceURL: URL) -> Bool {
        guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil) else { return false }
        guard CGImageSourceGetCount(source) == 1 else { return false }
        guard let type = CGImageSourceGetType(source), let contentType = UTType(type as String) else { return false }
        return contentType.conforms(to: .image)
    }

    static func destinationURL(
        for sourceURL: URL,
        preferredURL: URL? = nil,
        defaultStemSuffix: String = " - background removed"
    ) -> URL {
        let folder = preferredURL?.deletingLastPathComponent() ?? sourceURL.deletingLastPathComponent()
        let stem = preferredURL.map { $0.deletingPathExtension().lastPathComponent }
            ?? "\(sourceURL.deletingPathExtension().lastPathComponent)\(defaultStemSuffix)"
        return uniqueURL(folder: folder, stem: stem, pathExtension: "png")
    }

    static func uniqueURL(folder: URL, stem: String, pathExtension: String) -> URL {
        let baseName = stem.isEmpty ? "background-removed" : stem
        var index = 1
        while true {
            let suffix = index == 1 ? "" : " \(index)"
            let candidate = folder.appendingPathComponent("\(baseName)\(suffix).\(pathExtension)")
            if FileManager.default.fileExists(atPath: candidate.path) == false {
                return candidate
            }
            index += 1
        }
    }
}

private final class RequestCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var request: VNRequest?
    private var cancelled = false

    var isCancelled: Bool {
        lock.withLock { cancelled }
    }

    func register(_ request: VNRequest) {
        let shouldCancel = lock.withLock {
            self.request = request
            return cancelled
        }
        if shouldCancel { request.cancel() }
    }

    func cancel() {
        let request = lock.withLock {
            cancelled = true
            return self.request
        }
        request?.cancel()
    }

    func clear() {
        lock.withLock { request = nil }
    }
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
