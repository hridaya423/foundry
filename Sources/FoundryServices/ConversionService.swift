import AppKit
import AVFoundation
import Foundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers
import Vision

public enum FileConversionError: Error { case unavailable(String), cancelled }

public struct FileConversionTarget: Identifiable, Hashable, Sendable {
    public enum Category: String, Hashable, CaseIterable, Sendable {
        case photo = "Photo"
        case icon = "Icon"
        case document = "Document"
        case pdf = "PDF"
        case data = "Data"
        case archive = "Archive"
        case music = "Music"
        case video = "Video"
    }

    public let id: String
    public let title: String
    public let outputExtension: String
    public let category: Category
    /// Preferred route for the representative source; per-file routes are
    /// re-resolved at convert time since shared targets may route differently.
    public let route: ConversionRoute

    public init(id: String, title: String, outputExtension: String, category: Category, route: ConversionRoute) {
        self.id = id
        self.title = title
        self.outputExtension = outputExtension
        self.category = category
        self.route = route
    }

    /// Convenience for tests/fixtures: single-edge route via a specific engine.
    public init(id: String, title: String, outputExtension: String, category: Category, engine: ConversionEngine) {
        self.init(id: id, title: title, outputExtension: outputExtension, category: category,
                  route: ConversionRoute(edges: [ConversionEdge(input: "*", output: outputExtension, engine: engine)]))
    }

    public var engines: [ConversionEngine] { route.engines }
    public var engineSummary: String { route.engineSummary }
    /// Engines needing an on-disk tool (used by capability assessment).
    public var externalEngines: [ConversionEngine] { route.engines.filter { $0.isNative == false } }
}

/// Which `ConversionOptions` fields actually affect this target's output —
/// drives which controls the UI shows.
public enum ConversionOptionKind: Hashable, Sendable, CaseIterable {
    case quality, maxPixelSize, dpiAndPages, audioBitrate
}

extension FileConversionTarget {
    public var applicableOptions: Set<ConversionOptionKind> {
        var kinds = Set<ConversionOptionKind>()
        if FileConversionService.lossyImageExts.contains(outputExtension) {
            kinds.insert(.quality)
        }
        let rasterWrites = ConversionGraph.imageWriteExts.union(ConversionGraph.magickWriteExts).subtracting(["pdf"])
        if rasterWrites.contains(outputExtension),
           let producer = route.producingEngine, [.imageIO, .imageMagick].contains(producer) {
            kinds.insert(.maxPixelSize)
        }
        if route.engines.contains(.pdfKit) {
            kinds.insert(.dpiAndPages)
        }
        if ConversionGraph.audioExts.contains(outputExtension), route.engines.contains(.ffmpeg) {
            kinds.insert(.audioBitrate)
        }
        return kinds
    }
}

public enum FileConversionService {

    // MARK: - Target discovery

    public static func availableTargets(for url: URL) -> [FileConversionTarget] {
        let ext = ConversionGraph.normalizedExtension(of: url)
        var routes = ConversionGraph.routes(from: ext)
        // "Extract" is only meaningful when the input itself is an archive —
        // the multi-hop chain file→zip→extract is legal but useless.
        if ConversionGraph.archiveExtractExts.contains(ext) == false {
            routes.removeValue(forKey: ConversionGraph.extractExt)
        }
        var targets = routes.map { outExt, route in
            FileConversionTarget(
                id: outExt,
                title: title(for: outExt),
                outputExtension: outExt,
                category: category(for: outExt),
                route: route
            )
        }
        // Icon outputs only make sense for roughly-square, reasonably-sized art.
        if let meta = imageMetadata(for: url), meta.isIconCandidate == false {
            targets.removeAll { $0.category == .icon }
        }
        return sortTargets(targets)
    }

