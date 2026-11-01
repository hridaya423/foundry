import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct FileShelfView: View {
    var state: FileShelfState
    let convertSelected: ([ShelfFile]) -> Void
    var extractText: (URL) -> Void = { _ in }
    var decodeBarcode: (URL) -> Void = { _ in }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isConfirmingClear = false

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
                    HStack(spacing: 7) {
                        Image(systemName: "tray.full")
                            .font(FoundryTheme.Glyph.xs)
                        Text(state.selectedIDs.isEmpty
                            ? "\(state.files.count) waiting"
                            : "\(state.selectedFiles.count) selected of \(state.files.count)")
                            .font(FoundryTheme.micro)
                            .textCase(.uppercase)
                            .tracking(0.5)
                    }
                    .foregroundStyle(FoundryTheme.textSecondary)

                    Spacer(minLength: 8)

                    if state.isRemovingBackground {
                        FoundryActionButton(
                            title: "Cancel",
                            systemName: "xmark",
                            action: state.cancelBackgroundRemoval
                        )
                    } else {
                        if state.isSettingUpBEN2 {
                            Button("Cancel BEN2 Setup", action: state.cancelBEN2Setup)
                        } else if state.ben2Assessment.modelState != .ready || state.ben2Assessment.runtimeState != .ready {
                            Menu {
                                Button("Set Up BEN2", action: state.setUpBEN2)
                                Button("Remove BEN2 Data", role: .destructive, action: state.removeBEN2Data)
                                Button("Cancel", role: .cancel) {}
                            } label: {
                                Label("BEN2 Setup", systemImage: "shippingbox")
                            }
                        }
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

                    FoundryIconButton(
                        systemName: "trash",
                        accessibilityLabel: "Clear file shelf",
                        action: { isConfirmingClear = true }
                    )
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
                                    isRemovingBackground: state.backgroundRemovalFileID == file.id && state.isRemovingBackground,
                                    reveal: { NSWorkspace.shared.activateFileViewerSelecting([file.url]) },
                                    removeBackground: {
                                        state.select(id: file.id)
                                        state.removeBackgroundFromSelected()
                                    },
                                    tryBEN2: {
                                        state.select(id: file.id)
                                        state.removeBackgroundWithBEN2()
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
        .alert("Clear File Shelf?", isPresented: $isConfirmingClear) {
            Button("Clear Shelf", role: .destructive) { state.clear() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Remove all waiting files from Foundry. The original files will not be deleted.")
        }
        .alert("Couldn't Remove Background", isPresented: backgroundRemovalErrorBinding) {
            if state.backgroundRemovalNeedsDestination {
                Button("Choose Save Location") { state.chooseBackgroundRemovalDestination() }
            }
            Button("Dismiss", role: .cancel) { state.dismissBackgroundRemovalError() }
        } message: {
            Text(state.backgroundRemovalError ?? "Foundry could not process this image.")
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
                Button {
                    state.removeBackgroundFromSelected()
                } label: {
                    Label("Standard (Vision)", systemImage: "wand.and.stars")
                }
            }

            if state.canRemoveBackgroundFromSelected && state.canTryExperimentalBackgroundRemovalFromSelected {
                Divider()
            }

            if state.canTryExperimentalBackgroundRemovalFromSelected {
                Button {
                    state.removeBackgroundWithBEN2()
                } label: {
                    Label("Try BEN2", systemImage: "wand.and.stars")
                }
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
        .help("Choose a background removal engine")
    }
}

struct FileShelfRow: View {
    let file: ShelfFile
    let isSelected: Bool
    let canRemoveBackground: Bool
    let canTryBEN2: Bool
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
        .padding(.horizontal, 12)
        .frame(height: 48)
        .background(RowBackground(isSelected: isSelected, isHovering: isHovering, cornerRadius: 10))
        .animation(reduceMotion ? nil : FoundryTheme.Motion.hover, value: isHovering)
        .onHover { hovering in
            isHovering = hovering

        }
        .accessibilityElement(children: .contain)
        .accessibilityHint("Select file")
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .contextMenu {
            if isRemovingBackground {
                Button("Cancel Background Removal", action: cancelBackgroundRemoval)
            } else if canRemoveBackground || canTryBEN2 {
                Menu {
                    if canRemoveBackground {
                        Button("Standard (Vision)", action: removeBackground)
                    }
                    if canRemoveBackground && canTryBEN2 {
                        Divider()
                    }
                    if canTryBEN2 {
                        Button("Try BEN2", action: tryBEN2)
                    }
                } label: {
                    Label("Remove Background", systemImage: "wand.and.stars")
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
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .rotationEffect(.degrees(Double(index - 1) * 5))
                    .offset(x: CGFloat(index) * 13)
            }
        }
        .frame(width: stackWidth, height: 42, alignment: .leading)
        .accessibilityHidden(true)
    }
}
