import Foundation

/// A conversion engine. Native engines run in-process or via system tools and
/// are always ready; external engines are located on disk and provisioned
/// through Homebrew on demand.
public enum ConversionEngine: String, Sendable, Hashable, CaseIterable {
    // Native
    case imageIO       // CGImageSource/Destination — images + raster→pdf
    case avFoundation  // AVAssetExportSession — media remux/transcode
    case pdfKit        // PDFKit — pdf→image pages, merge-ready
    case textutil      // /usr/bin/textutil — rich text formats
    case plutil        // /usr/bin/plutil — plist↔json
    case structuredData// Foundation — csv/tsv↔json
    case archive       // ditto/tar — compress and extract
    case vision        // VNRecognizeTextRequest — image→text OCR
    // External (Homebrew)
    case ffmpeg
    case imageMagick
    case pandoc
    case soffice

    public var isNative: Bool {
        switch self {
        case .imageIO, .avFoundation, .pdfKit, .textutil, .plutil, .structuredData, .archive, .vision:
            return true
        case .ffmpeg, .imageMagick, .pandoc, .soffice:
            return false
        }
    }

    public var displayName: String {
        switch self {
        case .imageIO: return "Built-in image engine"
        case .avFoundation: return "Built-in media engine"
        case .pdfKit: return "Built-in PDF engine"
        case .textutil: return "Built-in text engine"
        case .plutil: return "Built-in plist engine"
        case .structuredData: return "Built-in data engine"
        case .archive: return "Built-in archive engine"
        case .vision: return "Built-in OCR engine"
        case .ffmpeg: return "FFmpeg"
        case .imageMagick: return "ImageMagick"
        case .pandoc: return "Pandoc"
        case .soffice: return "LibreOffice"
        }
    }

    /// Executable name to locate for external engines.
    public var executableName: String? {
        switch self {
        case .ffmpeg: return "ffmpeg"
        case .imageMagick: return "magick"
        case .pandoc: return "pandoc"
        case .soffice: return "soffice"
        default: return nil
        }
    }

    public var candidatePaths: [String] {
        switch self {
        case .soffice:
            return ["/Applications/LibreOffice.app/Contents/MacOS/soffice",
                    "/opt/homebrew/bin/soffice", "/usr/local/bin/soffice"]
        case .ffmpeg, .imageMagick, .pandoc:
            return ["/opt/homebrew/bin/\(executableName!)", "/usr/local/bin/\(executableName!)"]
        default: return []
        }
    }

    /// Homebrew formula (or nil when installed as a cask / not provisionable).
    public var brewFormula: String? {
        switch self {
        case .ffmpeg: return "ffmpeg"
        case .imageMagick: return "imagemagick"
        case .pandoc: return "pandoc"
        default: return nil
        }
    }

    public var brewCask: String? {
        switch self {
        case .soffice: return "libreoffice"
        default: return nil
        }
    }
}

/// One hop in a conversion: `input` ext → `output` ext via `engine`.
public struct ConversionEdge: Hashable, Sendable {
    public let input: String
    public let output: String
    public let engine: ConversionEngine

    public init(input: String, output: String, engine: ConversionEngine) {
        self.input = input
        self.output = output
        self.engine = engine
    }
}

public struct ConversionRoute: Hashable, Sendable {
    public var edges: [ConversionEdge]
    public init(edges: [ConversionEdge]) { self.edges = edges }

    public var engines: [ConversionEngine] { edges.map(\.engine) }
    public var producingEngine: ConversionEngine? { edges.last?.engine }
    public var hopCount: Int { edges.count }
    public var externalEngineCount: Int { engines.filter { $0.isNative == false }.count }

    /// Human-readable provenance, e.g. "Built in" or "via Pandoc + LibreOffice".
    public var engineSummary: String {
        let externals = engines.filter { $0.isNative == false }
        if externals.isEmpty { return "Built in" }
        let nativeUsed = engines.contains { $0.isNative }
        let names = externals.map(\.displayName).joined(separator: " + ")
        return nativeUsed ? "via \(names) + built-in" : "via \(names)"
    }
}