    public static func defaultTargetID(for url: URL, in targets: [FileConversionTarget]) -> String? {
        let ext = ConversionGraph.normalizedExtension(of: url)
        let preferred: String?
        switch ext {
        case "png": preferred = "jpg"
        case "jpg", "jpeg", "heic", "heif", "heics", "tif", "tiff", "bmp", "webp", "avif", "jp2", "svg",
             "dng", "cr2", "cr3", "nef", "arw", "orf", "rw2", "raf", "pef", "srw": preferred = "png"
        case "pdf": preferred = "png"
        case "doc", "docx", "odt", "rtf", "wordml", "html", "htm", "md", "markdown", "txt": preferred = "pdf"
        case "csv", "tsv": preferred = "json"
        case "json": preferred = "csv"
        case "plist": preferred = "json"
        case "zip", "tar", "gz", "tgz", "bz2", "tbz2", "xz", "txz", "tar.gz", "tar.bz2", "tar.xz":
            preferred = ConversionGraph.extractExt
        case "srt", "vtt", "ass", "ssa": preferred = "srt"
        default:
            if ConversionGraph.audioExts.contains(ext) { preferred = "mp3" }
            else if ConversionGraph.videoExts.contains(ext) { preferred = "mp4" }
            else { preferred = nil }
        }
        if let preferred, let match = targets.first(where: { $0.id == preferred }) {
            return match.id
        }
        return targets.first?.id
    }

    // MARK: - Capability assessment

    public static func assess(_ target: FileConversionTarget) async -> CapabilityState {
        await assess(target, locator: ExecutableLocator(), environment: ProcessInfo.processInfo.environment)
    }

    public static func assess(_ target: FileConversionTarget, locator: ExecutableLocator, environment: [String: String]) async -> CapabilityState {
        await assess(engines: target.route.engines, locator: locator, environment: environment)
    }

    /// Union assessment across several input extensions — used when the same
    /// output target is shared by differently-routed sources.
    public static func assess(target outputExt: String, forInputExts inputExts: [String], locator: ExecutableLocator = ExecutableLocator(), environment: [String: String] = ProcessInfo.processInfo.environment) async -> CapabilityState {
        var engines: [ConversionEngine] = []
        for ext in inputExts {
            guard let route = ConversionGraph.route(from: ext, to: outputExt) else { continue }
            for engine in route.engines where !engines.contains(engine) { engines.append(engine) }
        }
        return await assess(engines: engines, locator: locator, environment: environment)
    }

    private static func assess(engines: [ConversionEngine], locator: ExecutableLocator, environment: [String: String]) async -> CapabilityState {
        var missing: [ConversionEngine] = []
        var unavailableReason: String?
        let assessor = CapabilityAssessor(locator: locator, versionProbe: VersionProbe(), environment: environment)
        for engine in engines where engine.isNative == false {
            guard let exec = engine.executableName else { continue }
            let requirement = try? CapabilityRequirement(executableName: exec, explicitPaths: engine.candidatePaths)
            guard let requirement else { return .unavailable("Missing dependency: \(engine.displayName)") }
            let state = (try? await assessor.assess(requirement)) ?? .unavailable("Capability assessment failed")
            switch state {
            case .ready: break
            case .setupRequired: missing.append(engine)
            case .unavailable(let reason): unavailableReason = "\(engine.displayName): \(reason)"
            case .degraded(let reason): unavailableReason = "\(engine.displayName): \(reason)"
            }
        }
        if let unavailableReason { return .unavailable(unavailableReason) }
        guard missing.isEmpty == false else { return .ready }
        guard let brew = try? locator.locate(name: "brew", candidates: ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"], environment: environment) else {
            let names = missing.map(\.displayName).joined(separator: ", ")
            return .unavailable("Homebrew is required to install \(names)")
        }
        return .setupRequired(setupPlan(for: missing, homebrewPath: brew.path))
    }

    private static func setupPlan(for engines: [ConversionEngine], homebrewPath: String) -> SetupPlan {
        var commands: [ExactCommand] = []
        var seen = Set<String>()
        for engine in engines {
            if let formula = engine.brewFormula, seen.insert(formula).inserted {
                commands.append(ExactCommand(executable: homebrewPath, arguments: ["install", formula]))
            }
            if let cask = engine.brewCask, seen.insert(cask).inserted {
                commands.append(ExactCommand(executable: homebrewPath, arguments: ["install", "--cask", cask]))
            }
        }
        let names = engines.map(\.displayName).joined(separator: ", ")
        return SetupPlan(
            commands: commands,
            artifacts: [],
            mutationScope: "Homebrew installs the required tools for this user",
            cleanupOwnership: "Homebrew owns the installed packages",
            disclosure: "Installing \(names) requires network access to Homebrew; disk impact varies by package."
        )
    }

