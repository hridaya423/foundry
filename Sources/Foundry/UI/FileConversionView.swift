import AppKit
@preconcurrency import Foundation
import FoundryServices
import SwiftUI
import UniformTypeIdentifiers

struct FileConversionView: View {
    var state: FileConversionState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isDropTargeted = false

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    sectionTitle("Sources")
                    if state.sourceURLs.isEmpty == false {
                        Text("\(state.sourceURLs.count)")
                            .font(FoundryTheme.micro)
                            .foregroundStyle(FoundryTheme.textSecondary)
                            .padding(.horizontal, 6)
                            .frame(height: 16)
                            .background(FoundryTheme.fillTint)
                            .clipShape(Capsule())
                    }
                    Spacer()
                    if state.sourceURLs.isEmpty == false {
                        Button { state.chooseSourceFile() } label: {
                            Image(systemName: "plus")
                                .font(FoundryTheme.Glyph.xs)
                        }
                        .buttonStyle(PressableButtonStyle())
                        .foregroundStyle(FoundryTheme.textSecondary)
                        .help("Add files")
                        .accessibilityLabel("Add files")
                        Button { state.startOver() } label: {
                            Image(systemName: "xmark")
                                .font(FoundryTheme.Glyph.xs)
                        }
                        .buttonStyle(PressableButtonStyle())
                        .foregroundStyle(FoundryTheme.textQuaternary)
                        .help("Clear all files")
                        .accessibilityLabel("Clear all files")
                    }
                }
                .frame(height: 18)

                sourceCard
                Spacer(minLength: 0)
            }
            .frame(width: 300)

            VStack(alignment: .leading, spacing: 10) {
                sectionTitle("Convert To")
                    .frame(height: 18, alignment: .bottomLeading)

                settingsCard
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: state.sourceURLs)
        .sheet(item: dependencySetupBinding, content: dependencySetupSheet)
    }

    private var dependencySetupBinding: Binding<DependencySetup?> {
        Binding(get: { state.dependencySetup }, set: { if $0 == nil { state.cancelDependencySetup() } })
    }

    // MARK: - Sources

    private var sourceCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            if state.sourceURLs.isEmpty {
                dropHero
            } else {
                sourceList
            }
        }
        .frame(maxWidth: .infinity, minHeight: 250, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.primary.opacity(isDropTargeted ? 0.09 : 0.055))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(
                    isDropTargeted ? FoundryTheme.warning.opacity(FoundryTheme.Alpha.faint) : FoundryTheme.fillTint,
                    style: StrokeStyle(
                        lineWidth: isDropTargeted ? 1.5 : 1,
                        dash: state.sourceURLs.isEmpty ? [6, 5] : []
                    )
                )
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isDropTargeted)
        .onDrop(of: [UTType.fileURL], isTargeted: $isDropTargeted, perform: handleDrop)
    }

    private var dropHero: some View {
        Button { state.chooseSourceFile() } label: {
            VStack(spacing: 10) {
                Image(systemName: "arrow.down.doc")
                    .font(FoundryTheme.Glyph.xl)
                    .foregroundStyle(isDropTargeted ? FoundryTheme.warning : FoundryTheme.textSecondary)
                Text(isDropTargeted ? "Drop to add files" : "Drop files here")
                    .font(FoundryTheme.body)
                    .foregroundStyle(FoundryTheme.textPrimary)
                Text("or click to choose — images, documents,\nmedia, archives")
                    .font(FoundryTheme.caption)
                    .foregroundStyle(FoundryTheme.textQuaternary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Choose or drop files to convert")
    }

    private var sourceList: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let first = state.sourceURL {
                sourceHero(first)
            }

            if state.sourceURLs.count > 1 {
                Divider().overlay(FoundryTheme.fillTint).padding(.leading, 16)
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(state.sourceURLs.dropFirst()), id: \.self) { url in
                            sourceRow(url)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .scrollIndicators(.never)
                .frame(maxHeight: 170)
            }

            Spacer(minLength: 6)

            HStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(FoundryTheme.Glyph.xs)
                Text("Drop more files or click to add")
                    .font(FoundryTheme.caption)
            }
            .foregroundStyle(FoundryTheme.textQuaternary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .contentShape(Rectangle())
            .onTapGesture { state.chooseSourceFile() }
        }
    }

    private func sourceHero(_ url: URL) -> some View {
        HStack(alignment: .center, spacing: 12) {
            FileIcon(path: url.path) { Color.clear }
                .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 3) {
                Text(url.lastPathComponent)
                    .font(FoundryTheme.body)
                    .foregroundStyle(FoundryTheme.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                HStack(spacing: 5) {
                    if let size = Self.fileSize(of: url) {
                        Text(size)
                        Text("·")
                    }
                    Text(prettyFolder(url.deletingLastPathComponent()))
                }
                .font(FoundryTheme.caption)
                .foregroundStyle(FoundryTheme.textTertiary)
                .lineLimit(1)
                .truncationMode(.middle)
            }
            Spacer(minLength: 0)
            extBadge(ConversionGraph.normalizedExtension(of: url))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private func sourceRow(_ url: URL) -> some View {
        HStack(spacing: 9) {
            FileIcon(path: url.path) { Color.clear }
                .frame(width: 20, height: 20)
            Text(url.lastPathComponent)
                .font(FoundryTheme.bodySecondary)
                .foregroundStyle(FoundryTheme.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 4)
            if let size = Self.fileSize(of: url) {
                Text(size)
                    .font(FoundryTheme.caption)
                    .foregroundStyle(FoundryTheme.textQuaternary)
            }
            extBadge(ConversionGraph.normalizedExtension(of: url))
            Button { state.removeSource(url: url) } label: {
                Image(systemName: "xmark")
                    .font(FoundryTheme.Glyph.xs)
                    .foregroundStyle(FoundryTheme.textQuaternary)
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Remove \(url.lastPathComponent)")
            .accessibilityLabel("Remove \(url.lastPathComponent)")
        }
        .padding(.horizontal, 16)
        .frame(height: 34)
    }

    private func extBadge(_ ext: String) -> some View {
        Text(ext.isEmpty ? "FILE" : ext.uppercased())
            .font(FoundryTheme.micro)
            .foregroundStyle(FoundryTheme.textSecondary)
            .tracking(0.5)
            .padding(.horizontal, 7)
            .frame(height: 20)
            .background(FoundryTheme.fillTint)
            .clipShape(Capsule())
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        let fileProviders = providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }
        guard fileProviders.isEmpty == false else { return false }
        Task { @MainActor in
            var urls: [URL] = []
            for provider in fileProviders {
                let item: NSSecureCoding?
                do {
                    item = try await provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier)
                } catch {
                    BestEffort.log("load dropped item", error)
                    item = nil
                }
                if let item {
                    if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                        urls.append(url)
                    } else if let url = item as? URL {
                        urls.append(url)
                    }
                }
            }
            state.addSources(urls: urls)
        }
        return true
    }

    // MARK: - Settings

    private var canConvert: Bool {
        state.sourceURLs.isEmpty == false && state.selectedTarget != nil && state.isConverting == false
    }

    private var settingsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            if state.availableTargets.isEmpty == false {
                formatSection
                setupBanner
                optionsSection
                saveToSection
                outputPreview
                resultsSection
                Spacer(minLength: 0)
                actionArea
            } else if state.sourceURLs.isEmpty == false {
                Spacer(minLength: 0)
                VStack(spacing: 8) {
                    Image(systemName: "questionmark.folder")
                        .font(FoundryTheme.Glyph.lg)
                        .foregroundStyle(FoundryTheme.textTertiary)
                    Text("No converter for this file yet")
                        .font(FoundryTheme.body)
                        .foregroundStyle(FoundryTheme.textPrimary)
                    Text("Images, documents, archives and PDFs work out of the box. Audio and video need FFmpeg.")
                        .font(FoundryTheme.caption)
                        .foregroundStyle(FoundryTheme.textQuaternary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity)
                Spacer(minLength: 0)
            } else {
                Spacer(minLength: 0)
                VStack(spacing: 8) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(FoundryTheme.Glyph.lg)
                        .foregroundStyle(FoundryTheme.textQuaternary)
                    Text("Add a file to see the formats\nit can become.")
                        .font(FoundryTheme.bodySecondary)
                        .foregroundStyle(FoundryTheme.textQuaternary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                Spacer(minLength: 0)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 250, maxHeight: .infinity, alignment: .topLeading)
        .background(FoundryTheme.fillHover)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(FoundryTheme.fillTint, lineWidth: 1))
    }

    // MARK: Format

    private var formatSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            fieldLabel("Format")

            if state.availableTargets.count > 8 {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(FoundryTheme.Glyph.xs)
                        .foregroundStyle(FoundryTheme.textQuaternary)
                    TextField("Filter formats…", text: $formatFilter)
                        .textFieldStyle(.plain)
                        .font(FoundryTheme.bodySecondary)
                        .foregroundStyle(FoundryTheme.textPrimary)
                    if formatFilter.isEmpty == false {
                        Button { formatFilter = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(FoundryTheme.Glyph.xs)
                                .foregroundStyle(FoundryTheme.textQuaternary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10)
                .frame(height: 26)
                .background(fieldBackground)
            }

            Menu {
                ForEach(filteredTargetCategories, id: \.self) { category in
                    Section(category.rawValue) {
                        ForEach(filteredTargets[category] ?? []) { target in
                            Button { state.selectedTargetID = target.id } label: {
                                HStack {
                                    Text(target.title)
                                    Spacer()
                                    Text(state.capability(for: target)?.readinessLabel ?? "Assessing…")
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(state.selectedTarget?.title ?? "Choose format")
                            .font(FoundryTheme.body)
                            .foregroundStyle(FoundryTheme.textPrimary)
                        HStack(spacing: 5) {
                            if let target = state.selectedTarget {
                                Text(target.category.rawValue)
                                Text("·")
                                Text(target.engineSummary)
                            }
                            if let capability = state.selectedTarget.flatMap(state.capability(for:)) {
                                readinessDot(capability)
                                Text(capability.readinessLabel)
                            }
                        }
                        .font(FoundryTheme.caption)
                        .foregroundStyle(FoundryTheme.textQuaternary)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(FoundryTheme.Glyph.xs)
                        .foregroundStyle(FoundryTheme.textTertiary)
                }
                .padding(.horizontal, 12)
                .frame(height: 46)
                .background(fieldBackground)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
        }
    }

    private func readinessDot(_ capability: FileConversionCapability) -> some View {
        Circle()
            .fill(readinessColor(capability))
            .frame(width: 5, height: 5)
    }

    private func readinessColor(_ capability: FileConversionCapability) -> Color {
        switch capability.state {
        case .ready: return FoundryTheme.success
        case .setupRequired: return FoundryTheme.warning
        case .unavailable, .degraded: return FoundryTheme.destructive
        }
    }

    @ViewBuilder
    private var setupBanner: some View {
        if let target = state.selectedTarget,
           let capability = state.capability(for: target),
           case let .setupRequired(plan) = capability.state {
            HStack(spacing: 10) {
            Image(systemName: "shippingbox")
                .font(FoundryTheme.Glyph.sm)
                .foregroundStyle(FoundryTheme.warning)
            VStack(alignment: .leading, spacing: 2) {
                Text("Requires \(missingEngineNames(plan))")
                    .font(FoundryTheme.body)
                    .foregroundStyle(FoundryTheme.textPrimary)
                Text("Installed once via Homebrew")
                    .font(FoundryTheme.caption)
                    .foregroundStyle(FoundryTheme.textQuaternary)
            }
            Spacer(minLength: 0)
            Button("Set Up") { state.convert() }
                .buttonStyle(PressableButtonStyle())
                .font(FoundryTheme.micro)
                .foregroundStyle(FoundryTheme.textSecondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(FoundryTheme.warning.opacity(FoundryTheme.Alpha.subtle))
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).stroke(FoundryTheme.warning.opacity(FoundryTheme.Alpha.tint), lineWidth: 1))
        }
    }

    private func missingEngineNames(_ plan: SetupPlan) -> String {
        let names = plan.commands.compactMap { command -> String? in
            command.arguments.last.flatMap { formula in
                switch formula {
                case "ffmpeg": return "FFmpeg"
                case "imagemagick": return "ImageMagick"
                case "pandoc": return "Pandoc"
                case "libreoffice": return "LibreOffice"
                default: return formula.capitalized
                }
            }
        }
        return names.isEmpty ? "an extra tool" : names.joined(separator: " + ")
    }

    // MARK: Options

    @ViewBuilder
    private var optionsSection: some View {
        if let target = state.selectedTarget {
            let kinds = target.applicableOptions
            if kinds.isEmpty == false {
                VStack(alignment: .leading, spacing: 8) {
                    if kinds.contains(.quality) {
                        optionRow("Quality") {
                            optionChips([(nil, "Auto"), (1.0, "Best"), (0.85, "High"), (0.6, "Small")],
                                        get: { state.options.quality },
                                        set: { state.options.quality = $0 })
                        }
                    }
                    if kinds.contains(.maxPixelSize) {
                        optionRow("Max Size") {
                            optionChips([(nil, "Full"), (4096, "4K"), (2048, "2K"), (1024, "1K"), (512, "512")],
                                        get: { state.options.maxPixelSize },
                                        set: { state.options.maxPixelSize = $0 })
                        }
                    }
                    if kinds.contains(.audioBitrate) {
                        optionRow("Bitrate") {
                            optionChips([(nil, "Auto"), (128, "128"), (192, "192"), (256, "256"), (320, "320")],
                                        get: { state.options.audioBitrateKbps },
                                        set: { state.options.audioBitrateKbps = $0 })
                        }
                    }
                    if kinds.contains(.dpiAndPages) {
                        optionRow("PDF DPI") {
                            optionChips([(nil, "144"), (216.0, "216"), (300.0, "300"), (600.0, "600")],
                                        get: { state.options.dpi },
                                        set: { state.options.dpi = $0 })
                        }
                        optionRow("Pages") {
                            TextField("All pages — e.g. 1-3, 5", text: pagesBinding)
                                .textFieldStyle(.plain)
                                .font(FoundryTheme.bodySecondary)
                                .foregroundStyle(FoundryTheme.textPrimary)
                                .padding(.horizontal, 10)
                                .frame(height: 26)
                                .background(fieldBackground)
                                .accessibilityLabel("PDF pages to convert")
                        }
                    }
                    if kinds.contains(.stripMetadata) {
                        optionRow("Metadata") {
                            optionChips([(false, "Keep"), (true, "Strip")],
                                        get: { state.options.stripMetadata },
                                        set: { state.options.stripMetadata = $0 ?? false })
                        }
                    }
                }
                .transition(.opacity)
            }
            optionRow("Name") {
                optionChips([(nil, "Same"), ("{name}-converted", "{name}-converted"), ("{name}-{date}", "{name}-{date}")],
                            get: { state.options.nameTemplate },
                            set: { state.options.nameTemplate = $0 })
            }
        }
    }

    private var pagesBinding: Binding<String> {
        Binding(
            get: { state.options.pages ?? "" },
            set: { state.options.pages = $0.isEmpty ? nil : $0 }
        )
    }

    private func optionRow<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Text(label)
                .font(FoundryTheme.micro)
                .foregroundStyle(FoundryTheme.textQuaternary)
                .frame(width: 58, alignment: .leading)
            content()
            Spacer(minLength: 0)
        }
    }

    private func optionChips<Value: Equatable>(_ pairs: [(Value?, String)],
                                             get: @escaping () -> Value?,
                                             set: @escaping (Value?) -> Void) -> some View {
        HStack(spacing: 5) {
            ForEach(Array(pairs.enumerated()), id: \.offset) { _, pair in
                let selected = get() == pair.0
                Button { set(pair.0) } label: {
                    Text(pair.1)
                        .font(FoundryTheme.micro)
                        .foregroundStyle(selected ? FoundryTheme.textPrimary : FoundryTheme.textTertiary)
                        .padding(.horizontal, 9)
                        .frame(height: 24)
                        .background(
                            Capsule().fill(selected ? FoundryTheme.fillEmphasis : FoundryTheme.fillHover)
                        )
                        .overlay(
                            Capsule().strokeBorder(selected ? FoundryTheme.stroke : FoundryTheme.fillHover, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.10), value: selected)
            }
        }
    }

    // MARK: Destination

    private var saveToSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            fieldLabel("Save To")

            Button { state.chooseOutputFolder() } label: {
                HStack(spacing: 8) {
                    Image(systemName: "folder")
                        .font(FoundryTheme.Glyph.xs)
                        .foregroundStyle(FoundryTheme.textTertiary)
                    Text(prettyFolder(state.outputFolderURL))
                        .font(FoundryTheme.bodySecondary)
                        .foregroundStyle(FoundryTheme.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(FoundryTheme.Glyph.xs)
                        .foregroundStyle(FoundryTheme.textQuaternary)
                }
                .padding(.horizontal, 12)
                .frame(height: 36)
                .background(fieldBackground)
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var outputPreview: some View {
        if let source = state.sourceURL, let target = state.selectedTarget {
            let name = previewOutputName(for: source, target: target)
            HStack(spacing: 5) {
                Image(systemName: "arrow.right")
                    .font(FoundryTheme.Glyph.xs)
                    .foregroundStyle(FoundryTheme.textQuaternary)
                Text(name)
                    .font(FoundryTheme.caption)
                    .foregroundStyle(FoundryTheme.textQuaternary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if state.sourceURLs.count > 1 {
                    Text("+ \(state.sourceURLs.count - 1) more")
                        .font(FoundryTheme.caption)
                        .foregroundStyle(FoundryTheme.textQuaternary)
                }
            }
        }
    }

    private func previewOutputName(for source: URL, target: FileConversionTarget) -> String {
        var base = source.lastPathComponent
        for compound in [".tar.gz", ".tar.bz2", ".tar.xz"] where base.lowercased().hasSuffix(compound) {
            base = String(base.dropLast(compound.count))
        }
        if let dot = base.lastIndex(of: ".") { base = String(base[..<dot]) }
        if target.outputExtension == ConversionGraph.extractExt {
            return "\(base)/ (extracted folder)"
        }
        return "\(base).\(target.outputExtension)"
    }

    // MARK: Results

    @ViewBuilder
    private var resultsSection: some View {
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

    private func resultRow(_ outcome: FileConversionItemOutcome) -> some View {
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
        .frame(height: 26)
    }

    private func statusIcon(for state_: FileConversionItemState) -> some View {
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
    private func sizeDelta(source: URL, output: URL) -> some View {
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

    private var actionArea: some View {
        VStack(spacing: 8) {
            convertButton

            if state.isConverting, let progress = state.progress {
                progressBar(progress)
            } else if let detail = statusDetail {
                HStack(spacing: 6) {
                    Image(systemName: detail.icon)
                        .font(FoundryTheme.Glyph.xs)
                    Text(detail.text)
                        .font(FoundryTheme.caption)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(detail.color)
                .frame(maxWidth: .infinity, alignment: .leading)
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

    private func secondaryButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(FoundryTheme.Glyph.xs)
                Text(title)
            }
            .font(FoundryTheme.micro)
            .foregroundStyle(FoundryTheme.textSecondary)
            .frame(maxWidth: .infinity)
            .frame(height: 28)
            .background(FoundryTheme.fillHover)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(FoundryTheme.fillTint, lineWidth: 1))
        }
        .buttonStyle(PressableButtonStyle())
    }

    private func progressBar(_ progress: OperationProgress) -> some View {
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
            .tint(FoundryTheme.warning)
            if let status = progressLabel(progress) {
                Text(status)
                    .font(FoundryTheme.caption)
                    .foregroundStyle(FoundryTheme.textQuaternary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func progressLabel(_ progress: OperationProgress) -> String? {
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

    private var convertButton: some View {
        Button { state.isConverting ? state.cancel() : state.convert() } label: {
            HStack(spacing: 8) {
                if state.isConverting {
                    ProgressView()
                        .controlSize(.small)
                        .tint(FoundryTheme.textPrimary)
                }
                Text(
                    state.isConverting
                        ? "Cancel Conversion"
                        : state.sourceURLs.count > 1 ? "Convert \(state.sourceURLs.count) Files" : "Convert"
                )
                    .font(FoundryTheme.body)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 42)
            .foregroundStyle(FoundryTheme.textPrimary)
            .background(convertButtonGlass)
            .opacity(state.isConverting || canConvert ? 1 : 0.45)
        }
        .buttonStyle(PressableButtonStyle())
        .disabled(state.isConverting == false && canConvert == false)
        .keyboardShortcut(.defaultAction)
    }

    private var convertButtonGlass: some View {
        let shape = RoundedRectangle(cornerRadius: 13, style: .continuous)
        return shape
            .fill(.ultraThinMaterial)
            .overlay {
                shape.fill(FoundryTheme.fillSelected)
            }
            .overlay {
                shape.strokeBorder(FoundryTheme.stroke, lineWidth: 1)
            }
            .compositingGroup()
            .shadow(color: FoundryTheme.shadow, radius: 12, y: 6)
    }

    // MARK: Setup sheet

    private func dependencySetupSheet(_ setup: DependencySetup) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
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
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(FoundryTheme.fillTint, lineWidth: 1))

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

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(FoundryTheme.micro)
            .foregroundStyle(FoundryTheme.textQuaternary)
            .textCase(.uppercase)
            .tracking(0.5)
    }

    private var groupedTargets: [FileConversionTarget.Category: [FileConversionTarget]] {
        Dictionary(grouping: state.availableTargets, by: \.category)
    }

    private var groupedTargetCategories: [FileConversionTarget.Category] {
        FileConversionTarget.Category.allCases.filter { groupedTargets[$0]?.isEmpty == false }
    }

    @State private var formatFilter = ""

    private var filteredTargets: [FileConversionTarget.Category: [FileConversionTarget]] {
        let query = formatFilter.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard query.isEmpty == false else { return groupedTargets }
        return groupedTargets.mapValues { targets in
            targets.filter { $0.title.lowercased().contains(query) || $0.outputExtension.lowercased().contains(query) }
        }
    }

    private var filteredTargetCategories: [FileConversionTarget.Category] {
        FileConversionTarget.Category.allCases.filter { filteredTargets[$0]?.isEmpty == false }
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(FoundryTheme.micro)
            .foregroundStyle(FoundryTheme.textQuaternary)
            .textCase(.uppercase)
            .tracking(0.5)
    }

    private var fieldBackground: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(FoundryTheme.fillHover)
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(FoundryTheme.fillTint, lineWidth: 1)
            )
    }

    private func prettyFolder(_ url: URL?) -> String {
        guard let url else { return "Choose folder" }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let path = url.path
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }

    private var statusDetail: (text: String, icon: String, color: Color)? {
        if state.isConverting { return nil }
        if state.status.isEmpty { return nil }
        if state.outputURL != nil {
            return (state.status, "checkmark.circle.fill", FoundryTheme.success)
        }
        return (state.status, "exclamationmark.triangle.fill", FoundryTheme.warning)
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