/// User-tunable conversion settings. Engines read the options they understand;
/// unknown options are ignored (e.g. `dpi` only applies to pdf→image hops).
public struct ConversionOptions: Sendable, Equatable {
    public var quality: Double?        // 0…1 — lossy image output (jpg/heic/avif/jp2/webp)
    public var maxPixelSize: Int?      // resize longest edge (image outputs)
    public var dpi: Double?            // pdf→image render density (default 144)
    public var pages: String?          // pdf→image page selection, e.g. "1-3" or "2,4"
    public var audioBitrateKbps: Int?  // ffmpeg audio bitrate
    public init(quality: Double? = nil, maxPixelSize: Int? = nil, dpi: Double? = nil,
                pages: String? = nil, audioBitrateKbps: Int? = nil) {
        self.quality = quality
        self.maxPixelSize = maxPixelSize
        self.dpi = dpi
        self.pages = pages
        self.audioBitrateKbps = audioBitrateKbps
    }
    public static let standard = ConversionOptions()
}

/// The conversion edge graph. `edges` enumerates every direct hop an engine can
/// perform; the router finds the best ≤3-hop route between any two extensions.
public enum ConversionGraph {

    // MARK: Format sets

    /// ImageIO-verified write formats on macOS 14+ (webp/ico/icns writes are
    /// advertised but fail through sips — those stay on ImageMagick).
    public static let imageWriteExts: Set<String> = [
        "png", "jpg", "jpeg", "heic", "tiff", "tif", "gif", "bmp", "jp2", "avif", "pdf",
    ]
    public static let imageReadExts: Set<String> = [
        "png", "jpg", "jpeg", "heic", "heif", "heics", "tif", "tiff", "gif", "bmp",
        "webp", "avif", "jp2", "svg",
        "dng", "cr2", "cr3", "nef", "arw", "orf", "rw2", "raf", "pef", "srw",
    ]
    /// Formats Vision OCR can load — conservative subset of imageReadExts.
    public static let visionReadExts: Set<String> = [
        "png", "jpg", "jpeg", "heic", "tif", "tiff", "bmp", "gif", "webp",
    ]

    static let textutilReadExts: Set<String> = [
        "txt", "rtf", "rtfd", "html", "htm", "doc", "docx", "odt", "wordml", "webarchive",
    ]
    static let textutilWriteExts: Set<String> = [
        "txt", "rtf", "html", "doc", "docx", "odt", "wordml",
    ]

    static let audioExts: Set<String> = [
        "mp3", "m4a", "wav", "aif", "aiff", "caf", "aac", "flac", "ogg", "opus", "wma", "m4b",
    ]
    static let videoExts: Set<String> = [
        "mp4", "mov", "m4v", "mkv", "webm", "avi", "mpg", "mpeg", "ts", "mts", "vob",
    ]
    /// What AVFoundation can open (no mkv/webm/avi — those need FFmpeg).
    static let avFoundationReadAudio: Set<String> = [
        "mp3", "m4a", "wav", "aif", "aiff", "caf", "aac", "m4b",
    ]
    static let avFoundationReadVideo: Set<String> = ["mp4", "mov", "m4v"]

    static let ffmpegMediaRead: Set<String> = audioExts.union(videoExts).union(["mka"])
    /// Image-sequence formats ffmpeg reads — they can only produce video
    /// outputs (gif→mp3 would emit an empty stream, which is junk).
    static let ffmpegImageSequenceRead: Set<String> = ["gif", "apng"]
    static let ffmpegImageSequenceWrite: Set<String> = ["mp4", "mov", "mkv", "webm", "avi"]
    static let ffmpegMediaWrite: Set<String> = [
        "mp3", "m4a", "wav", "flac", "ogg", "opus", "aac", "aiff",
        "mp4", "mov", "mkv", "webm", "avi", "gif",
    ]
    static let subtitleExts: Set<String> = ["srt", "vtt", "ass", "ssa"]

    static let pandocReadExts: Set<String> = [
        "md", "markdown", "rst", "latex", "tex", "docbook", "dbk", "epub",
        "org", "textile", "html", "htm", "ipynb", "docx",
    ]
    static let pandocWriteExts: Set<String> = [
        "html", "md", "rst", "tex", "docx", "epub", "txt", "org", "asciidoc", "rtf", "odt",
    ]