    public static func missingDependencyName(for target: FileConversionTarget) -> String? {
        target.externalEngines.map(\.displayName).first
    }

    // MARK: - Conversion

    public static func convert(sourceURL: URL, target: FileConversionTarget, outputFolderURL: URL, options: ConversionOptions = .standard) async -> Result<URL, Error> {
        do {
            try Task.checkCancellation()
            let inputExt = ConversionGraph.normalizedExtension(of: sourceURL)

            // Re-resolve the route for this file's actual extension — shared
            // targets carry the route of whichever source produced them.
            let route: ConversionRoute
            if let first = target.route.edges.first,
               (first.input == inputExt || first.input == "*"),
               target.route.edges.last?.output == target.outputExtension {
                route = target.route
            } else if let resolved = ConversionGraph.route(from: inputExt, to: target.outputExtension) {
                route = resolved
            } else {
                throw FileConversionError.unavailable("No route from \(inputExt) to \(target.outputExtension)")
            }

            try FileManager.default.createDirectory(at: outputFolderURL, withIntermediateDirectories: true)

            if target.outputExtension == ConversionGraph.extractExt {
                let destination = try await extractArchive(sourceURL: sourceURL, into: outputFolderURL)
                return .success(destination)
            }

            let destination = uniqueDestination(for: sourceURL, ext: target.outputExtension, in: outputFolderURL)
            let artifactStore = ArtifactStore()
            let staged = try artifactStore.stage(for: destination)
            defer { artifactStore.discard(staged) }

            if route.hopCount == 1 {
                try await execute(edge: route.edges[0], input: sourceURL, output: staged.url, options: options)
            } else {
                try await executeMultiHop(route: route, source: sourceURL, staged: staged.url, options: options)
            }

            let committed = try artifactStore.commit(staged) { url in
                (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue ?? 0 > 0
            }
            return .success(committed)
        } catch {
            return .failure(error)
        }
    }

    /// Runs a multi-hop route through a private temp directory; the last hop
    /// writes into the staged artifact which convert() then commits.
    private static func executeMultiHop(route: ConversionRoute, source: URL, staged: URL, options: ConversionOptions) async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("Foundry-Conversion-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        var current = source
        for (index, edge) in route.edges.enumerated() {
            try Task.checkCancellation()
            let isLast = index == route.edges.count - 1
            let output = isLast
                ? staged
                : tempDir.appendingPathComponent("hop\(index).\(edge.output)")
            try await execute(edge: edge, input: current, output: output, options: options)
            guard FileManager.default.fileExists(atPath: output.path) else {
                throw FileConversionError.unavailable("\(edge.engine.displayName) produced no output")
            }
            current = output
        }
    }

    // MARK: - Edge executors

    private static func execute(edge: ConversionEdge, input: URL, output: URL, options: ConversionOptions) async throws {
        switch edge.engine {
        case .imageIO: try convertImageIO(input: input, output: output, ext: edge.output, options: options)
        case .textutil: try await run("/usr/bin/textutil", ["-convert", edge.output, "-output", output.path, input.path])
        case .avFoundation: try await convertAVFoundation(input: input, output: output, ext: edge.output, options: options)
        case .pdfKit: try convertPDFToImage(input: input, output: output, ext: edge.output, options: options)
        case .plutil: try await run("/usr/bin/plutil", ["-convert", edge.output == "json" ? "json" : "xml1", "-o", output.path, input.path])
        case .structuredData: try convertStructured(input: input, output: output, from: edge.input, to: edge.output)
        case .archive: try await convertArchive(input: input, output: output, ext: edge.output)
        case .vision: try await convertVisionOCR(input: input, output: output)
        case .ffmpeg: try await convertFFmpeg(input: input, output: output, ext: edge.output, options: options)
        case .imageMagick: try await convertImageMagick(input: input, output: output, ext: edge.output, options: options)
        case .pandoc: try await convertPandoc(input: input, output: output, ext: edge.output)
        case .soffice: try await convertSoffice(input: input, output: output, ext: edge.output)
        }
    }

    /// ImageIO edge — in-process, honors quality + maxPixelSize.
    private static func convertImageIO(input: URL, output: URL, ext: String, options: ConversionOptions) throws {
        guard let source = CGImageSourceCreateWithURL(input as CFURL, nil) else {
            throw FileConversionError.unavailable("Could not read image")
        }
        let uti = imageUTI(for: ext)
        guard let destination = CGImageDestinationCreateWithURL(output as CFURL, uti as CFString, 1, nil) else {
            throw FileConversionError.unavailable("ImageIO cannot write \(ext.uppercased())")
        }
        var props: [CFString: Any] = [:]
        if let quality = options.quality, lossyImageExts.contains(ext) {
            props[kCGImageDestinationLossyCompressionQuality] = quality
        }
        if let maxPixel = options.maxPixelSize {
            props[kCGImageDestinationImageMaxPixelSize] = maxPixel
        }
        CGImageDestinationAddImageFromSource(destination, source, 0, props as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw FileConversionError.unavailable("Image conversion failed")
        }
    }

    private static func imageUTI(for ext: String) -> String {
        switch ext {
        case "jpg", "jpeg": return UTType.jpeg.identifier
        case "tif", "tiff": return UTType.tiff.identifier
        case "jp2": return "public.jpeg-2000"
        default:
            return UTType(filenameExtension: ext)?.identifier ?? "public.\(ext)"
        }
    }

    static let lossyImageExts: Set<String> = ["jpg", "jpeg", "heic", "jp2", "avif", "webp"]

    /// AVFoundation edge — mov/m4v→mp4 passthrough when codecs allow, else
    /// re-encode; audio extraction via AppleM4A preset.
    private static func convertAVFoundation(input: URL, output: URL, ext: String, options: ConversionOptions) async throws {
        let asset = AVURLAsset(url: input)
        let presets: [String]
        if ext == "m4a" {
            presets = [AVAssetExportPresetAppleM4A]
        } else {
            // Passthrough is a fast lossless remux; fall back to re-encode.
            presets = ["mp4", "mov", "m4v"].contains(ConversionGraph.normalizedExtension(of: input))
                ? [AVAssetExportPresetPassthrough, AVAssetExportPresetHighestQuality]
                : [AVAssetExportPresetHighestQuality]
        }
        var lastError: Error = FileConversionError.unavailable("Export failed")
        for preset in presets {
            guard let session = AVAssetExportSession(asset: asset, presetName: preset) else { continue }
            // AVAssetExportSession is not Sendable; cancelExport is documented
            // thread-safe and the completion handler is where we read status.
            nonisolated(unsafe) let sessionRef = session
            session.outputURL = output
            session.outputFileType = ext == "m4a" ? .m4a : .mp4
            session.shouldOptimizeForNetworkUse = true
            do {
                try await withTaskCancellationHandler {
                    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                        sessionRef.exportAsynchronously {
                            switch sessionRef.status {
                            case .completed: continuation.resume()
                            case .cancelled: continuation.resume(throwing: CancellationError())
                            default: continuation.resume(throwing: sessionRef.error ?? FileConversionError.unavailable("Export failed"))
                            }
                        }
                    }
                } onCancel: {
                    sessionRef.cancelExport()
                }
                return
            } catch {
                lastError = error
                if error is CancellationError { throw error }
                try? FileManager.default.removeItem(at: output)
            }
        }
        throw lastError
    }

