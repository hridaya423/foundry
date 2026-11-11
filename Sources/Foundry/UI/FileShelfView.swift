import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct FileShelfView: View {
    var state: FileShelfState
    let convertSelected: ([ShelfFile]) -> Void
    var extractText: (URL) -> Void = { _ in }
    var decodeBarcode: (URL) -> Void = { _ in }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if state.files.isEmpty {
                FoundryEmptyState(
                    symbol: "tray.and.arrow.down",
                    title: "File Shelf is empty",
                    message: "Drop files anywhere on Foundry. They stay here temporarily until you remove them or quit."
                )
            } else {
                HStack(alignment: .center, spacing: 8) {
                    FoundrySectionHeader(title: Self.headerTitle(selected: state.selectedIDs.isEmpty ? 0 : state.selectedFiles.count,
                        total: state.files.count))

                    if state.isRemovingBackground {
                        FoundryActionButton(
                            title: "Cancel",
                            systemName: "xmark",
                            action: state.cancelBackgroundRemoval
                        )
                    } else if state.isSettingUpBEN2 {
                        FoundryActionButton(title: String(localized: "Cancel Download"), systemName: "xmark", action: state.cancelBEN2Setup)
                    } else {
                        if state.selectedFiles.isEmpty == false {
                            FoundryActionButton(
                                title: "Convert",
                                systemName: "arrow.left.arrow.right",
                                action: { convertSelected(state.selectedFiles) }
                            )
                        }

                        if state.canRemoveBackgroundFromSelected || state.canTryExperimentalBackgroundRemovalFromSelected {
                            backgroundRemovalMenu
                        }
                    }
                }
                .padding(.horizontal, 4)

                if state.backgroundRemovalStatus.isEmpty == false {
                    FoundryStatusBanner(
                        text: state.backgroundRemovalStatus,
                        symbol: state.backgroundRemovalError == nil ? "checkmark.circle" : "exclamationmark.triangle",
                        tint: state.backgroundRemovalError
                            == nil ? (state.isRemovingBackground ? FoundryTheme.accent : FoundryTheme.success) : FoundryTheme.warning,
                        isLoading: state.isRemovingBackground
                    )
                }

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(state.files) { file in
                                FileShelfRow(
                                    file: file,
                                    isSelected: state.selectedIDs.contains(file.id),
                                    canRemoveBackground: state.isRemovingBackground == false && state.supportsBackgroundRemoval(for: file),
                                    canTryBEN2: state.isRemovingBackground == false && state.canTryExperimentalBackgroundRemoval(for: file),
                                    needsModelDownload: state.isDetailedModelReady == false,
                                    isRemovingBackground: state.backgroundRemovalFileID == file.id && state.isRemovingBackground,
                                    reveal: { NSWorkspace.shared.activateFileViewerSelecting([file.url]) },
                                    removeBackground: {
                                        state.select(id: file.id)
                                        state.removeBackgroundFromSelected()
                                    },
                                    tryBEN2: {
                                        state.select(id: file.id)
                                        state.removeBackgroundDetailed()
                                    },
                                    cancelBackgroundRemoval: { state.cancelBackgroundRemoval() },
                                    extractText: { extractText(file.url) },
                                    decodeBarcode: { decodeBarcode(file.url) },
                                    remove: { state.remove(id: file.id) }
                                )
                                .id(file.id)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    let modifiers = NSEvent.modifierFlags
                                    if modifiers.contains(.shift) {
                                        state.extendSelection(to: file.id)
                                    } else if modifiers.contains(.command) {
                                        state.toggleSelection(id: file.id)
                                    } else {
                                        state.select(id: file.id)
                                    }
                                }
                                .accessibilityAddTraits(.isButton)
                                .accessibilityAction { state.toggleSelection(id: file.id) }
                                .onDrag { NSItemProvider(object: file.url as NSURL) }
                            }
                        }
                    }
                    .scrollIndicators(.never)
                    .onChange(of: state.selectedID) { _, id in
                        guard let id else { return }
                        proxy.scrollTo(id, anchor: .center)
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 14)
        .alert("Couldn't Remove Background", isPresented: backgroundRemovalErrorBinding) {
            if state.backgroundRemovalNeedsDestination {
                Button("Choose Save Location") { state.chooseBackgroundRemovalDestination() }
            }
            Button("Dismiss", role: .cancel) { state.dismissBackgroundRemovalError() }
        } message: {
            Text(state.backgroundRemovalError ?? String(localized: "This image couldn’t be read. Try a PNG or JPEG."))
        }
    }

    private var backgroundRemovalErrorBinding: Binding<Bool> {
        Binding(
            get: { state.backgroundRemovalError != nil },
            set: { isPresented in
                if isPresented == false { state.dismissBackgroundRemovalError() }
            }
        )
    }

    private var backgroundRemovalMenu: some View {
        Menu {
            if state.canRemoveBackgroundFromSelected {
                Button("Remove Background", action: state.removeBackgroundFromSelected)
            }
            if state.canTryExperimentalBackgroundRemovalFromSelected {
                FileShelfDetailedRemovalItem(needsDownload: state.isDetailedModelReady == false, action: state.removeBackgroundDetailed)
            }
        } label: {
            HStack(spacing: FoundryTheme.Spacing.xs) {
                Image(systemName: "wand.and.stars")
                    .font(FoundryTheme.Glyph.xs)
                Text("Remove Background")
                    .font(FoundryTheme.body)
                Image(systemName: "chevron.down")
                    .font(FoundryTheme.Glyph.xs)
            }
            .foregroundStyle(FoundryTheme.accent)
            .padding(.horizontal, FoundryTheme.Spacing.md)
            .frame(height: FoundryTheme.Control.compact)
        }
        .menuStyle(.borderlessButton)
        .buttonStyle(FoundryQuietButtonStyle())
        .accessibilityLabel("Remove Background")
        .help("Remove the background from the selected images")
    }

    static func headerTitle(selected: Int, total: Int) -> String {
        guard selected > 0 else { return total == 1 ? String(localized: "1 File") : String(localized: "\(total) Files") }
        return String(localized: "\(selected) of \(total) Selected")
    }
}

