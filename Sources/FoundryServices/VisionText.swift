import Foundation
import CoreGraphics
import ImageIO
import Vision

/// Lightweight Vision helpers shared by the OCR / barcode commands.
public enum VisionText {
    public static func recognizeText(in image: CGImage) async throws -> [String] {
        try await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            try handler.perform([request])
            return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
        }.value
    }

    public static func recognizeText(at url: URL) async throws -> [String] {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw FileConversionError.unavailable("Could not read image")
        }
        return try await recognizeText(in: image)
    }

    public static func readBarcodes(in image: CGImage) async throws -> [String] {
        try await Task.detached(priority: .userInitiated) {
            let request = VNDetectBarcodesRequest()
            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            try handler.perform([request])
            return (request.results ?? []).compactMap { $0.payloadStringValue }
        }.value
    }

    public static func readBarcodes(at url: URL) async throws -> [String] {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw FileConversionError.unavailable("Could not read image")
        }
        return try await readBarcodes(in: image)
    }
}