    /// PDFKit edge — renders selected pages at `options.dpi` (default 144).
    /// Multi-page selections write `name-N.png` siblings; single page uses the
    /// plain destination name.
    private static func convertPDFToImage(input: URL, output: URL, ext: String, options: ConversionOptions) throws {
        guard let document = PDFDocument(url: input), document.pageCount > 0 else {
            throw FileConversionError.unavailable("Could not open PDF")
        }
        let indexes = parsePageSelection(options.pages, pageCount: document.pageCount)
        let scale = max(0.5, min((options.dpi ?? 144) / 72.0, 8))
        let isJPEG = ext == "jpg" || ext == "jpeg"

        for (position, pageIndex) in indexes.enumerated() {
            try Task.checkCancellation()
            guard let page = document.page(at: pageIndex) else { continue }
            let bounds = page.bounds(for: .mediaBox)
            let width = Int(bounds.width * scale), height = Int(bounds.height * scale)
            guard width > 0, height > 0,
                  let context = CGContext(
                      data: nil, width: width, height: height,
                      bitsPerComponent: 8, bytesPerRow: 0,
                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                      bitmapInfo: isJPEG ? CGImageAlphaInfo.noneSkipLast.rawValue : CGImageAlphaInfo.premultipliedLast.rawValue
                  ) else { continue }
            context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            context.translateBy(x: -bounds.minX * scale, y: -bounds.minY * scale)
            context.scaleBy(x: scale, y: scale)
            page.draw(with: .mediaBox, to: context)
            guard let image = context.makeImage() else { continue }

            let pageOutput = pageOutputURL(base: output, index: position, total: indexes.count)
            guard let destination = CGImageDestinationCreateWithURL(pageOutput as CFURL, (isJPEG ? UTType.jpeg : UTType.png).identifier as CFString, 1, nil) else { continue }
            var props: [CFString: Any] = [:]
            if let quality = options.quality, isJPEG { props[kCGImageDestinationLossyCompressionQuality] = quality }
            CGImageDestinationAddImage(destination, image, props as CFDictionary)
            CGImageDestinationFinalize(destination)
        }
    }

