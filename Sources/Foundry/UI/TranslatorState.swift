import AppKit
import Combine
import Foundation

@MainActor
final class TranslatorState: ObservableObject {
    @Published var sourceText = "" { didSet { scheduleTranslation() } }
    @Published var sourceLanguage = "English" { didSet { scheduleTranslation() } }
    @Published var targetLanguage = "Spanish" { didSet { scheduleTranslation() } }
    @Published private(set) var result = ""
    @Published private(set) var translationError: String?
    @Published private(set) var isTranslating = false
    @Published private(set) var activeRequest: TranslationRequest?
    @Published private(set) var requestVersion = 0
    @Published var needsAppleTranslationFallback = false

    private let availability: TranslationAvailability
    private let translator: TranslationProvider.Translator
    private let debounce: Duration
    private var task: Task<Void, Never>?
    private var resetting = false

    init(availability: TranslationAvailability = .current, debounce: Duration = .milliseconds(450), translator: @escaping TranslationProvider.Translator = { await AppleTranslator.translate($0) }) {
        self.availability = availability
        self.debounce = debounce
        self.translator = translator
    }

    let languages = ["Arabic", "Chinese", "English", "French", "German", "Hindi", "Italian", "Japanese", "Korean", "Portuguese", "Russian", "Spanish"]

    func reset() {
        resetting = true
        task?.cancel()
        sourceText = ""
        sourceLanguage = "English"
        targetLanguage = "Spanish"
        result = ""
        translationError = nil
        isTranslating = false
        activeRequest = nil
        requestVersion = 0
        needsAppleTranslationFallback = false
        resetting = false
    }

    func translate() { scheduleTranslation() }

    func finish(_ outcome: TranslationOutcome, for request: TranslationRequest) {
        guard activeRequest?.id == request.id else { return }
        guard !Task.isCancelled else { return }
        switch outcome {
        case let .success(text): result = text; translationError = nil
        case .sessionRequired:
            result = ""; translationError = nil; needsAppleTranslationFallback = false
            isTranslating = true
            return
        case let .failure(error): result = ""; translationError = error.message
        }
        isTranslating = false
        activeRequest = nil
    }

    func requestAppleIntelligence() {
        guard let request = activeRequest ?? makeRequest() else { return }
        task?.cancel()
        activeRequest = request
        requestVersion += 1
        isTranslating = true
        task = Task { [weak self] in
            let outcome = await AppleTranslator.foundationModelsTranslation(request)
            guard !Task.isCancelled else { return }
            await MainActor.run { self?.finish(outcome, for: request) }
        }
    }

    func copyResult() {
        guard result.isEmpty == false else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(result, forType: .string)
    }

    func languageCode(for name: String) -> String? { TranslationLanguage.parse(name)?.identifier }

    private func scheduleTranslation() {
        guard !resetting else { return }
        task?.cancel()
        guard let request = makeRequest() else {
            result = ""; translationError = nil; isTranslating = false; activeRequest = nil
            return
        }
        guard availability == .translationFramework else {
            result = ""; translationError = TranslationFailure.unavailable.message; isTranslating = false; activeRequest = nil
            return
        }
        activeRequest = request
        if request.source == request.target { finish(.success(request.text), for: request); return }
        requestVersion += 1
        isTranslating = true
        task = Task { [weak self] in
            do { try await Task.sleep(for: self?.debounce ?? .zero) } catch { return }
            guard !Task.isCancelled else { return }
            let outcome = await self?.translator(request) ?? .failure(.cancelled)
            guard !Task.isCancelled else { return }
            await MainActor.run { self?.finish(outcome, for: request) }
        }
    }

    private func makeRequest() -> TranslationRequest? { TranslationRequest(text: sourceText, source: sourceLanguage, target: targetLanguage) }
}