    /// LibreOffice document-family formats (produces pdf/docx/odt/html/txt/rtf).
    static let sofficeDocReadExts: Set<String> = [
        "doc", "docx", "odt", "rtf", "txt", "html", "htm", "pdf",
    ]
    static let sofficeDocWriteExts: Set<String> = ["pdf", "docx", "odt", "html", "txt", "rtf"]
    static let sofficeSheetReadExts: Set<String> = ["xls", "xlsx", "ods", "csv"]
    static let sofficeSheetWriteExts: Set<String> = ["csv", "xlsx", "pdf"]
    static let sofficeDeckReadExts: Set<String> = ["ppt", "pptx", "odp"]
    static let sofficeDeckWriteExts: Set<String> = ["pdf", "pptx"]

    /// ImageMagick's extended reach — covers everything ImageIO misses.
    static let magickReadExts: Set<String> = imageReadExts.union(["psd", "eps", "ai", "ico", "icns"])
    static let magickWriteExts: Set<String> = imageWriteExts.union(["webp", "ico", "icns", "psd"])

    static let archiveExtractExts: Set<String> = [
        "zip", "tar", "gz", "tgz", "bz2", "tbz2", "xz", "txz", "tar.gz", "tar.bz2", "tar.xz",
    ]

    /// Sentinel output for archive extraction — produces a directory, not a file.
    public static let extractExt = "extract"

    // MARK: Graph construction

    /// Every direct edge in the graph, built once.
    public static let edges: [ConversionEdge] = buildEdges()

    private static func buildEdges() -> [ConversionEdge] {
        var edges: [ConversionEdge] = []

        func cartesian(_ engine: ConversionEngine, _ reads: Set<String>, _ writes: Set<String>) {
            for r in reads {
                for w in writes where w != r {
                    edges.append(ConversionEdge(input: r, output: w, engine: engine))
                }
            }
        }

        // Native engines
        cartesian(.imageIO, imageReadExts, imageWriteExts)
        cartesian(.textutil, textutilReadExts, textutilWriteExts)
        // AVFoundation: video → mp4/m4a, audio → m4a
        cartesian(.avFoundation, avFoundationReadVideo, ["mp4", "m4a"])
        cartesian(.avFoundation, avFoundationReadAudio, ["m4a"])
        // PDFKit: pdf → raster pages
        cartesian(.pdfKit, ["pdf"], ["png", "jpg"])
        // plutil: plist↔json
        cartesian(.plutil, ["plist", "json"], ["json", "plist"])
        // Structured data
        cartesian(.structuredData, ["csv", "tsv"], ["json"])
        cartesian(.structuredData, ["json"], ["csv", "tsv"])
        // Vision OCR
        cartesian(.vision, visionReadExts, ["txt"])
        // Archive: anything → zip; archives → extract
        edges.append(ConversionEdge(input: "*", output: "zip", engine: .archive))
        edges.append(ConversionEdge(input: "*", output: "tar.gz", engine: .archive))
        for ext in archiveExtractExts {
            edges.append(ConversionEdge(input: ext, output: extractExt, engine: .archive))
        }

        // External engines
        cartesian(.imageMagick, magickReadExts, magickWriteExts)
        cartesian(.ffmpeg, ffmpegMediaRead, ffmpegMediaWrite)
        cartesian(.ffmpeg, ffmpegImageSequenceRead, ffmpegImageSequenceWrite)
        cartesian(.ffmpeg, subtitleExts, subtitleExts)
        cartesian(.pandoc, pandocReadExts, pandocWriteExts)
        cartesian(.soffice, sofficeDocReadExts, sofficeDocWriteExts)
        cartesian(.soffice, sofficeSheetReadExts, sofficeSheetWriteExts)
        cartesian(.soffice, sofficeDeckReadExts, sofficeDeckWriteExts)

        return edges
    }

    // MARK: Routing