    private static func pageOutputURL(base: URL, index: Int, total: Int) -> URL {
        if total == 1 { return base }
        let dir = base.deletingLastPathComponent()
        let name = base.deletingPathExtension().lastPathComponent
        return dir.appendingPathComponent("\(name)-\(index + 1).\(base.pathExtension)")
    }

    /// Parses "1-3", "2,4", "all"/nil into page indexes (clamped to pageCount,
    /// capped at 50 pages).
    private static func parsePageSelection(_ pages: String?, pageCount: Int) -> [Int] {
        let cap = min(pageCount, 50)
        guard let pages, pages.trimmingCharacters(in: .whitespaces).isEmpty == false else {
            return Array(0..<cap)
        }
        var result: [Int] = []
        for part in pages.split(separator: ",") {
            let trimmed = part.trimmingCharacters(in: .whitespaces)
            if let dash = trimmed.firstIndex(of: "-") {
                let start = Int(trimmed[..<dash]) ?? 0
                let end = Int(trimmed[trimmed.index(after: dash)...]) ?? 0
                if end >= start { result.append(contentsOf: start...end) }
            } else if let n = Int(trimmed) {
                result.append(n)
            }
        }
        let resolved = result.compactMap { n -> Int? in
            let i = n - 1
            return (i >= 0 && i < cap) ? i : nil
        }
        return resolved.isEmpty ? Array(0..<cap) : resolved
    }

