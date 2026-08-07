import AppKit
import SwiftUI

struct FileShelfView: View {
    @ObservedObject var state: FileShelfState
    let convertSelected: () -> Void
    @State private var isConfirmingClear = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if state.files.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "tray.and.arrow.down")
                        .font(.system(size: 34, weight: .regular))
                        .foregroundStyle(FoundryTheme.secondaryText)
                    Text("Drop files anywhere on Foundry")
                        .font(FoundryTheme.body(size: 16, weight: .semibold))
                        .foregroundStyle(FoundryTheme.primaryText)
                    Text("They stay here temporarily until you remove them or quit.")
                        .font(FoundryTheme.body(size: 13, weight: .regular))
                        .foregroundStyle(FoundryTheme.secondaryText)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack {
                    Text("\(state.files.count) file\(state.files.count == 1 ? "" : "s") waiting")
                        .font(FoundryTheme.body(size: 11, weight: .semibold))
                        .foregroundStyle(FoundryTheme.faintText)
                        .textCase(.uppercase)
                        .tracking(0.5)
                    Spacer()
                    if state.selectedFile != nil {
                        Button("Convert") { convertSelected() }
                            .buttonStyle(PressableButtonStyle())
                            .font(FoundryTheme.body(size: 12, weight: .semibold))
                            .foregroundStyle(FoundryTheme.mutedText)
                            .pointerCursor()
                    }
                    if state.isRemovingBackground {
                        Button("Cancel") { state.cancelBackgroundRemoval() }
                            .buttonStyle(PressableButtonStyle())
                            .font(FoundryTheme.body(size: 12, weight: .semibold))
                            .foregroundStyle(FoundryTheme.mutedText)
                            .pointerCursor()
                    } else if state.canRemoveBackgroundFromSelected {
                        Button("Remove Background") { state.removeBackgroundFromSelected() }
                            .buttonStyle(PressableButtonStyle())
                            .font(FoundryTheme.body(size: 12, weight: .semibold))
                            .foregroundStyle(FoundryTheme.mutedText)
                            .pointerCursor()
                    }
                    if state.canTryExperimentalBackgroundRemovalFromSelected {
                        Button("Try BEN2") { state.removeBackgroundWithBEN2() }
                            .buttonStyle(PressableButtonStyle())
                            .font(FoundryTheme.body(size: 12, weight: .semibold))
                            .foregroundStyle(FoundryTheme.mutedText)
                            .pointerCursor()
                    }
                    Button("Clear") { isConfirmingClear = true }
                        .buttonStyle(PressableButtonStyle())
                        .font(FoundryTheme.body(size: 12, weight: .semibold))
                        .foregroundStyle(FoundryTheme.mutedText)
                        .pointerCursor()
                }
                .padding(.horizontal, 4)

                if state.backgroundRemovalStatus.isEmpty == false {
                    HStack(spacing: 6) {
                        if state.isRemovingBackground {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: state.backgroundRemovalError == nil ? "checkmark.circle" : "exclamationmark.triangle")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        Text(state.backgroundRemovalStatus)
                            .lineLimit(1)
                    }
                    .font(FoundryTheme.body(size: 12, weight: .medium))
                    .foregroundStyle(state.backgroundRemovalError == nil ? FoundryTheme.secondaryText : Color.orange.opacity(0.9))
                    .padding(.horizontal, 4)
                }

                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(state.files) { file in
                            FileShelfRow(
                                file: file,
                                isSelected: state.selectedID == file.id,
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
                                remove: { state.remove(id: file.id) }
                            )
                            .id(file.id)
                            .contentShape(Rectangle())
                            .onTapGesture { state.select(id: file.id) }
                            .onDrag { NSItemProvider(object: file.url as NSURL) }
                        }
                    }
                }
                .scrollIndicators(.never)
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
    let remove: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 12) {
            Image(nsImage: IconCache.shared.icon(forFile: file.url.path))
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text(file.name)
                    .font(FoundryTheme.body(size: 14, weight: .medium))
                    .foregroundStyle(FoundryTheme.primaryText)
                    .lineLimit(1)
                Text(file.location)
                    .font(FoundryTheme.body(size: 12, weight: .regular))
                    .foregroundStyle(FoundryTheme.mutedText)
                    .lineLimit(1)
            }

            Spacer()

            if isSelected || isHovering {
                Button(action: reveal) {
                    Image(systemName: "folder")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(FoundryTheme.mutedText)
                        .frame(width: 26, height: 26)
                        .background(Color.white.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                .buttonStyle(PressableButtonStyle())
                .pointerCursor()
                .accessibilityLabel("Reveal \(file.name) in Finder")
                .help("Reveal in Finder")

                Button(action: remove) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(FoundryTheme.mutedText)
                        .frame(width: 26, height: 26)
                        .background(Color.white.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                .buttonStyle(PressableButtonStyle())
                .pointerCursor()
                .accessibilityLabel("Remove \(file.name) from File Shelf")
                .help("Remove from File Shelf")
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 48)
        .background(RowBackground(isSelected: isSelected, isHovering: isHovering, cornerRadius: 10))
        .animation(.easeOut(duration: 0.10), value: isSelected)
        .animation(.easeOut(duration: 0.12), value: isHovering)
        .onHover { hovering in
            isHovering = hovering
            if hovering { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
        }
        .contextMenu {
            if isRemovingBackground {
                Button("Cancel Background Removal", action: cancelBackgroundRemoval)
            } else if canRemoveBackground {
                Button("Remove Background", action: removeBackground)
            }
            if canTryBEN2 {
                Button("Try BEN2", action: tryBEN2)
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
                Image(nsImage: IconCache.shared.icon(forFile: file.url.path))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 34, height: 34)
                    .background(Color.white.opacity(0.16))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .rotationEffect(.degrees(Double(index - 1) * 5))
                    .offset(x: CGFloat(index) * 13)
            }
        }
        .frame(width: stackWidth, height: 42, alignment: .leading)
    }
}
