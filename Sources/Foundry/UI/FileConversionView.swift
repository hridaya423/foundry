import AppKit
import Foundation
import SwiftUI

struct FileConversionView: View {
    @ObservedObject var state: FileConversionState

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Source")
                        .font(FoundryTheme.body(size: 11, weight: .semibold))
                        .foregroundStyle(FoundryTheme.faintText)
                        .textCase(.uppercase)
                        .tracking(0.5)
                    Spacer()
                    Button("Choose File") { state.chooseSourceFile() }
                        .buttonStyle(PressableButtonStyle())
                        .font(FoundryTheme.body(size: 12, weight: .semibold))
                        .foregroundStyle(FoundryTheme.secondaryText)
                        .pointerCursor()
                }

                sourceCard
                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Convert To")
                        .font(FoundryTheme.body(size: 11, weight: .semibold))
                        .foregroundStyle(FoundryTheme.faintText)
                        .textCase(.uppercase)
                        .tracking(0.5)
                    Spacer()
                }

                settingsCard
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .alert("Additional Tool Required", isPresented: dependencyPromptBinding) {
            Button("Install and Convert") { state.confirmDependencyInstallation() }
            Button("Cancel", role: .cancel) { state.dependencyPrompt = nil }
        } message: {
            Text("Foundry needs \(state.dependencyPrompt ?? "an external tool") to convert this file. Homebrew will install it on your Mac.")
        }
    }

    private var dependencyPromptBinding: Binding<Bool> {
        Binding(
            get: { state.dependencyPrompt != nil },
            set: { isPresented in
                if isPresented == false { state.dependencyPrompt = nil }
            }
        )
    }

    private var sourceCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            if state.sourceURLs.count == 1, let sourceURL = state.sourceURL {
                HStack(alignment: .top, spacing: 12) {
                    Image(nsImage: IconCache.shared.icon(forFile: sourceURL.path))
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 42, height: 42)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(sourceURL.lastPathComponent)
                            .font(FoundryTheme.body(size: 15, weight: .semibold))
                            .foregroundStyle(FoundryTheme.primaryText)
                            .lineLimit(2)
                        Text(prettyFolder(sourceURL.deletingLastPathComponent()))
                            .font(FoundryTheme.body(size: 12, weight: .regular))
                            .foregroundStyle(FoundryTheme.mutedText)
                            .lineLimit(2)
                            .truncationMode(.middle)
                    }
                    Spacer(minLength: 0)
                    if sourceURL.pathExtension.isEmpty == false {
                        Text(sourceURL.pathExtension.uppercased())
                            .font(FoundryTheme.body(size: 10, weight: .bold))
                            .foregroundStyle(FoundryTheme.secondaryText)
                            .tracking(0.5)
                            .padding(.horizontal, 8)
                            .frame(height: 22)
                            .background(Color.white.opacity(0.08))
                            .clipShape(Capsule())
                    }
                }
                Spacer(minLength: 0)
            } else if state.sourceURLs.isEmpty == false {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 30, weight: .regular))
                            .foregroundStyle(FoundryTheme.secondaryText)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(state.sourceURLs.count) files selected")
                                .font(FoundryTheme.body(size: 15, weight: .semibold))
                                .foregroundStyle(FoundryTheme.primaryText)
                            Text("The same output format will be applied to each file.")
                                .font(FoundryTheme.body(size: 12, weight: .regular))
                                .foregroundStyle(FoundryTheme.mutedText)
                        }
                    }

                    ForEach(Array(state.sourceURLs.prefix(4)), id: \.self) { sourceURL in
                        HStack(spacing: 8) {
                            Image(nsImage: IconCache.shared.icon(forFile: sourceURL.path))
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 22, height: 22)
                            Text(sourceURL.lastPathComponent)
                                .font(FoundryTheme.body(size: 12, weight: .medium))
                                .foregroundStyle(FoundryTheme.secondaryText)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                        }
                    }

                    if state.sourceURLs.count > 4 {
                        Text("+\(state.sourceURLs.count - 4) more files")
                            .font(FoundryTheme.body(size: 12, weight: .medium))
                            .foregroundStyle(FoundryTheme.faintText)
                    }
                }
                Spacer(minLength: 0)
            } else {
                Button { state.chooseSourceFile() } label: {
                    VStack(spacing: 12) {
                        Image(systemName: "doc.badge.plus")
                            .font(.system(size: 30, weight: .regular))
                            .foregroundStyle(FoundryTheme.secondaryText)
                        Text("Choose a file to convert")
                            .font(FoundryTheme.body(size: 15, weight: .semibold))
                            .foregroundStyle(FoundryTheme.primaryText)
                        Text("or drop one onto Foundry")
                            .font(FoundryTheme.body(size: 12, weight: .regular))
                            .foregroundStyle(FoundryTheme.faintText)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .pointerCursor()
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 220, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.white.opacity(0.055))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.white.opacity(0.07), lineWidth: 1))
    }

    private var canConvert: Bool {
        state.sourceURLs.isEmpty == false && state.selectedTarget != nil && state.isConverting == false
    }

    private var settingsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            if state.availableTargets.isEmpty == false {
                fieldLabel("Format")

                Menu {
                    ForEach(groupedTargetCategories, id: \.self) { category in
                        Section(category.rawValue) {
                            ForEach(groupedTargets[category] ?? []) { target in
                                Button(target.title) { state.selectedTargetID = target.id }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(state.selectedTarget?.title ?? "Choose format")
                                .font(FoundryTheme.body(size: 14, weight: .semibold))
                                .foregroundStyle(FoundryTheme.primaryText)
                            if let category = state.selectedTarget?.category {
                                Text(category.rawValue)
                                    .font(FoundryTheme.body(size: 11, weight: .medium))
                                    .foregroundStyle(FoundryTheme.faintText)
                            }
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(FoundryTheme.mutedText)
                    }
                    .padding(.horizontal, 13)
                    .frame(height: 40)
                    .background(fieldBackground)
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .pointerCursor()

                fieldLabel("Save To")

                Button {
                    state.chooseOutputFolder()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "folder")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(FoundryTheme.mutedText)
                        Text(prettyFolder(state.outputFolderURL))
                            .font(FoundryTheme.body(size: 13, weight: .medium))
                            .foregroundStyle(FoundryTheme.primaryText)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 13)
                    .frame(height: 40)
                    .background(fieldBackground)
                }
                .buttonStyle(.plain)
                .pointerCursor()

                Spacer(minLength: 0)

                convertButton

                if let detail = statusDetail {
                    HStack(spacing: 6) {
                        Image(systemName: detail.icon)
                            .font(.system(size: 11, weight: .semibold))
                        Text(detail.text)
                            .font(FoundryTheme.body(size: 12, weight: .medium))
                            .lineLimit(2)
                    }
                    .foregroundStyle(detail.color)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                if state.outputURLs.isEmpty == false {
                    Button(state.outputURLs.count == 1 ? "Reveal in Finder" : "Reveal Outputs in Finder") { state.revealOutput() }
                        .buttonStyle(PressableButtonStyle())
                        .font(FoundryTheme.body(size: 12, weight: .semibold))
                        .foregroundStyle(FoundryTheme.secondaryText)
                        .frame(maxWidth: .infinity)
                        .pointerCursor()
                }
            } else if state.sourceURLs.isEmpty == false {
                Spacer(minLength: 0)
                VStack(spacing: 10) {
                    Image(systemName: "questionmark.folder")
                        .font(.system(size: 28, weight: .regular))
                        .foregroundStyle(FoundryTheme.mutedText)
                    Text("No converter for this file yet")
                        .font(FoundryTheme.body(size: 14, weight: .semibold))
                        .foregroundStyle(FoundryTheme.primaryText)
                    Text("Images, documents and PDFs work out of the box. Audio and video need ffmpeg installed.")
                        .font(FoundryTheme.body(size: 12, weight: .regular))
                        .foregroundStyle(FoundryTheme.faintText)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                Spacer(minLength: 0)
            } else {
                Spacer(minLength: 0)
                Text("Choose a file to see the formats you can convert it to.")
                    .font(FoundryTheme.body(size: 13, weight: .regular))
                    .foregroundStyle(FoundryTheme.faintText)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .multilineTextAlignment(.center)
                Spacer(minLength: 0)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 220, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.white.opacity(0.055))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.white.opacity(0.07), lineWidth: 1))
    }

    private var groupedTargets: [FileConversionTarget.Category: [FileConversionTarget]] {
        Dictionary(grouping: state.availableTargets, by: \.category)
    }

    private var groupedTargetCategories: [FileConversionTarget.Category] {
        FileConversionTarget.Category.allCases.filter { groupedTargets[$0]?.isEmpty == false }
    }

    private var convertButton: some View {
        Button { state.isConverting ? state.cancel() : state.convert() } label: {
            HStack(spacing: 8) {
                if state.isConverting {
                    ProgressView()
                        .controlSize(.small)
                        .tint(FoundryTheme.primaryText)
                }
                Text(
                    state.isConverting
                        ? "Cancel Conversion"
                        : state.sourceURLs.count > 1 ? "Convert \(state.sourceURLs.count) Files" : "Convert"
                )
                    .font(FoundryTheme.body(size: 14, weight: .bold))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .foregroundStyle(FoundryTheme.primaryText)
            .background(convertButtonGlass)
            .opacity(state.isConverting || canConvert ? 1 : 0.45)
        }
        .buttonStyle(PressableButtonStyle())
        .disabled(state.isConverting == false && canConvert == false)
        .keyboardShortcut(.defaultAction)
        .pointerCursor()
    }

    private var convertButtonGlass: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        return shape
            .fill(.ultraThinMaterial)
            .overlay {
                shape.fill(Color.white.opacity(0.10))
            }
            .overlay {
                shape.strokeBorder(Color.white.opacity(0.16), lineWidth: 1)
            }
            .compositingGroup()
            .shadow(color: Color.black.opacity(0.28), radius: 12, y: 6)
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(FoundryTheme.body(size: 11, weight: .semibold))
            .foregroundStyle(FoundryTheme.faintText)
            .textCase(.uppercase)
            .tracking(0.5)
    }

    private var fieldBackground: some View {
        RoundedRectangle(cornerRadius: 11, style: .continuous)
            .fill(Color.white.opacity(0.06))
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
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
            return (state.status, "checkmark.circle.fill", Color.green.opacity(0.85))
        }
        return (state.status, "exclamationmark.triangle.fill", Color.orange.opacity(0.9))
    }
}