    /// CSV/TSV ↔ JSON, implemented in Foundation (no dependency).
    private static func convertStructured(input: URL, output: URL, from: String, to: String) throws {
        if to == "json" {
            let text = try String(contentsOf: input, encoding: .utf8)
            let delimiter: Character = from == "tsv" ? "\t" : ","
            let rows = parseDelimited(text, delimiter: delimiter)
            guard let header = rows.first, rows.count > 1 else {
                // Header-only or empty file → empty array.
                try "[]\n".write(to: output, atomically: true, encoding: .utf8)
                return
            }
            let objects = rows.dropFirst().map { row -> [String: String] in
                var obj: [String: String] = [:]
                for (i, key) in header.enumerated() where i < row.count {
                    obj[key] = row[i]
                }
                return obj
            }
            let data = try JSONSerialization.data(withJSONObject: objects, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: output)
        } else {
            // json → csv/tsv
            let delimiter: Character = to == "tsv" ? "\t" : ","
            let data = try Data(contentsOf: input)
            let json = try JSONSerialization.jsonObject(with: data)
            var columns: [String] = []
            var rows: [[String: Any]] = []
            if let array = json as? [[String: Any]] {
                rows = array
                for row in array {
                    for key in row.keys where !columns.contains(key) { columns.append(key) }
                }
            } else if let dict = json as? [String: Any] {
                columns = ["key", "value"]
                rows = dict.map { ["key": $0.key, "value": $0.value] }
            } else if let array = json as? [Any] {
                columns = ["value"]
                rows = array.map { ["value": $0] }
            } else {
                throw FileConversionError.unavailable("JSON must be an array or object")
            }
            var lines = [columns.map { escapeDelimited($0, delimiter: delimiter) }.joined(separator: String(delimiter))]
            for row in rows {
                lines.append(columns.map { col in
                    let value = row[col]
                    if let nested = value as? [String: Any], let d = try? JSONSerialization.data(withJSONObject: nested) {
                        return escapeDelimited(String(decoding: d, as: UTF8.self), delimiter: delimiter)
                    }
                    if let arr = value as? [Any], let d = try? JSONSerialization.data(withJSONObject: arr) {
                        return escapeDelimited(String(decoding: d, as: UTF8.self), delimiter: delimiter)
                    }
                    return escapeDelimited(value.map { "\($0)" } ?? "", delimiter: delimiter)
                }.joined(separator: String(delimiter)))
            }
            try lines.joined(separator: "\n").write(to: output, atomically: true, encoding: .utf8)
        }
    }

