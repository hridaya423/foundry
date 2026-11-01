import AppKit
import FoundryDomain
import SwiftUI
import UniformTypeIdentifiers

struct MediaDownloadsView: View {
    var manager: MediaDownloadManager
    let start: (String) -> Int
    let cancel: (UUID) -> Void
    let retry: (MediaDownloadItem) -> Void
    let changeDestination: () -> Void
    var performHaptic: () -> Void = {}
    var notify: (ActionFeedback) -> Void = { _ in }
    var siteIcons = true

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
            withAnimation(FoundryTheme.Motion.overlayOut) { notice = nil }
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
                    .font(FoundryTheme.body)
                    .foregroundStyle(FoundryTheme.textPrimary)
                    .lineLimit(1)
                Text("Download complete")
                    .font(FoundryTheme.caption)
                    .foregroundStyle(FoundryTheme.textTertiary)
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
                    .font(FoundryTheme.Glyph.xs)
                    .foregroundStyle(FoundryTheme.textTertiary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: FoundryTheme.Radius.overlay, style: .continuous)
                .fill(FoundryTheme.fillTint)
                .overlay(
                    RoundedRectangle(cornerRadius: FoundryTheme.Radius.overlay, style: .continuous)
                        .strokeBorder(FoundryTheme.separator, lineWidth: 1)
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
                    .font(FoundryTheme.Glyph.sm)
                    .foregroundStyle(composerFocused ? FoundryTheme.accent : FoundryTheme.textTertiary)
                    .frame(width: 30, height: 30)
                    .background(FoundryTheme.fillHover)
                    .clipShape(RoundedRectangle(cornerRadius: FoundryTheme.Radius.control, style: .continuous))

                TextField("Paste one or more media links", text: $links, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(FoundryTheme.bodySecondary)
                    .foregroundStyle(FoundryTheme.textPrimary)
                    .lineLimit(1...3)
                    .focused($composerFocused)
                    .onChange(of: links) { _, _ in validationMessage = nil }
                    .onSubmit(submit)
                    .accessibilityLabel("Media links")
                    .accessibilityHint("Paste one or more supported media URLs")

                if links.isEmpty {
                    Button("Paste", action: pasteLinks)
                        .font(FoundryTheme.micro)
                        .foregroundStyle(FoundryTheme.textSecondary)
                        .buttonStyle(FoundryQuietButtonStyle())
                        .transition(.opacity)
                }

                Button(action: submit) {
                    HStack(spacing: 6) {
                        Text("Download")
                        Image(systemName: "arrow.down")
                            .font(FoundryTheme.Glyph.xs)
                    }
                    .font(FoundryTheme.body)
                    .foregroundStyle(FoundryTheme.prominentControlText.opacity(FoundryTheme.Alpha.strong))
                    .padding(.horizontal, 13)
                    .frame(height: 32)
                    .background(FoundryTheme.prominentControlFill.opacity(links.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.34 : 0.92))
                    .clipShape(RoundedRectangle(cornerRadius: FoundryTheme.Radius.control, style: .continuous))
                }
                .buttonStyle(PressableButtonStyle())
                .disabled(links.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .background(FoundryTheme.scrim)
            .clipShape(RoundedRectangle(cornerRadius: FoundryTheme.Radius.overlay, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: FoundryTheme.Radius.overlay, style: .continuous)
                    .stroke(composerFocused || isDropTargeted ? FoundryTheme.accent.opacity(FoundryTheme.Alpha.half) : FoundryTheme.fillTint, lineWidth: 1)
            )
            .onDrop(of: [.url, .plainText], isTargeted: $isDropTargeted) { providers in
                receiveDroppedLinks(providers)
            }

            if let validationMessage {
                Label(validationMessage, systemImage: "exclamationmark.circle.fill")
                    .font(FoundryTheme.caption)
                    .foregroundStyle(FoundryTheme.warning)
                    .transition(.opacity)
                    .padding(.leading, 4)
            } else {
                HStack(spacing: 5) {
                    Text("YouTube, playlists, social video, or direct media")
                    Text("·")
                    Text("↵ to download")
                        .font(FoundryTheme.mono)
                    Spacer()
                    if linkCount > 1 {
                        Text("\(linkCount) links")
                            .font(FoundryTheme.micro)
                            .foregroundStyle(FoundryTheme.accent)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(FoundryTheme.accentTintFill)
                            .clipShape(Capsule())
                            .contentTransition(.numericText())
                    }
                    if manager.activeCount > 0 {
                        Text("\(manager.activeCount) downloading")
                            .foregroundStyle(FoundryTheme.accent)
                            .contentTransition(.numericText())
                    }
                }
                .font(FoundryTheme.caption)
                .foregroundStyle(FoundryTheme.textQuaternary)
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
                        .foregroundStyle(FoundryTheme.accent)
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
            .font(FoundryTheme.caption)
            .foregroundStyle(FoundryTheme.textSecondary)
            .padding(.horizontal, 4)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .background(FoundryTheme.fillSubtle)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(FoundryTheme.fillTint)
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
                    .font(FoundryTheme.micro)
                    .foregroundStyle(FoundryTheme.textQuaternary)

                Text("\(items.count)")
                    .font(FoundryTheme.mono)
                    .foregroundStyle(FoundryTheme.textQuaternary)

                Spacer()

                if canClear {
                    Button("Clear List") { manager.clearFinished() }
                        .font(FoundryTheme.caption)
                        .foregroundStyle(FoundryTheme.textTertiary)
                        .buttonStyle(FoundryQuietButtonStyle())
                        .help("Clear finished, failed and cancelled downloads from this list. The files stay on disk.")
                }
            }
            .padding(.horizontal, 2)

            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    MediaDownloadRow(item: item, isSelected: selectedID == item.id,
                        faviconURL: Self.faviconURL(for: item.sourceURL, siteIcons: siteIcons),
                        cancel: cancel, retry: retry, redownload: { _ = start(item.sourceURL) }, notify: notify) {
                        manager.remove(id: item.id)
                    }
                    .onTapGesture { selectedID = selectedID == item.id ? nil : item.id }
                    .accessibilityHint(item.status == .active ? "" : "Delete removes this row")
                    if index < items.count - 1 {
                        Rectangle()
                            .fill(FoundryTheme.fillHover)
                            .frame(height: 1)
                            .padding(.leading, 48)
                    }
                }
            }
            .background(FoundryTheme.fillHover)
            .clipShape(RoundedRectangle(cornerRadius: FoundryTheme.Radius.overlay, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: FoundryTheme.Radius.overlay, style: .continuous)
                    .stroke(FoundryTheme.fillTint, lineWidth: 1)
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
            validationMessage = String(localized: "Paste a full video or audio URL, starting with https://.")
            return
        }
        links = MediaDownloadProvider.remainingInput(after: links)
        validationMessage = Self.skippedMessage(remaining: links)
        composerFocused = true
    }

