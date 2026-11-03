import AppKit
import FoundryServices
import SwiftUI

extension FileConversionView {

    @ViewBuilder
    var resultsSection: some View {
        if state.itemOutcomes.isEmpty == false {
            VStack(alignment: .leading, spacing: 6) {
                fieldLabel("Results")
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(state.itemOutcomes) { outcome in
                            resultRow(outcome)
                        }
                    }
                }
                .scrollIndicators(.never)
                .frame(maxHeight: 120)
            }
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        }
    }

    func resultRow(_ outcome: FileConversionItemOutcome) -> some View {
        HStack(spacing: 9) {
            statusIcon(for: outcome.state)
                .frame(width: 16)
            Text(outcome.sourceURL.lastPathComponent)
                .font(FoundryTheme.caption)
                .foregroundStyle(FoundryTheme.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
            if let outputURL = outcome.outputURL {
                Image(systemName: "arrow.right")
                    .font(FoundryTheme.Glyph.xs)
                    .foregroundStyle(FoundryTheme.textQuaternary)
                Text(outputURL.lastPathComponent)
                    .font(FoundryTheme.caption)
                    .foregroundStyle(FoundryTheme.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 4)
            if let message = outcome.failure?.message, outcome.state == .failed {
                Text(message)
                    .font(FoundryTheme.caption)
                    .foregroundStyle(FoundryTheme.destructive)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(message)
            }
            if let outputURL = outcome.outputURL {
                sizeDelta(source: outcome.sourceURL, output: outputURL)
                FoundryIconButton(
                    systemName: "eye",
                    accessibilityLabel: "Quick Look \(outputURL.lastPathComponent)",
                    action: { state.onQuickLookOutput?(outputURL) }
                )
                FoundryIconButton(
                    systemName: "square.and.arrow.up",
                    accessibilityLabel: "Share \(outputURL.lastPathComponent)",
                    action: { state.onShareOutput?(outputURL) }
                )
            }
        }
        .frame(height: FoundryTheme.Control.compact)
    }

    func statusIcon(for state_: FileConversionItemState) -> some View {
        Group {
            switch state_ {
            case .pending:
                Image(systemName: "circle")
                    .foregroundStyle(FoundryTheme.textQuaternary)
            case .processing:
                ProgressView().controlSize(.mini)
            case .completed:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(FoundryTheme.success)
            case .failed:
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(FoundryTheme.destructive)
            case .cancelled:
                Image(systemName: "slash.circle")
                    .foregroundStyle(FoundryTheme.textTertiary)
            }
        }
        .font(FoundryTheme.Glyph.xs)
    }

    @ViewBuilder
    func sizeDelta(source: URL, output: URL) -> some View {
        let inSize = Self.byteCount(of: source)
        let outSize = Self.byteCount(of: output)
        if let inSize, let outSize, inSize > 0 {
            let ratio = Double(outSize) / Double(inSize)
            let delta = ratio - 1
            let color: Color = delta < -0.02 ? FoundryTheme.success : (delta > 0.05 ? FoundryTheme.warning : FoundryTheme.textQuaternary)
            Text("\(Self.formatBytes(outSize)) (\(delta >= 0 ? "+" : "")\(Int((delta * 100).rounded()))%)")
                .font(FoundryTheme.caption)
                .foregroundStyle(color)
        }
    }

    // MARK: Actions

    var actionArea: some View {
        VStack(spacing: 8) {
            convertButton

            if state.isConverting, let progress = state.progress {
                progressBar(progress)
            } else if state.status.isEmpty == false {
                InlineNotice(level: state.statusLevel, text: "\(state.status)")
            }

            if state.isConverting == false {
                HStack(spacing: 8) {
                    if state.outputURLs.isEmpty == false {
                        secondaryButton(state.outputURLs.count == 1 ? "Reveal in Finder" : "Reveal Outputs", icon: "folder") {
                            state.revealOutput()
                        }
                    }
                    if state.itemOutcomes.contains(where: { $0.state == .failed || $0.state == .cancelled }) {
                        secondaryButton("Retry Failed", icon: "arrow.clockwise") {
                            state.retryFailed()
                        }
                    }
                    if state.itemOutcomes.isEmpty == false || state.outputURLs.isEmpty == false {
                        secondaryButton("New Batch", icon: "plus") {
                            state.startOver()
                        }
                    }
                }
            }
        }
    }

    func secondaryButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(FoundryTheme.Glyph.xs)
                Text(title)
            }
            .font(FoundryTheme.micro)
            .foregroundStyle(FoundryTheme.textSecondary)
            .frame(maxWidth: .infinity)
            .frame(height: FoundryTheme.Control.compact)
            .background(FoundryTheme.fillHover)
            .clipShape(RoundedRectangle(cornerRadius: FoundryTheme.Radius.control, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: FoundryTheme.Radius.control, style: .continuous).stroke(FoundryTheme.fillTint, lineWidth: 1))
        }
        .buttonStyle(PressableButtonStyle())
    }

    func progressBar(_ progress: OperationProgress) -> some View {
        VStack(spacing: 5) {
            Group {
                switch progress {
                case let .items(completed, total):
                    if let total, total > 0 {
                        ProgressView(value: Double(completed), total: Double(total))
                    } else {
                        ProgressView()
                    }
                case let .bytes(completed, total):
                    if let total, total > 0 {
                        ProgressView(value: Double(completed), total: Double(total))
                    } else {
                        ProgressView()
                    }
                case .artifactBytes:
                    ProgressView()
                case .indeterminate:
                    ProgressView()
                }
            }
            .progressViewStyle(.linear)
            .tint(FoundryTheme.accent)
            if let status = progressLabel(progress) {
                Text(status)
                    .font(FoundryTheme.caption)
                    .foregroundStyle(FoundryTheme.textQuaternary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    func progressLabel(_ progress: OperationProgress) -> String? {
        switch progress {
        case let .items(completed, total):
            guard let total else { return "Working…" }
            return "\(completed) of \(total) files"
        case let .bytes(completed, _):
            return Self.formatBytes(completed)
        default:
            return nil
        }
    }

    var convertButton: some View {
        Button { state.isConverting ? state.cancel() : state.convert() } label: {
            HStack(spacing: 8) {
                if state.isConverting {
                    ProgressView()
                        .controlSize(.small)
                        .tint(FoundryTheme.textPrimary)
                }
                Text(
                    state.isConverting
                        ? "Cancel ⌘."
                        : state.sourceURLs.count > 1 ? "Convert \(state.sourceURLs.count) Files" : "Convert"
                )
                    .font(FoundryTheme.body)
            }
            .frame(maxWidth: .infinity)
            .frame(height: FoundryTheme.Control.row)
            .foregroundStyle(FoundryTheme.textPrimary)
            .background(convertButtonGlass)
            .opacity(state.isConverting || canConvert ? 1 : FoundryTheme.Alpha.half)
        }
        .buttonStyle(PressableButtonStyle())
        .disabled(state.isConverting == false && canConvert == false)
        .keyboardShortcut(Self.convertShortcut(isConverting: state.isConverting))
    }

    static func convertShortcut(isConverting: Bool) -> KeyboardShortcut {
        isConverting ? KeyboardShortcut(".", modifiers: .command) : .defaultAction
    }

    var convertButtonGlass: some View {
        RoundedRectangle(cornerRadius: FoundryTheme.Radius.control, style: .continuous)
            .fill(FoundryTheme.fillSelected)
            .overlay {
                RoundedRectangle(cornerRadius: FoundryTheme.Radius.control, style: .continuous).strokeBorder(FoundryTheme.stroke, lineWidth: 1)
            }
    }

    // MARK: Setup sheet

    func dependencySetupSheet(_ setup: DependencySetup) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: FoundryTheme.Radius.row, style: .continuous)
                        .fill(FoundryTheme.warning.opacity(FoundryTheme.Alpha.tint))
                    Image(systemName: "shippingbox")
                        .font(FoundryTheme.Glyph.md)
                        .foregroundStyle(FoundryTheme.warning)
                }
                .frame(width: 38, height: 38)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Install \(missingEngineNames(setup.plan))")
                        .font(FoundryTheme.body)
                    Text("Needed to convert to \(setup.target.title)")
                        .font(FoundryTheme.bodySecondary)
                        .foregroundStyle(FoundryTheme.textTertiary)
                }
            }

            Text(setup.plan.disclosure)
                .font(FoundryTheme.bodySecondary)
                .foregroundStyle(FoundryTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(setup.plan.commands.enumerated()), id: \.offset) { _, command in
                    Text(([command.executable] + command.arguments).joined(separator: " "))
                        .font(FoundryTheme.mono)
                        .foregroundStyle(FoundryTheme.textPrimary)
                        .textSelection(.enabled)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(FoundryTheme.fillHover)
            .clipShape(RoundedRectangle(cornerRadius: FoundryTheme.Radius.control, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: FoundryTheme.Radius.control, style: .continuous).stroke(FoundryTheme.fillTint, lineWidth: 1))

            HStack(spacing: 6) {
                if let bytes = setup.plan.estimatedDownloadBytes {
                    Label("~\(Self.formatBytes(bytes)) download", systemImage: "arrow.down.circle")
                }
                Label(setup.plan.mutationScope, systemImage: "externaldrive")
                Label(setup.plan.cleanupOwnership, systemImage: "trash")
            }
            .font(FoundryTheme.caption)
            .foregroundStyle(FoundryTheme.textQuaternary)

            HStack {
                Button("Cancel", role: .cancel) { state.cancelDependencySetup() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Install Only") { Task { await state.installTool() } }
                Button("Install and Convert") { Task { await state.installToolAndConvert() } }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 480)
    }

    // MARK: Helpers

    func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(FoundryTheme.micro)
            .foregroundStyle(FoundryTheme.textQuaternary)
    }

    var groupedTargets: [FileConversionTarget.Category: [FileConversionTarget]] {
        Dictionary(grouping: state.availableTargets, by: \.category)
    }

    var filteredTargets: [FileConversionTarget.Category: [FileConversionTarget]] {
        let query = formatFilter.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard query.isEmpty == false else { return groupedTargets }
        return groupedTargets.mapValues { targets in
            targets.filter { $0.title.lowercased().contains(query) || $0.outputExtension.lowercased().contains(query) }
        }
    }

    var filteredTargetCategories: [FileConversionTarget.Category] {
        FileConversionTarget.Category.allCases.filter { filteredTargets[$0]?.isEmpty == false }
    }

    func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(FoundryTheme.micro)
            .foregroundStyle(FoundryTheme.textQuaternary)
    }

    var fieldBackground: some View {
        RoundedRectangle(cornerRadius: FoundryTheme.Radius.row, style: .continuous)
            .fill(FoundryTheme.fillHover)
            .overlay(
                RoundedRectangle(cornerRadius: FoundryTheme.Radius.row, style: .continuous)
                    .stroke(FoundryTheme.fillTint, lineWidth: 1)
            )
    }

    func prettyFolder(_ url: URL?) -> String {
        guard let url else { return "Choose folder" }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let path = url.path
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }

    static func byteCount(of url: URL) -> Int64? {
        url.fileResourceValues([.fileSizeKey])?.fileSize.map { Int64($0) }
    }

    static func fileSize(of url: URL) -> String? {
        byteCount(of: url).map(formatBytes)
    }

    static func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

}