    /// Minimal correct RFC-4180-style parser: quoted fields, "" escapes,
    /// embedded newlines, \r\n endings.
    private static func parseDelimited(_ text: String, delimiter: Character) -> [[String]] {
        var rows: [[String]] = []
        var field = ""
        var row: [String] = []
        var inQuotes = false
        var i = text.startIndex
        while i < text.endIndex {
            let c = text[i]
            if inQuotes {
                if c == "\"" {
                    let next = text.index(after: i)
                    if next < text.endIndex && text[next] == "\"" {
                        field.append("\"")
                        i = next
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(c)
                }
            } else if c == "\"" && field.isEmpty {
                inQuotes = true
            } else if c == delimiter {
                row.append(field); field = ""
            } else if c == "\n" || c == "\r" {
                if c == "\r" {
                    let next = text.index(after: i)
                    if next < text.endIndex && text[next] == "\n" { i = next }
                }
                row.append(field); field = ""
                if row.count > 1 || row.first?.isEmpty == false { rows.append(row) }
                row = []
            } else {
                field.append(c)
            }
            i = text.index(after: i)
        }
        if field.isEmpty == false || row.isEmpty == false {
            row.append(field)
            if row.count > 1 || row.first?.isEmpty == false { rows.append(row) }
        }
        return rows
    }

    private static func escapeDelimited(_ value: String, delimiter: Character) -> String {
        if value.contains(delimiter) || value.contains("\"") || value.contains("\n") || value.contains("\r") {
            return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return value
    }

    /// Archive edges: `* → zip/tar.gz` handled here; extraction routes through
    /// `extractArchive` (called directly from convert since output is a dir).
    private static func convertArchive(input: URL, output: URL, ext: String) async throws {
        if ext == "zip" {
            try await run("/usr/bin/ditto", ["-c", "-k", "--sequesterRsrc", input.path, output.path])
        } else {
            // tar.gz — run from the parent dir so the archive stores clean names.
            let parent = input.deletingLastPathComponent()
            try await run("/usr/bin/tar", ["-czf", output.path, "-C", parent.path, input.lastPathComponent])
        }
    }

    /// Extracts an archive into a unique sibling directory. Stages into a
    /// dotfile dir first, then moves — same contract as ArtifactStore.
    private static func extractArchive(sourceURL: URL, into folder: URL) async throws -> URL {
        let base = sourceURL.deletingPathExtensionIfCompound().lastPathComponent
        var index = 1
        var destination: URL
        repeat {
            let suffix = index == 1 ? "" : " \(index)"
            destination = folder.appendingPathComponent("\(base)-extracted\(suffix)", isDirectory: true)
            index += 1
        } while FileManager.default.fileExists(atPath: destination.path)

        let staged = folder.appendingPathComponent(".\(destination.lastPathComponent).foundry-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: staged, withIntermediateDirectories: true)

        do {
            let ext = ConversionGraph.normalizedExtension(of: sourceURL)
            if ext == "zip" {
                try await run("/usr/bin/ditto", ["-x", "-k", sourceURL.path, staged.path])
            } else {
                try await run("/usr/bin/tar", ["-xf", sourceURL.path, "-C", staged.path])
            }
        } catch {
            try? FileManager.default.removeItem(at: staged)
            throw error
        }
        try FileManager.default.moveItem(at: staged, to: destination)
        return destination
    }

    /// Vision OCR edge — accurate recognition, language correction on.
    private static func convertVisionOCR(input: URL, output: URL) async throws {
        guard let source = CGImageSourceCreateWithURL(input as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw FileConversionError.unavailable("Could not read image for OCR")
        }
        let recognized = try await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            try handler.perform([request])
            return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
        }.value
        try recognized.joined(separator: "\n").write(to: output, atomically: true, encoding: .utf8)
    }

    private static func convertFFmpeg(input: URL, output: URL, ext: String, options: ConversionOptions) async throws {
        let ffmpeg = try await locateExecutable(.ffmpeg)
        var args = ["-hide_banner", "-y", "-i", input.path]
        if let kbps = options.audioBitrateKbps, ConversionGraph.audioExts.contains(ext) {
            args += ["-b:a", "\(kbps)k"]
        }
        if ext == "mp4" { args += ["-movflags", "+faststart"] }
        args.append(output.path)
        try await run(ffmpeg, args)
    }

    private static func convertImageMagick(input: URL, output: URL, ext: String, options: ConversionOptions) async throws {
        let magick = try await locateExecutable(.imageMagick)
        var args = [input.path]
        if let maxPixel = options.maxPixelSize { args += ["-resize", "\(maxPixel)x\(maxPixel)>"] }
        if let quality = options.quality, lossyImageExts.contains(ext) {
            args += ["-quality", String(Int((quality * 100).rounded()))]
        }
        args.append(output.path)
        try await run(magick, args)
    }

    private static func convertPandoc(input: URL, output: URL, ext: String) async throws {
        let pandoc = try await locateExecutable(.pandoc)
        var args = [input.path]
        // Format hints where extension detection is ambiguous.
        let inputExt = ConversionGraph.normalizedExtension(of: input)
        if ["docbook", "dbk"].contains(inputExt) { args += ["-f", "docbook"] }
        switch ext {
        case "txt": args += ["-t", "plain"]
        case "tex": args += ["-t", "latex"]
        default: break
        }
        if ["html", "epub", "docx", "odt"].contains(ext) { args.append("-s") }
        args += ["-o", output.path]
        try await run(pandoc, args)
    }

    private static func convertSoffice(input: URL, output: URL, ext: String) async throws {
        let soffice = try await locateExecutable(.soffice)
        let temporaryFolder = FileManager.default.temporaryDirectory.appendingPathComponent("Foundry-Conversion-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temporaryFolder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryFolder) }
        try await run(soffice, ["--headless", "--convert-to", sofficeFormat(ext), "--outdir", temporaryFolder.path, input.path])
        let generated = temporaryFolder.appendingPathComponent(input.deletingPathExtension().lastPathComponent + "." + ext)
        guard FileManager.default.fileExists(atPath: generated.path) else {
            throw FileConversionError.unavailable("LibreOffice did not produce the expected output.")
        }
        try FileManager.default.removeItem(at: output)
        try FileManager.default.moveItem(at: generated, to: output)
    }

    private static func sofficeFormat(_ ext: String) -> String {
        switch ext {
        case "txt": return "txt:Text"
        case "csv": return "csv:Text - txt - csv (StarCalc)"
        default: return ext
        }
    }

    // MARK: - Helpers

    private static func locateExecutable(_ engine: ConversionEngine) async throws -> String {
        let locator = ExecutableLocator()
        if let found = try locator.locate(name: engine.executableName ?? "", candidates: engine.candidatePaths, environment: ProcessInfo.processInfo.environment) {
            return found.path
        }
        throw FileConversionError.unavailable("\(engine.displayName) is not installed")
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

    private static func uniqueDestination(for sourceURL: URL, ext: String, in folder: URL) -> URL {
        let original = sourceURL.deletingPathExtensionIfCompound().lastPathComponent
        var index = 1
        while true {
            let suffix = index == 1 ? "" : " \(index)"
            let candidate = folder.appendingPathComponent("\(original)\(suffix).\(ext)")
            if FileManager.default.fileExists(atPath: candidate.path) == false { return candidate }
            index += 1
        }
    }

    static func title(for ext: String) -> String {
        switch ext {
        case "jpg": return "JPEG"
        case "txt": return "Plain Text"
        case "rtf": return "Rich Text"
        case "html": return "HTML"
        case "doc": return "Word .doc"
        case "docx": return "Word .docx"
        case "odt": return "OpenDocument"
        case "wordml": return "Word XML"
        case "md": return "Markdown"
        case "epub": return "EPUB"
        case "rst": return "reStructuredText"
        case "tex": return "LaTeX"
        case "jp2": return "JPEG 2000"
        case "mp3": return "MP3"
        case "plist": return "Property List"
        case "json": return "JSON"
        case "csv": return "CSV"
        case "tsv": return "TSV"
        case "zip": return "ZIP Archive"
        case "tar.gz": return "TAR.GZ Archive"
        case "extract": return "Extract contents"
        case "srt": return "SubRip Subtitle"
        case "vtt": return "WebVTT Subtitle"
        case "tar": return "TAR"
        default: return ext.uppercased()
        }
    }

    static func category(for ext: String) -> FileConversionTarget.Category {
        switch ext {
        case "ico", "icns": return .icon
        case "pdf": return .pdf
        case "zip", "tar.gz", "tar", ConversionGraph.extractExt: return .archive
        case "json", "plist", "csv", "tsv", "srt", "vtt": return .data
        case "png", "jpg", "jpeg", "heic", "tiff", "tif", "gif", "bmp", "webp", "avif", "jp2", "svg",
             "dng", "cr2", "cr3", "nef", "arw", "orf", "rw2", "raf", "pef", "srw", "psd", "tga":
            return .photo
        case "mp3", "m4a", "wav", "aif", "aiff", "caf", "aac", "flac", "ogg", "opus", "wma", "m4b":
            return .music
        case "mp4", "mov", "m4v", "mkv", "webm", "avi", "mpg", "mpeg", "ts", "mts", "vob":
            return .video
        default: return .document
        }
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

    private static let categoryOrder: [FileConversionTarget.Category: Int] = [
        .photo: 0, .icon: 1, .document: 2, .pdf: 3, .data: 4, .archive: 5, .music: 6, .video: 7,
    ]

    private static func imageMetadata(for url: URL) -> ConversionImageMetadata? {
        guard ConversionGraph.imageReadExts.contains(ConversionGraph.normalizedExtension(of: url)),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? CGFloat,
              let height = properties[kCGImagePropertyPixelHeight] as? CGFloat else {
            return nil
        }
        return ConversionImageMetadata(width: width, height: height)
    }
}

private struct ConversionImageMetadata {
    let width: CGFloat
    let height: CGFloat
    var isIconCandidate: Bool { abs(width - height) < 0.5 && width <= 2048 && height <= 2048 }
}

private extension URL {
    /// Strip compound archive suffixes so "a.tar.gz" → base "a".
    func deletingPathExtensionIfCompound() -> URL {
        let lower = lastPathComponent.lowercased()
        if [".tar.gz", ".tar.bz2", ".tar.xz"].contains(where: { lower.hasSuffix($0) }) {
            return deletingPathExtension().deletingPathExtension()
        }
        return deletingPathExtension()
    }
}