    /// Best route (≤3 hops) from `input` ext to `output` ext, or nil.
    /// Ranking: fewest hops, then fewest external engines, then graph order.
    public static func route(from input: String, to output: String) -> ConversionRoute? {
        guard input != output else { return nil }
        // Single-hop fast path — pick the best direct edge.
        let direct = edges.filter { ($0.input == input || $0.input == "*") && $0.output == output }
            .filter { edgeAllowed(origin: input, edge: $0) }
            .sorted(by: edgePreference)
        if let best = direct.first { return ConversionRoute(edges: [best]) }

        // BFS up to 3 hops.
        var visited: Set<String> = [input]
        var frontier: [(ext: String, route: ConversionRoute)] = [
            (input, ConversionRoute(edges: []))
        ]
        var candidates: [ConversionRoute] = []
        for _ in 0..<3 where !frontier.isEmpty {
            var next: [(String, ConversionRoute)] = []
            for (ext, route) in frontier {
                for edge in edges where (edge.input == ext || edge.input == "*") && edge.output != ext {
                    guard edgeAllowed(origin: input, edge: edge) else { continue }
                    let newRoute = ConversionRoute(edges: route.edges + [edge])
                    if edge.output == output {
                        candidates.append(newRoute)
                        continue
                    }
                    guard visited.insert(edge.output).inserted else { continue }
                    next.append((edge.output, newRoute))
                }
            }
            if candidates.isEmpty == false { break }
            frontier = next
        }
        return candidates.sorted(by: routePreference).first
    }

    /// All reachable output extensions from `input`, each with its best route.
    public static func routes(from input: String) -> [String: ConversionRoute] {
        var best: [String: ConversionRoute] = [:]
        var visited: Set<String> = [input]
        var frontier: [(ext: String, route: ConversionRoute)] = [
            (input, ConversionRoute(edges: []))
        ]
        for _ in 0..<3 where !frontier.isEmpty {
            var next: [(String, ConversionRoute)] = []
            for (ext, route) in frontier {
                for edge in edges where (edge.input == ext || edge.input == "*") && edge.output != ext && edge.output != input {
                    guard edgeAllowed(origin: input, edge: edge) else { continue }
                    let newRoute = ConversionRoute(edges: route.edges + [edge])
                    if let existing = best[edge.output] {
                        if routePreference(newRoute, existing) {
                            best[edge.output] = newRoute
                        }
                    } else {
                        best[edge.output] = newRoute
                    }
                    if visited.insert(edge.output).inserted {
                        next.append((edge.output, newRoute))
                    }
                }
            }
            frontier = next
        }
        return best
    }

    /// Junk-route guard: audio outputs are only meaningful when the chain
    /// *started* from media. Without this, paths like png→gif→mov→mp3 would
    /// offer "convert this image to audio" (an empty stream).
    private static func edgeAllowed(origin: String, edge: ConversionEdge) -> Bool {
        if audioExts.contains(edge.output) || subtitleExts.contains(edge.output) {
            return mediaOrigins.contains(origin)
        }
        return true
    }

    private static let mediaOrigins: Set<String> = audioExts.union(videoExts).union(subtitleExts)

    private static func edgePreference(_ a: ConversionEdge, _ b: ConversionEdge) -> Bool {
        if a.engine.isNative != b.engine.isNative { return a.engine.isNative }
        return a.engine.rawValue < b.engine.rawValue
    }

    private static func routePreference(_ a: ConversionRoute, _ b: ConversionRoute) -> Bool {
        if a.hopCount != b.hopCount { return a.hopCount < b.hopCount }
        if a.externalEngineCount != b.externalEngineCount {
            return a.externalEngineCount < b.externalEngineCount
        }
        return a.engineSummary < b.engineSummary
    }

    /// Normalized compound-aware extension for a file URL ("x.tar.gz" → "tar.gz").
    public static func normalizedExtension(of url: URL) -> String {
        let name = url.lastPathComponent.lowercased()
        for compound in [".tar.gz", ".tar.bz2", ".tar.xz"] where name.hasSuffix(compound) {
            return String(compound.dropFirst())
        }
        return url.pathExtension.lowercased()
    }
}
