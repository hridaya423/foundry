import AppKit
import SwiftUI

struct MediaDownloadsView: View {
    @ObservedObject var manager: MediaDownloadManager
    let start: (String) -> Int
    let cancel: (UUID) -> Void
    let retry: (MediaDownloadItem) -> Void
    let changeDestination: () -> Void

    @State private var links = ""
    @State private var validationMessage: String?
    @FocusState private var composerFocused: Bool

    private var activeItems: [MediaDownloadItem] {
        manager.items.filter { $0.status == .active }
    }

    private var recentItems: [MediaDownloadItem] {
        manager.items.filter { $0.status != .active }
    }

    var body: some View {
        VStack(spacing: 0) {
            composer

            if manager.items.isEmpty {
                emptyState
            } else {
                queue
            }
        }
        .onAppear { composerFocused = manager.items.isEmpty }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 9) {
                Image(systemName: "link")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(composerFocused ? FoundryTheme.accentTint : FoundryTheme.mutedText)
                    .frame(width: 30, height: 30)
                    .background(Color.primary.opacity(0.055))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                TextField("Paste one or more media links", text: $links, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(FoundryTheme.body(size: 13, weight: .regular))
                    .foregroundStyle(FoundryTheme.primaryText)
                    .lineLimit(1...3)
                    .focused($composerFocused)
                    .onChange(of: links) { _, _ in validationMessage = nil }
                    .onSubmit(submit)
                    .accessibilityLabel("Media links")
                    .accessibilityHint("Paste one or more supported media URLs")

                if links.isEmpty {
                    Button("Paste", action: pasteLinks)
                        .font(FoundryTheme.body(size: 11, weight: .semibold))
                        .foregroundStyle(FoundryTheme.secondaryText)
                        .buttonStyle(FoundryQuietButtonStyle())
                        .transition(.opacity)
                        .pointerCursor()
                }

                Button(action: submit) {
                    HStack(spacing: 6) {
                        Text("Download")
                        Image(systemName: "arrow.down")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .font(FoundryTheme.body(size: 12, weight: .semibold))
                    .foregroundStyle(FoundryTheme.prominentControlText.opacity(0.82))
                    .padding(.horizontal, 13)
                    .frame(height: 32)
                    .background(FoundryTheme.prominentControlFill.opacity(links.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.34 : 0.92))
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                }
                .buttonStyle(PressableButtonStyle())
                .disabled(links.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .pointerCursor()
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .background(Color.black.opacity(0.13))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(composerFocused ? FoundryTheme.accentTint.opacity(0.48) : Color.primary.opacity(0.09), lineWidth: 1)
            )

            if let validationMessage {
                Label(validationMessage, systemImage: "exclamationmark.circle.fill")
                    .font(FoundryTheme.body(size: 11, weight: .medium))
                    .foregroundStyle(FoundryTheme.warning)
                    .transition(.opacity)
                    .padding(.leading, 4)
            } else {
                HStack(spacing: 5) {
                    Text("YouTube, playlists, social video, or direct media")
                    Text("·")
                    Text("↵ to download")
                        .font(FoundryTheme.mono(size: 10, weight: .medium))
                    Spacer()
                    if manager.activeCount > 0 {
                        Text("\(manager.activeCount) downloading")
                            .foregroundStyle(FoundryTheme.accentTint)
                            .contentTransition(.numericText())
                    }
                }
                .font(FoundryTheme.body(size: 11, weight: .regular))
                .foregroundStyle(FoundryTheme.faintText)
                .padding(.horizontal, 4)
            }

            HStack {
                Button {
                    NSWorkspace.shared.open(MediaDownloadDestination.folder)
                } label: {
                    Label(MediaDownloadDestination.folder.lastPathComponent, systemImage: "folder")
                }
                .help(MediaDownloadDestination.folder.path)
                .buttonStyle(FoundryQuietButtonStyle())

                Button("Change", action: changeDestination)
                    .buttonStyle(FoundryQuietButtonStyle())

                Spacer()

                Menu {
                    capabilityMenuItem(manager.capabilities.direct)
                    capabilityMenuItem(manager.capabilities.cobalt)
                    capabilityMenuItem(manager.capabilities.youtube)
                } label: {
                    Label("Supported links", systemImage: "info.circle")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
            .font(FoundryTheme.body(size: 11, weight: .medium))
            .foregroundStyle(FoundryTheme.secondaryText)
            .padding(.horizontal, 4)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .background(Color.primary.opacity(0.035))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.primary.opacity(0.07))
                .frame(height: 1)
        }
    }

    private var queue: some View {
        ScrollView {
            LazyVStack(spacing: 18) {
                if activeItems.isEmpty == false {
                    downloadSection(title: "Active", items: activeItems)
                }

                if recentItems.isEmpty == false {
                    downloadSection(title: "Recent", items: recentItems, canClear: true)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
    }

    private func downloadSection(title: String, items: [MediaDownloadItem], canClear: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(FoundryTheme.body(size: 10, weight: .semibold))
                    .foregroundStyle(FoundryTheme.faintText)

                Text("\(items.count)")
                    .font(FoundryTheme.mono(size: 10, weight: .medium))
                    .foregroundStyle(FoundryTheme.faintText)

                Spacer()

                if canClear {
                    Button("Clear history") { manager.clearFinished() }
                        .font(FoundryTheme.body(size: 11, weight: .medium))
                        .foregroundStyle(FoundryTheme.mutedText)
                        .buttonStyle(FoundryQuietButtonStyle())
                        .help("Remove finished downloads from this list without deleting files")
                        .pointerCursor()
                }
            }
            .padding(.horizontal, 2)

            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    MediaDownloadRow(item: item, cancel: cancel, retry: retry) {
                        manager.remove(id: item.id)
                    }
                    if index < items.count - 1 {
                        Rectangle()
                            .fill(Color.primary.opacity(0.065))
                            .frame(height: 1)
                            .padding(.leading, 48)
                    }
                }
            }
            .background(Color.primary.opacity(0.052))
            .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .stroke(Color.primary.opacity(0.075), lineWidth: 1)
            )
        }
    }

