import AppKit
@preconcurrency import Foundation
import FoundryServices
import SwiftUI
import UniformTypeIdentifiers

struct FileConversionView: View {
    var state: FileConversionState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
@Environment(\.accessibilityReduceTransparency) var reduceTransparency
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
        .animation(reduceMotion ? nil : FoundryTheme.Motion.state, value: state.sourceURLs)
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
        .background(isDropTargeted ? FoundryTheme.fillSelected : FoundryTheme.fillHover)
        .clipShape(RoundedRectangle(cornerRadius: FoundryTheme.Radius.popover, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: FoundryTheme.Radius.popover, style: .continuous)
                .strokeBorder(
                    isDropTargeted ? FoundryTheme.selectionBorder : FoundryTheme.fillTint,
                    style: StrokeStyle(
                        lineWidth: isDropTargeted ? 1.5 : 1,
                        dash: state.sourceURLs.isEmpty ? [6, 5] : []
                    )
                )
        }
        .animation(reduceMotion ? nil : FoundryTheme.Motion.hover, value: isDropTargeted)
        .onDrop(of: [UTType.fileURL], isTargeted: $isDropTargeted, perform: handleDrop)
    }

    private var dropHero: some View {
        Button { state.chooseSourceFile() } label: {
            VStack(spacing: 10) {
                Image(systemName: "arrow.down.doc")
                    .font(FoundryTheme.Glyph.xl)
                    .foregroundStyle(isDropTargeted ? FoundryTheme.accent : FoundryTheme.textSecondary)
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

    var canConvert: Bool {
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

    func missingEngineNames(_ plan: SetupPlan) -> String {
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
                        optionRow("Longest Edge") {
                            optionMenu("Longest Edge", [(nil, "Original"), (4096, "4096 px"), (2048, "2048 px"), (1024, "1024 px"), (512, "512 px")],
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
                optionMenu("Name", Self.nameTemplates.map { ($0, nameExample($0)) },
                            get: { state.options.nameTemplate },
                            set: { state.options.nameTemplate = $0 })
            }
        }
    }

    static let nameTemplates: [String?] = [nil, "{name}-converted", "{name}-{date}"]

    private func nameExample(_ template: String?) -> String {
        guard let source = state.sourceURLs.first else { return template ?? String(localized: "Same") }
        return FileConversionService.renderNameTemplate(template, source: source, ext: state.selectedTarget?.id ?? "")
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
                .frame(width: 84, alignment: .leading)
            content()
            Spacer(minLength: 0)
        }
    }

    private func optionMenu<Value: Hashable>(_ title: String, _ pairs: [(Value?, String)],
                                            get: @escaping () -> Value?,
                                            set: @escaping (Value?) -> Void) -> some View {
        Picker(title, selection: Binding(get: get, set: set)) {
            ForEach(Array(pairs.enumerated()), id: \.offset) { _, pair in
                Text(pair.1).tag(pair.0)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .fixedSize()
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
                .animation(reduceMotion ? nil : FoundryTheme.Motion.hover, value: selected)
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

    @State var formatFilter = ""
}
