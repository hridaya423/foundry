import Foundation
import SwiftUI

#if canImport(Translation)
import Translation
#endif

struct TranslatorView: View {
    @Bindable var state: TranslatorState
    var insert: (() -> Bool)? = nil
    var targetAppName: String?

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                TranslatorPane(placeholder: "Enter text", text: $state.sourceText, isEditable: true, accessory: {
                    sourceLanguageMenu
                })

                Button(action: state.swapLanguages) {
                    Image(systemName: "arrow.left.arrow.right")
                        .font(FoundryTheme.Glyph.md)
                        .foregroundStyle(FoundryTheme.textSecondary)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Swap languages (⌘S)")
                .accessibilityLabel("Swap languages")

                TranslatorPane(placeholder: "Translation", text: Binding(get: { state.result }, set: { _ in }), isEditable: false, copy: state.copyResult) {
                    languageMenu
                }
            }

            HStack(spacing: 10) {
                if state.isTranslating {
                    ProgressView()
                        .controlSize(.small)
                    Text("Translating")
                        .font(FoundryTheme.body)
                        .foregroundStyle(FoundryTheme.textSecondary)
                }

                if let translationError = state.translationError {
                    if state.offersAppleIntelligence {
                        InlineNotice(level: .warning, text: "\(translationError)", actionTitle: "Try Apple Intelligence",
                            action: { state.requestAppleIntelligence() })
                    } else {
                        InlineNotice(level: .warning, text: "\(translationError)")
                    }
                }

                Spacer()

                if state.result.isEmpty == false, let insert {
                    FoundryActionButton(title: "Replace", systemName: "text.insert") {
                        _ = insert()
                    }
                    .help(String(localized: "Replace the selection in \(targetAppName ?? String(localized: "the previous app"))"))
                }
            }
            .frame(minHeight: FoundryTheme.Control.compact)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .background(translationBackend)
    }

    @ViewBuilder
    private var translationBackend: some View {
        #if canImport(Translation)
        if #available(macOS 15.0, *) {
            AppleTranslationTask(state: state, requestVersion: state.requestVersion)
        }
        #endif
    }

    private var languageMenu: some View {
        Menu {
            ForEach(state.languages, id: \.self) { language in
                Button(language) {
                    state.targetLanguage = language
                }
            }
        } label: {
            HStack(spacing: 5) {
                Text(state.targetLanguage)
                Image(systemName: "chevron.down")
                    .font(FoundryTheme.Glyph.xs)
            }
            .font(FoundryTheme.body)
            .foregroundStyle(FoundryTheme.textSecondary)
            .padding(.horizontal, 10)
            .frame(height: FoundryTheme.Control.mini)
            .background(FoundryTheme.fillTint)
            .clipShape(Capsule())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .accessibilityLabel("Target language")
    }

    private var sourceLabel: String {
        guard state.sourceLanguage == TranslatorState.detectLanguage else { return state.sourceLanguage }
        return state.detectedLanguage.map { String(localized: "\($0) (Detected)") } ?? TranslatorState.detectLanguage
    }

    private var sourceLanguageMenu: some View {
        Menu {
            Button(TranslatorState.detectLanguage) { state.sourceLanguage = TranslatorState.detectLanguage }
            Divider()
            ForEach(state.languages, id: \.self) { language in
                Button(language) {
                    state.sourceLanguage = language
                }
            }
        } label: {
            HStack(spacing: 5) {
                Text(sourceLabel)
                Image(systemName: "chevron.down")
                    .font(FoundryTheme.Glyph.xs)
            }
            .font(FoundryTheme.body)
            .foregroundStyle(FoundryTheme.textSecondary)
            .padding(.horizontal, 10)
            .frame(height: FoundryTheme.Control.mini)
            .background(FoundryTheme.fillTint)
            .clipShape(Capsule())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .accessibilityLabel("Source language")
    }
}

#if canImport(Translation)
@available(macOS 15.0, *)
struct AppleTranslationTask: View {
    @Bindable var state: TranslatorState
    let requestVersion: Int

    @State private var configuration: TranslationSession.Configuration?

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onAppear { configure() }
            .onChange(of: requestVersion) { _, _ in
                configure()
            }
            .translationTask(configuration) { session in
                guard let request = state.activeRequest else { return }
                let text = request.text
                do {
                    // TranslationSession is not Sendable but is only used
                    // inside this task's serial execution.
                    nonisolated(unsafe) let translationSession = session
                    let response = try await translationSession.translate(text)
                    state.finish(.success(response.targetText), for: request)
                } catch is CancellationError {
                    state.finish(.failure(.cancelled), for: request)
                } catch {
                    state.finish(.failure(.backend(error.localizedDescription)), for: request)
                }
            }
    }

    private func configure() {
        guard requestVersion > 0, let request = state.activeRequest,
              let sourceCode = state.languageCode(for: request.source.displayName),
              let targetCode = state.languageCode(for: request.target.displayName) else { return }
        configuration = TranslationSession.Configuration(
            source: Locale.Language(identifier: sourceCode),
            target: Locale.Language(identifier: targetCode)
        )
        configuration?.invalidate()
    }
}
#endif

struct TranslatorPane<Accessory: View>: View {
    let placeholder: String
    @Binding var text: String
    let isEditable: Bool
    var copy: (() -> Void)? = nil
    @ViewBuilder var accessory: () -> Accessory

    init(placeholder: String, text: Binding<String>, isEditable: Bool, copy: (() -> Void)? = nil,
        @ViewBuilder accessory: @escaping () -> Accessory = { EmptyView() }) {
        self.placeholder = placeholder
        self._text = text
        self.isEditable = isEditable
        self.copy = copy
        self.accessory = accessory
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                if isEditable {
                    HStack {
                        accessory()
                        Spacer()
                    }
                } else {
                    accessory()
                    if text.isEmpty == false, let copy {
                        Button(action: copy) {
                            Image(systemName: "doc.on.doc")
                                .font(FoundryTheme.Glyph.xs)
                                .foregroundStyle(FoundryTheme.textSecondary)
                                .frame(width: 26, height: 26)
                                .background(FoundryTheme.fillTint)
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Copy translation")
                        .help("Copy translation")
                    }
                }
                Spacer()
            }

            ZStack(alignment: .topLeading) {
                if text.isEmpty && isEditable == false {
                    Text(placeholder)
                        .font(FoundryTheme.title)
                        .foregroundStyle(FoundryTheme.textQuaternary)
                        .padding(.top, 8)
                        .padding(.leading, 4)
                }

                if isEditable {
                    TextField(placeholder, text: $text, axis: .vertical)
                        .font(FoundryTheme.title)
                        .foregroundStyle(FoundryTheme.textPrimary)
                        .textFieldStyle(.plain)
                        .background(Color.clear)
                        .lineLimit(8...12)
                        .padding(.top, 8)
                        .padding(.leading, 4)
                } else {
                    Text(text)
                        .font(FoundryTheme.title)
                        .foregroundStyle(FoundryTheme.textPrimary)
                        .textSelection(.enabled)
                        .padding(.top, 8)
                        .padding(.leading, 4)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 265, maxHeight: .infinity, alignment: .topLeading)
        .background(FoundryTheme.fillHover)
        .clipShape(RoundedRectangle(cornerRadius: FoundryTheme.Radius.overlay, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: FoundryTheme.Radius.overlay, style: .continuous)
                .stroke(FoundryTheme.fillTint, lineWidth: 1)
        )
    }
}