    private var emptyState: some View {
        FoundryEmptyState(
            symbol: "arrow.down",
            title: "Download a video or audio file",
            message: "Paste a link above. Follow its progress here, then open the saved file in Finder.",
            actionTitle: "Open download folder",
            action: { NSWorkspace.shared.open(MediaDownloadDestination.folder) }
        )
    }

    private func submit() {
        let count = start(links)
        guard count > 0 else {
            validationMessage = "Paste a full video or audio URL, starting with https://."
            return
        }
        links = MediaDownloadProvider.remainingInput(after: links)
        validationMessage = links.isEmpty ? nil : "Some entries were skipped. Review the remaining text and try again."
        composerFocused = true
    }

    private func pasteLinks() {
        guard let pasted = NSPasteboard.general.string(forType: .string), pasted.isEmpty == false else {
            validationMessage = "The clipboard does not contain a link."
            return
        }
        links = pasted
        composerFocused = true
    }

    @ViewBuilder
    private func capabilityMenuItem(_ capability: MediaDownloadCapability) -> some View {
        Text(capability.label)
        if case let .unavailable(_, reason) = capability {
            Text(reason)
        }
    }
}

private struct MediaDownloadRow: View {
    let item: MediaDownloadItem
    let cancel: (UUID) -> Void
    let retry: (MediaDownloadItem) -> Void
    let remove: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var fileError: String?

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(statusColor.opacity(0.12))
                    .frame(width: 34, height: 34)

