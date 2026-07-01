import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

@MainActor
final class FileConversionState: ObservableObject {
    @Published var sourceURL: URL?
    @Published var outputFolderURL: URL?
    @Published var availableTargets: [FileConversionTarget] = []
    @Published var selectedTargetID: String?
    @Published var status = ""
    @Published var isConverting = false
    @Published var outputURL: URL?

    var selectedTarget: FileConversionTarget? {
        availableTargets.first { $0.id == selectedTargetID } ?? availableTargets.first
    }

    func reset() {
        sourceURL = nil
        outputFolderURL = nil
        availableTargets = []
        selectedTargetID = nil
        status = ""
        isConverting = false
        outputURL = nil
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
        sourceURL = url
        outputFolderURL = outputFolderURL ?? url.deletingLastPathComponent()
        availableTargets = FileConversionService.availableTargets(for: url)
        selectedTargetID = FileConversionService.defaultTargetID(for: url, in: availableTargets)
        outputURL = nil
        status = availableTargets.isEmpty ? "No local converter available for this file yet" : ""
    }

    func convert() {
        guard let sourceURL, let target = selectedTarget else { return }
        let outputFolderURL = outputFolderURL ?? sourceURL.deletingLastPathComponent()
        isConverting = true
        outputURL = nil
        status = FileConversionService.preflightStatus(for: target) ?? "Converting to \(target.title)…"

        Task.detached {
            let result = FileConversionService.convert(sourceURL: sourceURL, target: target, outputFolderURL: outputFolderURL)
            await MainActor.run {
                self.isConverting = false
                switch result {
                case let .success(url):
                    self.outputURL = url
                    self.status = "Created \(url.lastPathComponent)"
                case let .failure(error):
                    self.status = error.localizedDescription
                }
            }
        }
    }

