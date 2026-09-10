import Foundation
import SwiftUI
import FoundryDomain

#if canImport(Translation)
import Translation
#endif

struct TranslatorView: View {
    @ObservedObject var state: TranslatorState

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                TranslatorPane(placeholder: "Enter text", text: $state.sourceText, isEditable: true, accessory: {
                    sourceLanguageMenu
                })

                Image(systemName: "arrow.right")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(FoundryTheme.secondaryText)

                TranslatorPane(placeholder: "Translation", text: Binding(get: { state.result }, set: { _ in }), isEditable: false, copy: state.copyResult) {
                    languageMenu
                }
            }

            HStack(spacing: 10) {
                if state.isTranslating {
                    ProgressView()
                        .controlSize(.small)
                    Text("Translating")
                        .font(FoundryTheme.body(size: 13, weight: .semibold))
                        .foregroundStyle(FoundryTheme.secondaryText)
                }

                if let translationError = state.translationError {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(FoundryTheme.warning)
                    Text(translationError)
                        .font(FoundryTheme.body(size: 12, weight: .medium))
                        .foregroundStyle(FoundryTheme.warning)
                        .lineLimit(2)
                }

                if state.translationError != nil {
                    FoundryActionButton(title: "Try Apple Intelligence", systemName: "apple.logo") {
                        state.requestAppleIntelligence()
                    }
                }

                Spacer()
            }
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
                    .font(.system(size: 9, weight: .bold))
            }
            .font(FoundryTheme.body(size: 12, weight: .semibold))
            .foregroundStyle(FoundryTheme.secondaryText)
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(Color.primary.opacity(0.07))
            .clipShape(Capsule())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .accessibilityLabel("Target language")
    }

    private var sourceLanguageMenu: some View {
        Menu {
            ForEach(state.languages, id: \.self) { language in
                Button(language) {
                    state.sourceLanguage = language
                }
            }
        } label: {
            HStack(spacing: 5) {
                Text(state.sourceLanguage)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
            }
            .font(FoundryTheme.body(size: 12, weight: .semibold))
            .foregroundStyle(FoundryTheme.secondaryText)
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(Color.primary.opacity(0.07))
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
    @ObservedObject var state: TranslatorState
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

    init(placeholder: String, text: Binding<String>, isEditable: Bool, copy: (() -> Void)? = nil, @ViewBuilder accessory: @escaping () -> Accessory = { EmptyView() }) {
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
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(FoundryTheme.secondaryText)
                                .frame(width: 26, height: 26)
                                .background(Color.primary.opacity(0.07))
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .pointerCursor()
                        .accessibilityLabel("Copy translation")
                        .help("Copy translation")
                    }
                }
                Spacer()
            }

            ZStack(alignment: .topLeading) {
                if text.isEmpty && isEditable == false {
                    Text(placeholder)
                        .font(FoundryTheme.body(size: 18, weight: .regular))
                        .foregroundStyle(FoundryTheme.faintText)
                        .padding(.top, 8)
                        .padding(.leading, 4)
                }

                if isEditable {
                    TextField(placeholder, text: $text, axis: .vertical)
                        .font(FoundryTheme.body(size: 18, weight: .regular))
                        .foregroundStyle(FoundryTheme.primaryText)
                        .textFieldStyle(.plain)
                        .background(Color.clear)
                        .lineLimit(8...12)
                        .padding(.top, 8)
                        .padding(.leading, 4)
                } else {
                    Text(text)
                        .font(FoundryTheme.display(size: 20, weight: .semibold))
                        .foregroundStyle(FoundryTheme.primaryText)
                        .textSelection(.enabled)
                        .padding(.top, 8)
                        .padding(.leading, 4)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 265, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.primary.opacity(0.055))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.primary.opacity(0.07), lineWidth: 1)
        )
    }
}