    static func skippedMessage(remaining: String) -> String? {
        let count = remaining.split(whereSeparator: \.isWhitespace).count
        guard count > 0 else { return nil }
        return count == 1
            ? String(localized: "1 link isn’t supported and was left in the box.")
            : String(localized: "\(count) links aren’t supported and were left in the box.")
    }

    static func faviconURL(for source: String, siteIcons: Bool) -> URL? {
        guard siteIcons, let host = URL(string: source)?.host, host.isEmpty == false else { return nil }
        return URL(string: "https://icons.duckduckgo.com/ip3/\(host).ico")
    }

    private func pasteLinks() {
        guard let pasted = NSPasteboard.general.string(forType: .string), pasted.isEmpty == false else {
            validationMessage = String(localized: "The clipboard does not contain a link.")
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
    let isSelected: Bool
    let faviconURL: URL?
    let cancel: (UUID) -> Void
    let retry: (MediaDownloadItem) -> Void
    let redownload: () -> Void
    let notify: (ActionFeedback) -> Void
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
                        .font(FoundryTheme.body)
                        .foregroundStyle(FoundryTheme.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(item.progress.title)

                    if let current = item.progress.currentItem, let total = item.progress.totalItems {
                        Text("\(current) of \(total)")
                            .font(FoundryTheme.mono)
                            .foregroundStyle(FoundryTheme.textSecondary)
                            .padding(.horizontal, 6)
                            .frame(height: 18)
                            .background(FoundryTheme.fillTint)
                            .clipShape(Capsule())
                    }

                    Spacer(minLength: 4)

                    Text(statusLabel)
                        .font(FoundryTheme.micro)
                        .foregroundStyle(statusColor)
                        .contentTransition(.numericText())
                }

                if item.status == .active, let fraction = item.progress.fractionCompleted {
                    ZStack(alignment: .leading) {
                        Capsule().fill(FoundryTheme.fillTint)
                        Capsule()
                            .fill(FoundryTheme.accent)
                            .scaleEffect(x: max(fraction, 0.01), y: 1, anchor: .leading)
                            .animation(reduceMotion ? nil : FoundryTheme.Motion.progress, value: fraction)
                    }
                    .frame(height: 3)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Download progress")
                    .accessibilityValue("\(Int(fraction * 100)) percent")
                }

                HStack(spacing: 5) {
                    Text(fileError ?? detailText)
                        .font(FoundryTheme.caption)
                        .foregroundStyle(FoundryTheme.textTertiary)
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
        .background(RowBackground(isSelected: isSelected, isHovering: isHovering))
        .animation(reduceMotion ? nil : FoundryTheme.Motion.hover, value: isHovering)
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
            .clipShape(RoundedRectangle(cornerRadius: FoundryTheme.Radius.control, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: FoundryTheme.Radius.control, style: .continuous)
                    .strokeBorder(FoundryTheme.fillTint, lineWidth: 1)
            )

            if item.status != .active {
                statusBadge
            }
        }
    }

    private var hostIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: FoundryTheme.Radius.control, style: .continuous)
                .fill(statusColor.opacity(FoundryTheme.Alpha.subtle))