    func revealOutput() {
        guard let outputURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([outputURL])
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

enum FileConversionService {
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

    static func convert(sourceURL: URL, target: FileConversionTarget, outputFolderURL: URL) -> Result<URL, Error> {
        do {
            try FileManager.default.createDirectory(at: outputFolderURL, withIntermediateDirectories: true)
            let destination = outputFolderURL.appendingPathComponent(outputFileName(for: sourceURL, target: target))
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }

            switch target.family {
            case .image:
                try run("/usr/bin/sips", ["-s", "format", target.outputExtension == "jpg" ? "jpeg" : target.outputExtension, sourceURL.path, "--out", destination.path])
            case .text:
                try run("/usr/bin/textutil", ["-convert", target.outputExtension, "-output", destination.path, sourceURL.path])
            case .mediaFFmpeg:  
                let ffmpeg = try installFFmpegIfNeeded()
                try run(ffmpeg, ["-y", "-i", sourceURL.path, destination.path])
            case .imageMagick:
                let magick = try installImageMagickIfNeeded()
                try run(magick, [sourceURL.path, destination.path])
            case .pandoc:
                let pandoc = try installPandocIfNeeded()
                try run(pandoc, [sourceURL.path, "-o", destination.path])
            case .soffice:
                let soffice = try installSofficeIfNeeded()
                try run(soffice, ["--headless", "--convert-to", sofficeFormat(target.outputExtension), "--outdir", outputFolderURL.path, sourceURL.path])
                let generated = outputFolderURL.appendingPathComponent(sourceURL.deletingPathExtension().lastPathComponent + "." + target.outputExtension)
                if generated.path != destination.path, FileManager.default.fileExists(atPath: generated.path) {
                    if FileManager.default.fileExists(atPath: destination.path) {
                        try FileManager.default.removeItem(at: destination)
                    }
                    try FileManager.default.moveItem(at: generated, to: destination)
                }
            }
            return .success(destination)
        } catch {
            return .failure(error)
        }
    }

    private static func target(_ ext: String, title: String? = nil, category: FileConversionTarget.Category, family: FileConversionTarget.Family) -> FileConversionTarget {
        FileConversionTarget(id: ext, title: title ?? ext.uppercased(), outputExtension: ext, category: category, family: family)
    }

    private static func outputFileName(for sourceURL: URL, target: FileConversionTarget) -> String {
        sourceURL.deletingPathExtension().lastPathComponent + "." + target.outputExtension
    }

    private static func run(_ path: String, _ arguments: [String]) throws {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "Conversion failed"
            throw NSError(domain: "FoundryConversion", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: output.trimmingCharacters(in: .whitespacesAndNewlines)])
        }
    }

    private static func firstExecutable(_ paths: [String]) -> String? {
        paths.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    private static func installFFmpegIfNeeded() throws -> String {
        if let ffmpeg = firstExecutable(["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg"]) { return ffmpeg }
        guard let brew = firstExecutable(["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]) else {
            throw NSError(domain: "FoundryConversion", code: 1, userInfo: [NSLocalizedDescriptionKey: "ffmpeg is missing and Homebrew was not found"])
        }
        try run(brew, ["install", "ffmpeg"])
        if let ffmpeg = firstExecutable(["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg"]) { return ffmpeg }
        throw NSError(domain: "FoundryConversion", code: 1, userInfo: [NSLocalizedDescriptionKey: "ffmpeg install finished, but ffmpeg was not found"])
    }

    private static func installImageMagickIfNeeded() throws -> String {
        if let magick = firstExecutable(["/opt/homebrew/bin/magick", "/usr/local/bin/magick"]) { return magick }
        guard let brew = firstExecutable(["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]) else {
            throw NSError(domain: "FoundryConversion", code: 1, userInfo: [NSLocalizedDescriptionKey: "ImageMagick is missing and Homebrew was not found"])
        }
        try run(brew, ["install", "imagemagick"])
        if let magick = firstExecutable(["/opt/homebrew/bin/magick", "/usr/local/bin/magick"]) { return magick }
        throw NSError(domain: "FoundryConversion", code: 1, userInfo: [NSLocalizedDescriptionKey: "ImageMagick install finished, but magick was not found"])
    }

    private static func installPandocIfNeeded() throws -> String {
        if let pandoc = firstExecutable(["/opt/homebrew/bin/pandoc", "/usr/local/bin/pandoc"]) { return pandoc }
        guard let brew = firstExecutable(["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]) else {
            throw NSError(domain: "FoundryConversion", code: 1, userInfo: [NSLocalizedDescriptionKey: "pandoc is missing and Homebrew was not found"])
        }
        try run(brew, ["install", "pandoc"])
        if let pandoc = firstExecutable(["/opt/homebrew/bin/pandoc", "/usr/local/bin/pandoc"]) { return pandoc }
        throw NSError(domain: "FoundryConversion", code: 1, userInfo: [NSLocalizedDescriptionKey: "pandoc install finished, but pandoc was not found"])
    }

    private static func installSofficeIfNeeded() throws -> String {
        if let soffice = firstExecutable(["/Applications/LibreOffice.app/Contents/MacOS/soffice", "/Applications/OpenOffice.app/Contents/MacOS/soffice", "/opt/homebrew/bin/soffice", "/usr/local/bin/soffice"]) { return soffice }
        guard let brew = firstExecutable(["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]) else {
            throw NSError(domain: "FoundryConversion", code: 1, userInfo: [NSLocalizedDescriptionKey: "LibreOffice is missing and Homebrew was not found"])
        }
        try run(brew, ["install", "--cask", "libreoffice"])
        if let soffice = firstExecutable(["/Applications/LibreOffice.app/Contents/MacOS/soffice", "/opt/homebrew/bin/soffice", "/usr/local/bin/soffice"]) { return soffice }
        throw NSError(domain: "FoundryConversion", code: 1, userInfo: [NSLocalizedDescriptionKey: "LibreOffice install finished, but soffice was not found"])
    }

    static func preflightStatus(for target: FileConversionTarget) -> String? {
        switch target.family {
        case .mediaFFmpeg where ffmpegInstalled == false:
            return "Installing ffmpeg, then converting to \(target.title)…"
        case .imageMagick where imageMagickInstalled == false:
            return "Installing ImageMagick, then converting to \(target.title)…"
        case .pandoc where pandocInstalled == false:
            return "Installing pandoc, then converting to \(target.title)…"
        case .soffice where sofficeInstalled == false:
            return "Installing LibreOffice, then converting to \(target.title)…"
        default:
            return nil
        }
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

    static let ffmpegInstalled = firstExecutable(["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg"]) != nil
    private static let imageMagickInstalled = firstExecutable(["/opt/homebrew/bin/magick", "/usr/local/bin/magick"]) != nil
    private static let pandocInstalled = firstExecutable(["/opt/homebrew/bin/pandoc", "/usr/local/bin/pandoc"]) != nil
    private static let sofficeInstalled = firstExecutable(["/Applications/LibreOffice.app/Contents/MacOS/soffice", "/Applications/OpenOffice.app/Contents/MacOS/soffice", "/opt/homebrew/bin/soffice", "/usr/local/bin/soffice"]) != nil
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