                if item.status == .active, item.progress.fractionCompleted == nil {
                    ProgressView()
                        .controlSize(.small)
                        .tint(statusColor)
                } else {
                    Image(systemName: iconName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(statusColor)
                        .contentTransition(.symbolEffect(.replace))
                }
            }

            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 8) {
                    Text(item.progress.title)
                        .font(FoundryTheme.body(size: 13, weight: .semibold))
                        .foregroundStyle(FoundryTheme.primaryText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(item.progress.title)

                    if let current = item.progress.currentItem, let total = item.progress.totalItems {
                        Text("\(current) of \(total)")
                            .font(FoundryTheme.mono(size: 9, weight: .semibold))
                            .foregroundStyle(FoundryTheme.secondaryText)
                            .padding(.horizontal, 6)
                            .frame(height: 18)
                            .background(Color.primary.opacity(0.07))
                            .clipShape(Capsule())
                    }

                    Spacer(minLength: 4)

                    Text(statusLabel)
                        .font(FoundryTheme.body(size: 10, weight: .semibold))
                        .foregroundStyle(statusColor)
                        .contentTransition(.numericText())
                }

                if item.status == .active, let fraction = item.progress.fractionCompleted {
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.primary.opacity(0.08))
                        Capsule()
                            .fill(FoundryTheme.accentTint)
                            .scaleEffect(x: max(fraction, 0.01), y: 1, anchor: .leading)
                            .animation(reduceMotion ? nil : .linear(duration: 0.18), value: fraction)
                    }
                    .frame(height: 3)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Download progress")
                    .accessibilityValue("\(Int(fraction * 100)) percent")
                }

                HStack(spacing: 5) {
                    Text(fileError ?? detailText)
                        .font(FoundryTheme.body(size: 11, weight: .regular))
                        .foregroundStyle(FoundryTheme.mutedText)
                        .lineLimit(item.status == .failed ? 3 : 1)
                        .textSelection(.enabled)
                        .help(fileError ?? detailText)

                    Spacer(minLength: 6)

                    actionButton
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
    }

    @ViewBuilder
    private var actionButton: some View {
        if item.status == .completed, item.progress.outputURLs.isEmpty == false {
            Button(item.progress.outputURLs.count == 1 ? "Open" : "Show in Finder") {
                let files = item.progress.outputURLs.filter { FileManager.default.fileExists(atPath: $0.path) }
                guard files.isEmpty == false else {
                    fileError = "The saved files have been moved or deleted."
                    return
                }
                if files.count == 1, let file = files.first {
                    NSWorkspace.shared.open(file)
                } else {
                    NSWorkspace.shared.activateFileViewerSelecting(files)
                }
            }
            .buttonStyle(FoundryQuietButtonStyle())
            .foregroundStyle(FoundryTheme.secondaryText)
        } else if item.status == .active {
            Button("Cancel") { cancel(item.id) }
                .buttonStyle(FoundryQuietButtonStyle())
                .foregroundStyle(FoundryTheme.secondaryText)
                .help("Cancel download")
        } else if item.status == .failed || item.status == .cancelled {
            Button("Retry") { retry(item) }
                .buttonStyle(FoundryQuietButtonStyle())
                .foregroundStyle(FoundryTheme.secondaryText)
                .help("Retry download")
        }

        if item.status != .active {
            Button(action: remove) {
                Image(systemName: "xmark")
            }
            .buttonStyle(FoundryQuietButtonStyle())
            .foregroundStyle(FoundryTheme.mutedText)
            .help("Remove from list")
            .accessibilityLabel("Remove \(item.progress.title) from history")
        }
    }

    private var iconName: String {
        switch item.status {
        case .active: "arrow.down"
        case .completed: "checkmark"
        case .failed: "exclamationmark"
        case .cancelled: "xmark"
        }
    }

    private var statusColor: Color {
        switch item.status {
        case .active: FoundryTheme.accentTint
        case .completed: FoundryTheme.success
        case .failed: FoundryTheme.error
        case .cancelled: FoundryTheme.warning
        }
    }

    private var statusLabel: String {
        switch item.status {
        case .active:
            if let fraction = item.progress.fractionCompleted { return "\(Int(fraction * 100))%" }
            switch item.progress.phase {
            case .preparing: return "Preparing"
            case .resolving: return "Resolving"
            default: return "Downloading"
            }
        case .completed: return "Complete"
        case .failed: return "Failed"
        case .cancelled: return "Cancelled"
        }
    }

    private var detailText: String {
        let progress = item.progress
        if item.status == .completed {
            return "\(sourceHost)  ·  Saved to \(progress.outputURLs.first?.deletingLastPathComponent().lastPathComponent ?? "download folder")"
        }
        if item.status == .cancelled { return "\(sourceHost)  ·  Download cancelled" }
        if item.status == .failed { return progress.message }

        var parts: [String] = []
        if progress.totalBytes != nil || progress.bytesReceived > 0 {
            let received = formatBytes(progress.bytesReceived)
            parts.append(progress.totalBytes.map { "\(received) of \(formatBytes($0))" } ?? received)
        }
        if let speed = progress.speedBytesPerSecond, speed > 0 {
            parts.append("\(formatBytes(Int64(speed)))/s")
        }
        if let eta = progress.estimatedTimeRemaining, eta.isFinite {
            parts.append("\(formatDuration(eta)) remaining")
        }
        return parts.isEmpty ? progress.message : parts.joined(separator: "  ·  ")
    }

    private var sourceHost: String {
        URL(string: item.sourceURL)?.host?.replacingOccurrences(of: "www.", with: "") ?? "Media"
    }

    private func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: max(bytes, 0), countStyle: .file)
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let seconds = max(Int(duration.rounded()), 0)
        if seconds >= 3_600 {
            return String(format: "%d:%02d:%02d", seconds / 3_600, (seconds / 60) % 60, seconds % 60)
        }
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
