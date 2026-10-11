import AppKit
@preconcurrency import QuickLookThumbnailing
import SwiftUI
import FoundryServices

struct SplitPreviewLayout<ListContent: View, Preview: View>: View {
    @ViewBuilder var list: ListContent
    @ViewBuilder var preview: Preview

    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 0) {
                list
                    .frame(width: proxy.size.width * 0.42)
                Divider()
                    .opacity(0.5)
                preview
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
    }
}

struct PreviewMetadata: View {
    let rows: [(label: String, value: String)]

    var body: some View {
        VStack(spacing: 0) {
            Divider().opacity(0.5)
            ForEach(rows, id: \.label) { row in
                HStack(alignment: .firstTextBaseline) {
                    Text(row.label)
                        .foregroundStyle(FoundryTheme.mutedText)
                    Spacer(minLength: 12)
                    Text(row.value)
                        .foregroundStyle(FoundryTheme.secondaryText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
                .font(FoundryTheme.body(size: 11, weight: .regular))
                .padding(.vertical, 5)
                .accessibilityElement(children: .combine)
            }
        }
    }

    static func size(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    static func date(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }
}

struct SnippetPreview: View {
    let snippet: StoredSnippet

    private var attributedContent: AttributedString {
        var result = AttributedString(snippet.content)
        result.font = .system(size: 12.5)
        var searchStart = snippet.content.startIndex
        while let open = snippet.content.range(of: "{", range: searchStart..<snippet.content.endIndex) {
            guard let close = snippet.content.range(of: "}", range: open.upperBound..<snippet.content.endIndex) else { break }
            let tokenRange = open.lowerBound..<close.upperBound
            if let lower = AttributedString.Index(tokenRange.lowerBound, within: result),
               let upper = AttributedString.Index(tokenRange.upperBound, within: result) {
                result[lower..<upper].foregroundColor = FoundryTheme.accentTint
            }
            searchStart = close.upperBound
        }
        return result
    }

    private var metadata: [(label: String, value: String)] {
        var rows: [(String, String)] = []
        if snippet.keyword.isEmpty == false { rows.append(("Keyword", snippet.keyword)) }
        if snippet.tags.isEmpty == false { rows.append(("Tags", snippet.tags.map { "#\($0)" }.joined(separator: " "))) }
        if snippet.useCount > 0 { rows.append(("Used", "\(snippet.useCount)×")) }
        if let lastUsed = snippet.lastUsedAt { rows.append(("Last used", PreviewMetadata.date(lastUsed))) }
        rows.append(("Updated", PreviewMetadata.date(snippet.updatedAt)))
        rows.append(("Length", "\(snippet.content.count) chars"))
        return rows
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "curlybraces")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(FoundryTheme.accentTint)
                Text(snippet.title)
                    .font(FoundryTheme.body(size: 13, weight: .semibold))
                    .foregroundStyle(FoundryTheme.primaryText)
                    .lineLimit(2)
                if snippet.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(FoundryTheme.mutedText)
                }
            }

            ScrollView {
                Text(attributedContent)
                    .foregroundStyle(FoundryTheme.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, minHeight: 120, maxHeight: .infinity)

            PreviewMetadata(rows: metadata)
        }
        .padding(16)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Snippet preview, \(snippet.title)")
    }
}

struct FilePreview: View {
    let path: String
    var showsMetadata = true

    @State private var thumbnail: NSImage?

    private var url: URL { URL(fileURLWithPath: path) }

    private var metadata: [(label: String, value: String)] {
        let values = url.fileResourceValues([.localizedTypeDescriptionKey, .fileSizeKey, .contentModificationDateKey, .isDirectoryKey])
        var rows: [(String, String)] = [("Kind", values?.localizedTypeDescription ?? "File")]
        if values?.isDirectory != true, let size = values?.fileSize { rows.append(("Size", PreviewMetadata.size(size))) }
        if let modified = values?.contentModificationDate { rows.append(("Modified", PreviewMetadata.date(modified))) }
        rows.append(("Where", (url.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath))
        return rows
    }

    var body: some View {
        VStack(spacing: 12) {
            Group {
                if let thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    FileIcon(path: path) {
                        Image(systemName: "doc")
                            .font(.system(size: 48, weight: .light))
                            .foregroundStyle(FoundryTheme.faintText)
                    }
                    .frame(width: 96, height: 96)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 140, maxHeight: .infinity)
            .accessibilityHidden(true)

            Text(url.lastPathComponent)
                .font(FoundryTheme.body(size: 13, weight: .semibold))
                .foregroundStyle(FoundryTheme.primaryText)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .truncationMode(.middle)

            if showsMetadata { PreviewMetadata(rows: metadata) }
        }
        .padding(16)
        .task(id: path) {
            thumbnail = nil
            let request = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: 360, height: 240),
                scale: NSScreen.main?.backingScaleFactor ?? 2, representationTypes: .thumbnail)
            thumbnail = await BestEffort.attempt("generate thumbnail \(url.lastPathComponent)") {
                try await QLThumbnailGenerator.shared.generateBestRepresentation(for: request).nsImage
            }
        }
    }
}