            if let faviconURL {
                RemoteIcon(url: faviconURL) { fallbackGlyph }
                    .padding(5)
            } else {
                fallbackGlyph
            }

            if item.status == .active, item.progress.fractionCompleted == nil {
                RoundedRectangle(cornerRadius: FoundryTheme.Radius.control, style: .continuous)
                    .fill(FoundryTheme.shadow)
                ProgressView()
                    .controlSize(.small)
                    .tint(.white)
                    .scaleEffect(0.8)
            }
        }
    }

    private var fallbackGlyph: some View {
        Image(systemName: "link")
            .font(FoundryTheme.Glyph.sm)
            .foregroundStyle(statusColor)
    }

    private var statusBadge: some View {
        Image(systemName: badgeSymbol)
            .font(FoundryTheme.Glyph.xs)
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
                notify(.success(String(localized: "Copied link")))
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
                    fileError = String(localized: "The saved files have been moved or deleted.")
                    return
                }
                if files.count == 1, let file = files.first {
                    NSWorkspace.shared.open(file)
                } else {
                    NSWorkspace.shared.activateFileViewerSelecting(files)
                }
            }
            .buttonStyle(FoundryQuietButtonStyle())
            .foregroundStyle(FoundryTheme.textSecondary)
        } else if item.status == .active {
            Button("Cancel") { cancel(item.id) }
                .buttonStyle(FoundryQuietButtonStyle())
                .foregroundStyle(FoundryTheme.textSecondary)
                .help("Cancel download")
        } else if item.status == .failed || item.status == .cancelled {
            Button("Retry") { retry(item) }
                .buttonStyle(FoundryQuietButtonStyle())
                .foregroundStyle(FoundryTheme.textSecondary)
                .help("Retry download")
        }

        if item.status != .active {
            Button(action: remove) {
                Image(systemName: "xmark")
            }
            .buttonStyle(FoundryQuietButtonStyle())
            .foregroundStyle(FoundryTheme.textTertiary)
            .help("Remove from list")
            .accessibilityLabel("Remove \(item.progress.title) from history")
        }
    }

    private var statusColor: Color {
        switch item.status {
        case .active: FoundryTheme.accent
        case .completed: FoundryTheme.success
        case .failed: FoundryTheme.destructive
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
