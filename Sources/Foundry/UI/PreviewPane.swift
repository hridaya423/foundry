import AppKit
@preconcurrency import QuickLookThumbnailing
import SwiftUI

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

struct FilePreview: View {
    let path: String
    var showsMetadata = true

    @State private var thumbnail: NSImage?

    private var url: URL { URL(fileURLWithPath: path) }

    private var metadata: [(label: String, value: String)] {
        let values = try? url.resourceValues(forKeys: [.localizedTypeDescriptionKey, .fileSizeKey, .contentModificationDateKey, .isDirectoryKey])
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
                    Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                        .resizable()
                        .aspectRatio(contentMode: .fit)
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
            let request = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: 360, height: 240), scale: NSScreen.main?.backingScaleFactor ?? 2, representationTypes: .thumbnail)
            thumbnail = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request).nsImage
        }
    }
}
