import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct MediaDownloadsView: View {
    var manager: MediaDownloadManager
    let start: (String) -> Int
    let cancel: (UUID) -> Void
    let retry: (MediaDownloadItem) -> Void
    let changeDestination: () -> Void
    var performHaptic: () -> Void = {}

    @State private var links = ""
    @State private var validationMessage: String?
    @State private var selectedID: UUID?
    @State private var notice: MediaDownloadItem?
    @State private var noticedCompletions: Set<UUID> = []
    @State private var noticeDismissTask: Task<Void, Never>?
    @State private var isDropTargeted = false
    @FocusState private var composerFocused: Bool

    private var totalSpeedText: String? {
        let speed = activeItems.compactMap(\.progress.speedBytesPerSecond).reduce(0, +)
        guard speed > 0 else { return nil }
        return ByteCountFormatter.string(fromByteCount: Int64(speed), countStyle: .binary) + "/s"
    }

    private var activeItems: [MediaDownloadItem] {
        manager.items.filter { $0.status == .active }
    }

    private var linkCount: Int {
        links.split(whereSeparator: \.isWhitespace).count
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
        .overlay(alignment: .bottom) {
            if let notice {
                completionNotice(notice)
                    .padding(14)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .background {
            ZStack {
                if let selectedID, manager.items.first(where: { $0.id == selectedID })?.status != .active {
                    Button("") {
                        manager.remove(id: selectedID)
                        self.selectedID = nil
                    }
                    .keyboardShortcut(.delete, modifiers: [])
                    .hidden()
                    .accessibilityLabel("Remove selected download")
                }
                if composerFocused == false {
                    Button("") { pasteLinks() }
                        .keyboardShortcut("v", modifiers: .command)
                        .hidden()
                        .accessibilityLabel("Paste links")
                }
            }
        }
        .onAppear {
            composerFocused = manager.items.isEmpty
            noticedCompletions = Set(manager.items.filter { $0.status == .completed }.map(\.id))
        }
        .onChange(of: manager.items) { _, items in
            if let newest = items.first(where: { $0.status == .completed && noticedCompletions.contains($0.id) == false }) {
                noticedCompletions.insert(newest.id)
                showNotice(newest)
            }
            noticedCompletions = noticedCompletions.intersection(Set(items.map(\.id)))
        }
    }

    private func showNotice(_ item: MediaDownloadItem) {
        noticeDismissTask?.cancel()
        notice = item
        performHaptic()
        noticeDismissTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(6))
            guard Task.isCancelled == false else { return }
            withAnimation(.easeOut(duration: 0.2)) { notice = nil }
        }
    }

    private func completionNotice(_ item: MediaDownloadItem) -> some View {
        HStack(spacing: 10) {
            if let path = item.progress.outputURLs.first?.path {
                FileIcon(path: path) { Color.clear }
                    .frame(width: 26, height: 26)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(item.progress.title)
                    .font(FoundryTheme.body(size: 12, weight: .semibold))
                    .foregroundStyle(FoundryTheme.primaryText)
                    .lineLimit(1)
                Text("Download complete")
                    .font(FoundryTheme.body(size: 11, weight: .regular))
                    .foregroundStyle(FoundryTheme.mutedText)
            }
            Spacer(minLength: 8)
            let files = item.progress.outputURLs.filter { FileManager.default.fileExists(atPath: $0.path) }
            if files.isEmpty == false {
                Button("Reveal") { NSWorkspace.shared.activateFileViewerSelecting(files); notice = nil }
                    .buttonStyle(FoundryQuietButtonStyle())
                if files.count == 1, let file = files.first {
                    Button("Open") { NSWorkspace.shared.open(file); notice = nil }
                        .buttonStyle(FoundryQuietButtonStyle())
                }
            }
            Button { notice = nil } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(FoundryTheme.mutedText)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss")
            .pointerCursor()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(Color.primary.opacity(0.07))
                .overlay(
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                )
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Download complete: \(item.progress.title)")
        .accessibilityHint("Reveal or open the downloaded file")
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
                    .stroke(composerFocused || isDropTargeted ? FoundryTheme.accentTint.opacity(0.48) : Color.primary.opacity(0.09), lineWidth: 1)
            )
            .onDrop(of: [.url, .plainText], isTargeted: $isDropTargeted) { providers in
                receiveDroppedLinks(providers)
            }

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
                    if linkCount > 1 {
                        Text("\(linkCount) links")
                            .font(FoundryTheme.body(size: 10, weight: .semibold))
                            .foregroundStyle(FoundryTheme.accentTint)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(FoundryTheme.accentTint.opacity(0.14))
                            .clipShape(Capsule())
                            .contentTransition(.numericText())
                    }
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

                if let totalSpeedText {
                    Text(totalSpeedText)
                        .foregroundStyle(FoundryTheme.accentTint)
                        .contentTransition(.numericText())
                        .help("Combined download speed")
                }

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
                    MediaDownloadRow(item: item, cancel: cancel, retry: retry, redownload: { _ = start(item.sourceURL) }) {
                        manager.remove(id: item.id)
                    }
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(FoundryTheme.accentTint.opacity(0.45), lineWidth: 1.5)
                            .padding(.horizontal, 3)
                            .opacity(selectedID == item.id ? 1 : 0)
                    )
                    .onTapGesture { selectedID = selectedID == item.id ? nil : item.id }
                    .accessibilityHint(item.status == .active ? "" : "Delete removes this row")
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

    private func receiveDroppedLinks(_ providers: [NSItemProvider]) -> Bool {
        var handled = false
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                handled = true
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    Task { @MainActor in appendDroppedLink(url.absoluteString) }
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                handled = true
                provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { item, _ in
                    guard let text = item as? String else { return }
                    Task { @MainActor in appendDroppedLink(text) }
                }
            }
        }
        return handled
    }

    private func appendDroppedLink(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return }
        links = links.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? trimmed : links + "\n" + trimmed
        validationMessage = nil
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
    let redownload: () -> Void
    let remove: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var fileError: String?
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 12) {
            leadingIcon

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
        .background(isHovering ? Color.primary.opacity(0.035) : .clear)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isHovering)
        .onHover { isHovering = $0 }
        .contextMenu { rowMenu }
    }

    private var leadingIcon: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if item.status == .completed, let path = item.progress.outputURLs.first?.path {
                    FileIcon(path: path) { hostIcon }
                } else {
                    hostIcon
                }
            }
            .frame(width: 34, height: 34)
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            )

            if item.status != .active {
                statusBadge
            }
        }
    }

    private var hostIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(statusColor.opacity(0.10))

            if let faviconURL {
                RemoteIcon(url: faviconURL) { fallbackGlyph }
                    .padding(5)
            } else {
                fallbackGlyph
            }

            if item.status == .active, item.progress.fractionCompleted == nil {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.black.opacity(0.35))
                ProgressView()
                    .controlSize(.small)
                    .tint(.white)
                    .scaleEffect(0.8)
            }
        }
    }

    private var fallbackGlyph: some View {
        Image(systemName: "link")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(statusColor)
    }

    private var statusBadge: some View {
        Image(systemName: badgeSymbol)
            .font(.system(size: 7, weight: .black))
            .foregroundStyle(.white)
            .frame(width: 13, height: 13)
            .background(statusColor)
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(Color(nsColor: .windowBackgroundColor), lineWidth: 1.5))
            .offset(x: 3, y: 3)
            .accessibilityHidden(true)
    }

    private var badgeSymbol: String {
        switch item.status {
        case .active: "arrow.down"
        case .completed: "checkmark"
        case .failed: "exclamationmark"
        case .cancelled: "xmark"
        }
    }

    private var faviconURL: URL? {
        guard let host = URL(string: item.sourceURL)?.host, host.isEmpty == false else { return nil }
        return URL(string: "https://icons.duckduckgo.com/ip3/\(host).ico")
    }

    @ViewBuilder
    private var rowMenu: some View {
        if item.status == .completed, item.progress.outputURLs.isEmpty == false {
            Button("Reveal in Finder") {
                let files = item.progress.outputURLs.filter { FileManager.default.fileExists(atPath: $0.path) }
                if files.isEmpty == false { NSWorkspace.shared.activateFileViewerSelecting(files) }
            }
            Button("Redownload") { redownload() }
        }
        if let url = URL(string: item.sourceURL) {
            Button("Open Source Page") { NSWorkspace.shared.open(url) }
            Button("Copy URL") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(item.sourceURL, forType: .string)
            }
        }
        if item.status == .failed || item.status == .cancelled {
            Divider()
            Button("Retry Download") { retry(item) }
        }
        if item.status != .active {
            Divider()
            Button("Remove from List") { remove() }
        }
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
