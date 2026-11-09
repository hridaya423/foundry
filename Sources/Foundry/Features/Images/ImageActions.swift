import AppKit
import CoreImage
import Foundation
import FoundryDomain
import FoundryServices
import UniformTypeIdentifiers
import os

private final class SamplerBox: Sendable {
    // NSColorSampler is not Sendable on this SDK; the lock-box vouches for
    // the single hop across the continuation boundary in pickColor.
    let value = OSAllocatedUnfairLock<NSColorSampler?>(uncheckedState: nil)

    init(_ value: NSColorSampler) { self.value.withLockUnchecked { $0 = value } }
}

@MainActor private func pickImageFile(title: String) -> URL? {
    let panel = NSOpenPanel()
    panel.title = title
    panel.allowedContentTypes = [.image]
    panel.allowsMultipleSelection = false
    panel.canChooseDirectories = false
    return panel.runModal() == .OK ? panel.url : nil
}

private func stageTextPreview(_ text: String, named name: String) throws -> URL {
    let staging = FileManager.default.temporaryDirectory.appendingPathComponent("FoundryOCR", isDirectory: true)
    try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
    let preview = staging.appendingPathComponent("\(name).txt")
    try text.write(to: preview, atomically: true, encoding: .utf8)
    return preview
}

/// Stage extracted/decoded text as a temp file and present it via Quick
/// Look (or open it when no panel is wired). Returns false when empty.
@MainActor private func presentExtractedText(_ lines: [String], sourceName: String, suffix: String, onQuickLook: (@MainActor (URL) -> Void)?) throws -> Bool {
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

private func cgImage(from data: Data) -> CGImage? {
    NSImage(data: data)?.cgImage(forProposedRect: nil, context: nil, hints: nil)
}

/// Clipboard/shelf image entry points — Vision OCR or barcode decode staged
/// to a temp file and shown via Quick Look. These aren't panel actions; the
/// clipboard history and file shelf call them directly.
enum TextPreview {
    /// OCR a clipboard image payload → stage → Quick Look. Returns false when
    /// no text is found.
    @MainActor
    static func extractText(fromImageData data: Data, sourceName: String = "Clipboard image", onQuickLook: (@MainActor (URL) -> Void)?) async throws -> Bool {
        guard let image = cgImage(from: data) else { throw FileConversionError.unavailable("Could not decode image data") }
        let lines = try await VisionText.recognizeText(in: image)
        return try presentExtractedText(lines, sourceName: sourceName, suffix: "OCR", onQuickLook: onQuickLook)
    }

    /// Barcode/QR decode of a clipboard image payload → stage → Quick Look.
    @MainActor
    static func decodeBarcode(fromImageData data: Data, sourceName: String = "Clipboard image", onQuickLook: (@MainActor (URL) -> Void)?) async throws -> Bool {
        guard let image = cgImage(from: data) else { throw FileConversionError.unavailable("Could not decode image data") }
        let lines = try await VisionText.readBarcodes(in: image)
        return try presentExtractedText(lines, sourceName: sourceName, suffix: "Barcode", onQuickLook: onQuickLook)
    }

    /// Barcode/QR decode of an image file → stage → Quick Look (File Shelf).
    @MainActor
    static func decodeBarcode(at url: URL, onQuickLook: (@MainActor (URL) -> Void)?) async throws -> Bool {
        let lines = try await VisionText.readBarcodes(at: url)
        return try presentExtractedText(lines, sourceName: url.deletingPathExtension().lastPathComponent, suffix: "Barcode", onQuickLook: onQuickLook)
    }

    /// OCR of an image file → stage → Quick Look (File Shelf).
    @MainActor
    static func extractText(at url: URL, onQuickLook: (@MainActor (URL) -> Void)?) async throws -> Bool {
        let lines = try await VisionText.recognizeText(at: url)
        return try presentExtractedText(lines, sourceName: url.deletingPathExtension().lastPathComponent, suffix: "OCR", onQuickLook: onQuickLook)
    }
}

struct ExtractTextFromImageAction: ResultAction, Equatable {
    let paths: [String]

    init(path: String? = nil) { paths = path.map { [$0] } ?? [] }
    init(paths: [String]) { self.paths = paths }

    var icon: String? { "text.viewfinder" }

    func perform(_ ctx: ActionContext) async -> CommandOutcome {
        let urls = paths.isEmpty ? pickImageFile(title: "Extract Text from Image").map { [$0] } : paths.map { URL(fileURLWithPath: $0) }
        guard let urls, urls.isEmpty == false else { return .cancelled }
        do {
            ctx.emit(.status("Recognizing text…"))
            var sections: [String] = []
            for url in urls {
                let text = try await VisionText.recognizeText(at: url).joined(separator: "\n")
                guard text.isEmpty == false else { continue }
                sections.append(urls.count > 1 ? url.lastPathComponent + "\n" + text : text)
            }
            guard sections.isEmpty == false else {
                let name = urls.count == 1 ? urls[0].lastPathComponent : String(localized: "those images")
                return .failure(message: String(localized: "No text found in \(name)"), retryable: false)
            }
            let text = sections.joined(separator: "\n\n")
            ctx.pasteboard.clearContents()
            ctx.pasteboard.setString(text, forType: .string)
            ctx.diagnostics.log("OCR extracted text from \(sections.count) of \(urls.count) images")
            return .copied(content: text)
        } catch {
            ctx.diagnostics.log("OCR failed: \(error.localizedDescription)")
            return .failure(message: String(localized: "Could not extract text"), retryable: true)
        }
    }
}

struct PreviewExtractedTextAction: ResultAction, Equatable {
    let path: String

    var icon: String? { "eye" }

    func perform(_ ctx: ActionContext) async -> CommandOutcome {
        let url = URL(fileURLWithPath: path)
        do {
            ctx.emit(.status("Recognizing text…"))
            let lines = try await VisionText.recognizeText(at: url)
            guard try presentExtractedText(lines, sourceName: url.deletingPathExtension().lastPathComponent, suffix: "OCR",
                onQuickLook: ctx.panel.onQuickLook) else {
                return .failure(message: String(localized: "No text found in \(url.lastPathComponent)"), retryable: false)
            }
            return ctx.panel.onQuickLook == nil ? .success(message: nil) : .stayOpen(message: nil)
        } catch {
            ctx.diagnostics.log("OCR preview failed: \(error.localizedDescription)")
            return .failure(message: String(localized: "Could not extract text"), retryable: true)
        }
    }
}

struct PickColorAction: ResultAction, Equatable {
    var icon: String? { "eyedropper.halffull" }

    func perform(_ ctx: ActionContext) async -> CommandOutcome {
        let color: NSColor? = await withCheckedContinuation { continuation in
            let sampler = SamplerBox(NSColorSampler())
            sampler.value.withLockUnchecked { value in
                value?.show { color in
                    continuation.resume(returning: color)
                    withExtendedLifetime(sampler) {}
                }
            }
        }
        guard let color else { return .cancelled }
        let hex = Self.hexString(for: color)
        recordRecentColor(hex, in: ctx)
        let formats = Self.colorFormats(for: color)
        let recents = ctx.localState.get(\.colorPickerRecents)
        if let chosen = await chooseColorFormat(hex: hex, color: color, formats: formats, recents: recents, ctx: ctx) {
            ctx.pasteboard.clearContents()
            ctx.pasteboard.setString(chosen, forType: .string)
            ctx.emit(.feedback(.success("Copied \(chosen)")))
            return .copied(content: chosen)
        }
        ctx.pasteboard.clearContents()
        ctx.pasteboard.setString(hex, forType: .string)
        ctx.emit(.feedback(.success("Copied \(hex)")))
        return .copied(content: hex)
    }

    private func recordRecentColor(_ hex: String, in ctx: ActionContext) {
        ctx.localState.update { state in
            var recents = state.colorPickerRecents.filter { $0 != hex }
            recents.insert(hex, at: 0)
            state.colorPickerRecents = Array(recents.prefix(12))
        }
    }

    /// Format + recent-colors picker shown after the sampler. Returns the
    /// string to copy, or nil to fall back to hex.
    @MainActor private func chooseColorFormat(
        hex: String,
        color: NSColor,
        formats: [(label: String, value: String)],
        recents: [String],
        ctx: ActionContext
    ) async -> String? {
        let swatch = NSImage(size: NSSize(width: 40, height: 24), flipped: false) { rect in
            color.setFill()
            NSBezierPath(roundedRect: rect, xRadius: 5, yRadius: 5).fill()
            return true
        }
        let recentOptions = Array(recents.prefix(4))
        let prompt = await ctx.panel.requestPrompt(PanelPromptSpec(
            title: LocalizedStringResource("\(hex)"),
            message: "Pick a format to copy.\n\(Self.contrastSummary(for: color))",
            picker: PanelPromptSpec.Picker(
                id: "format",
                options: (formats.map(\.label) + recentOptions).map { LocalizedStringResource("\($0)") },
                selected: 0
            ),
            image: swatch,
            confirmLabel: "Copy"
        ))
        guard prompt.confirmed else { return nil }
        let index = prompt.selection
        if formats.indices.contains(index) { return formats[index].value }
        let recentIndex = index - formats.count
        guard recentOptions.indices.contains(recentIndex) else { return nil }
        return recentOptions[recentIndex]
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
            ("NSColor", String(format: "NSColor(red: %.3f, green: %.3f, blue: %.3f, alpha: %.3f)", rgb.redComponent, rgb.greenComponent,
                rgb.blueComponent, alpha)),
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

    nonisolated private static func hexString(for color: NSColor) -> String {
        guard let rgb = color.usingColorSpace(.sRGB) else { return "#000000" }
        let r = Int((rgb.redComponent * 255).rounded())
        let g = Int((rgb.greenComponent * 255).rounded())
        let b = Int((rgb.blueComponent * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}

struct GenerateQRCodeAction: ResultAction, Equatable {
    var icon: String? { "qrcode" }

    func perform(_ ctx: ActionContext) async -> CommandOutcome {
        guard let content = ctx.pasteboard.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines), content.isEmpty == false else {
            return .failure(message: String(localized: "Clipboard has no text to encode"), retryable: false)
        }
        guard let image = qrImage(for: content) else {
            return .failure(message: String(localized: "Could not generate QR code"), retryable: false)
        }
        ctx.pasteboard.clearContents()
        ctx.pasteboard.writeObjects([image])
        ctx.diagnostics.log("Generated QR code for \(content.count) characters")
        await Self.presentSaveOffer(image, content: content, ctx: ctx)
        ctx.emit(.feedback(.success("QR code copied to clipboard")))
        return .copied(content: content)
    }

    /// "Copied — save a PNG?" offer after QR generation. Resolves through
    /// the panel prompt: under tests the default port declines, so modal
    /// UI never runs.
    @MainActor static func presentSaveOffer(_ image: NSImage, content: String, ctx: ActionContext) async {
        let preview = content.count > 120 ? String(content.prefix(120)) + "…" : content
        let offer = await ctx.panel.requestPrompt(PanelPromptSpec(
            title: "QR code copied to clipboard",
            message: "\(preview)",
            confirmLabel: "Save as PNG…",
            cancelLabel: "Done"
        ))
        guard offer.confirmed else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "QR Code.png"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let destination = panel.url,
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else { return }
        do {
            try png.write(to: destination)
        } catch {
            _ = await ctx.panel.requestPrompt(PanelPromptSpec(
                title: "Couldn't save the QR code",
                message: "\(error.localizedDescription)",
                confirmLabel: "OK",
                cancelLabel: nil
            ))
        }
    }
}

@MainActor private let qrContext = CIContext()

@MainActor
private func qrImage(for content: String) -> NSImage? {
    guard let data = content.data(using: .utf8),
          let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
    filter.setValue(data, forKey: "inputMessage")
    filter.setValue("M", forKey: "inputCorrectionLevel")
    guard let output = filter.outputImage else { return nil }
    let scaled = output.transformed(by: CGAffineTransform(scaleX: 12, y: 12))
    guard let cgImage = qrContext.createCGImage(scaled, from: scaled.extent) else { return nil }
    return NSImage(cgImage: cgImage, size: NSSize(width: scaled.extent.width, height: scaled.extent.height))
}

func wifiQRPayload(ssid: String, password: String, security: Int) -> String {
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

struct GenerateWiFiQRCodeAction: ResultAction, Equatable {
    var icon: String? { "wifi" }

    func perform(_ ctx: ActionContext) async -> CommandOutcome {
        let prompt = await ctx.panel.requestPrompt(PanelPromptSpec(
            title: "Wi-Fi QR Code",
            message: "Guests scan the code to join the network.",
            fields: [
                PanelPromptSpec.Field(id: "ssid", placeholder: "Network name (SSID)"),
                PanelPromptSpec.Field(id: "password", placeholder: "Password", isSecure: true),
            ],
            picker: PanelPromptSpec.Picker(
                id: "security",
                options: ["WPA / WPA2 / WPA3", "WEP", "Open network"],
                selected: 0
            ),
            confirmLabel: "Generate"
        ))
        guard prompt.confirmed else { return .cancelled }
        let network = (prompt.texts.first ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard network.isEmpty == false else {
            return .failure(message: String(localized: "Enter a network name"), retryable: true)
        }
        let payload = wifiQRPayload(ssid: network, password: prompt.texts.dropFirst().first ?? "", security: prompt.selection)
        guard let image = qrImage(for: payload) else {
            return .failure(message: String(localized: "Could not generate QR code"), retryable: false)
        }
        ctx.pasteboard.clearContents()
        ctx.pasteboard.writeObjects([image])
        ctx.emit(.feedback(.success("Wi-Fi QR code copied to clipboard")))
        return .copied(content: payload)
    }
}

struct ReadQRCodeAction: ResultAction, Equatable {
    var icon: String? { "qrcode.viewfinder" }

    func perform(_ ctx: ActionContext) async -> CommandOutcome {
        guard let url = pickImageFile(title: "Read QR Code") else { return .cancelled }
        do {
            ctx.emit(.status("Scanning image…"))
            let payloads = try await VisionText.readBarcodes(at: url)
            guard let payload = payloads.first else {
                return .failure(message: String(localized: "No QR code found in \(url.lastPathComponent)"), retryable: false)
            }
            ctx.pasteboard.clearContents()
            ctx.pasteboard.setString(payload, forType: .string)
            ctx.diagnostics.log("Decoded QR payload (\(payload.count) characters)")
            ctx.emit(.feedback(.success("Copied \(payload)")))
            return .copied(content: payload)
        } catch {
            ctx.diagnostics.log("QR decode failed: \(error.localizedDescription)")
            return ctx.finish(.failure(message: String(localized: "Could not read QR code"), retryable: true))
        }
    }
}

struct RecognizeScreenTextAction: ResultAction, Equatable {
    var icon: String? { "text.viewfinder" }

    func perform(_ ctx: ActionContext) async -> CommandOutcome {
        guard await ctx.panel.canCaptureScreen() else {
            let answer = await ctx.panel.requestPrompt(PanelPromptSpec(
                title: "Allow Screen Recording to read text from the screen.",
                message: "macOS asks once. Come back and run this again after you allow it.",
                confirmLabel: "Allow",
                cancelLabel: "Not Now"))
            if answer.confirmed { await ctx.panel.requestPermission(.screenRecording) }
            return .cancelled
        }
        ctx.emit(.status("Select a region…"))
        let temporary = FileManager.default.temporaryDirectory
            .appendingPathComponent("foundry-screen-ocr-\(UUID().uuidString).png")
        do {
            _ = try await ProcessRunner.run(path: "/usr/sbin/screencapture", arguments: ["-i", "-x", temporary.path], timeout: 120)
        } catch {
            return .failure(message: String(localized: "Could not capture the screen"), retryable: true)
        }
        defer { try? FileManager.default.removeItem(at: temporary) }
        guard FileManager.default.fileExists(atPath: temporary.path) else { return .cancelled }
        do {
            ctx.emit(.status("Recognizing text…"))
            let lines = try await VisionText.recognizeText(at: temporary)
            let text = lines.joined(separator: "\n")
            guard text.isEmpty == false else {
                return .failure(message: String(localized: "No text found in the captured region"), retryable: false)
            }
            ctx.pasteboard.clearContents()
            ctx.pasteboard.setString(text, forType: .string)
            ctx.diagnostics.log("Screen OCR captured \(lines.count) line(s)")
            ctx.emit(.feedback(.success("Copied \(lines.count) line(s) of text")))
            return .copied(content: text)
        } catch {
            ctx.diagnostics.log("Screen OCR failed: \(error.localizedDescription)")
            return ctx.finish(.failure(message: String(localized: "Could not extract text"), retryable: true))
        }
    }
}