struct FileShelfDetailedRemovalItem: View {
    let needsDownload: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("Remove Background (Detailed)")
            if needsDownload { Text("One-time model download") }
        }
    }
}

struct FileShelfRow: View {
    let file: ShelfFile
    let isSelected: Bool
    let canRemoveBackground: Bool
    let canTryBEN2: Bool
    let needsModelDownload: Bool
    let isRemovingBackground: Bool
    let reveal: () -> Void
    let removeBackground: () -> Void
    let tryBEN2: () -> Void
    let cancelBackgroundRemoval: () -> Void
    let extractText: () -> Void
    let decodeBarcode: () -> Void
    let remove: () -> Void

    private var isImageFile: Bool {
        UTType(filenameExtension: file.url.pathExtension)?.conforms(to: .image) == true
    }

    @State private var isHovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 12) {
            FileIcon(path: file.url.path) { Color.clear }
                .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text(file.name)
                    .font(FoundryTheme.body)
                    .foregroundStyle(FoundryTheme.textPrimary)
                    .lineLimit(1)
                Text(file.location)
                    .font(FoundryTheme.bodySecondary)
                    .foregroundStyle(FoundryTheme.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            if isSelected || isHovering {
                FoundryIconButton(
                    systemName: "folder",
                    accessibilityLabel: "Reveal \(file.name) in Finder",
                    action: reveal
                )

                FoundryIconButton(
                    systemName: "xmark",
                    accessibilityLabel: "Remove \(file.name) from File Shelf",
                    action: remove
                )
            }
        }
        .padding(.horizontal, FoundryTheme.Spacing.sm)
        .frame(height: FoundryTheme.Control.rowTall)
        .background(RowBackground(isSelected: isSelected, isHovering: isHovering))
        .animation(reduceMotion ? nil : FoundryTheme.Motion.hover, value: isHovering)
        .onHover { isHovering = $0 }
        .accessibilityElement(children: .contain)
        .accessibilityHint("Select file")
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .contextMenu {
            if isRemovingBackground {
                Button("Cancel Background Removal", action: cancelBackgroundRemoval)
            } else {
                if canRemoveBackground {
                    Button("Remove Background", action: removeBackground)
                }
                if canTryBEN2 {
                    FileShelfDetailedRemovalItem(needsDownload: needsModelDownload, action: tryBEN2)
                }
            }
            if isImageFile {
                Button("Extract Text (OCR)", action: extractText)
                Button("Read QR or Barcode", action: decodeBarcode)
            }
            Button("Reveal in Finder", action: reveal)
            Divider()
            Button("Remove from File Shelf", action: remove)
        }
    }
}

struct ShelfIconStack: View {
    let files: [ShelfFile]

    private var stackWidth: CGFloat {
        files.count <= 1 ? 40 : min(40 + CGFloat(files.count - 1) * 14, 70)
    }

    var body: some View {
        ZStack {
            ForEach(Array(files.enumerated()), id: \.element.id) { index, file in
                FileIcon(path: file.url.path) { Color.clear }
                    .frame(width: 34, height: 34)
                    .background(FoundryTheme.stroke)
                    .clipShape(RoundedRectangle(cornerRadius: FoundryTheme.Radius.control, style: .continuous))
                    .rotationEffect(.degrees(Double(index - 1) * 5))
                    .offset(x: CGFloat(index) * 13)
            }
        }
        .frame(width: stackWidth, height: 42, alignment: .leading)
        .accessibilityHidden(true)
    }
}
