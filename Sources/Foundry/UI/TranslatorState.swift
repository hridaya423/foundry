import AppKit
import Foundation
import NaturalLanguage
import Observation
import FoundryDomain

@MainActor
@Observable
final class TranslatorState {
    @ObservationIgnored var onFeedback: ((ActionFeedback) -> Void)?
    var sourceText = "" { didSet { scheduleTranslation() } }
    var sourceLanguage = TranslatorState.detectLanguage { didSet { languagesChanged() } }
    var targetLanguage = "Spanish" { didSet { languagesChanged() } }
    private(set) var detectedLanguage: String?
    private(set) var result = ""
    private(set) var translationError: String?
    private(set) var offersAppleIntelligence = false
    private(set) var isTranslating = false
    private(set) var activeRequest: TranslationRequest?
    private(set) var requestVersion = 0
    var needsAppleTranslationFallback = false

    private let availability: TranslationAvailability
    private let translator: TranslationProvider.Translator
    private let debounce: Duration
    private var task: Task<Void, Never>?
    private var resetting = false
    private let localState: LocalStateStore

    init(localState: LocalStateStore = .shared, availability: TranslationAvailability = .current, debounce: Duration = .milliseconds(450),
        translator: @escaping TranslationProvider.Translator = { await AppleTranslator.translate($0) }) {
        self.availability = availability
        self.debounce = debounce
        self.translator = translator
        self.localState = localState
        restoreLanguages()
    }

    private func restoreLanguages() {
        resetting = true
        if let source = localState.get(\.translatorSourceLanguage) { sourceLanguage = source }
        if let target = localState.get(\.translatorTargetLanguage) { targetLanguage = target }
        resetting = false
    }

    private func languagesChanged() {
        guard resetting == false else { return }
        localState.set(\.translatorSourceLanguage, sourceLanguage)
        localState.set(\.translatorTargetLanguage, targetLanguage)
        scheduleTranslation()
    }

    static let detectLanguage = "Detect Language"

    nonisolated static func detect(_ text: String) -> String? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        guard let code = recognizer.dominantLanguage?.rawValue else { return nil }
        return (TranslationLanguage.parse(code) ?? TranslationLanguage.parse(String(code.prefix(2))))?.displayName
    }

    let languages = ["Arabic", "Chinese", "English", "French", "German", "Hindi", "Italian", "Japanese", "Korean", "Portuguese", "Russian", "Spanish"]

    func reset() {
        resetting = true
        task?.cancel()
        sourceText = ""
        result = ""
        translationError = nil
        isTranslating = false
        activeRequest = nil
        requestVersion = 0
        needsAppleTranslationFallback = false
        resetting = false
    }

    func finish(_ outcome: TranslationOutcome, for request: TranslationRequest) {
        guard activeRequest?.id == request.id else { return }
        guard !Task.isCancelled else { return }
        switch outcome {
        case let .success(text): result = text; translationError = nil
        case .sessionRequired:
            result = ""; translationError = nil; needsAppleTranslationFallback = false
            isTranslating = true
            return
        case let .failure(error):
            result = ""; translationError = error.message
            if case .backend = error { offersAppleIntelligence = true }
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

    func translate(into language: String) {
        guard language != targetLanguage else { return }
        if language == sourceLanguage { sourceLanguage = targetLanguage }
        targetLanguage = language
    }

    func swapLanguages() {
        resetting = true
        let source = sourceLanguage == Self.detectLanguage ? detectedLanguage ?? "English" : sourceLanguage
        (sourceLanguage, targetLanguage) = (targetLanguage, source)
        if result.isEmpty == false { sourceText = result }
        resetting = false
        languagesChanged()
    }

    func copyResult() {
        guard result.isEmpty == false else { return }
        NSPasteboard.general.copy(result)
        onFeedback?(.success(String(localized: "Copied translation")))
    }

    func languageCode(for name: String) -> String? { TranslationLanguage.parse(name)?.identifier }

    private func scheduleTranslation() {
        guard !resetting else { return }
        task?.cancel()
        offersAppleIntelligence = false
        guard let request = makeRequest() else {
            result = ""; isTranslating = false; activeRequest = nil
            let undetected = sourceLanguage == Self.detectLanguage && sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            translationError = undetected ? String(localized: "Foundry can’t tell which language this is. Choose it from the menu.") : nil
            return
        }
        guard availability == .translationFramework else {
            result = ""; translationError = TranslationFailure.unavailable.message; isTranslating = false; activeRequest = nil
            return
        }
        activeRequest = request
        if request.source == request.target { finish(.success(request.text), for: request); return }
        requestVersion += 1
        task = Task { [weak self] in
            do { try await Task.sleep(for: self?.debounce ?? .zero) } catch { return }
            guard !Task.isCancelled else { return }
            self?.isTranslating = true
            let outcome = await self?.translator(request) ?? .failure(.cancelled)
            guard !Task.isCancelled else { return }
            await MainActor.run { self?.finish(outcome, for: request) }
        }
    }

    private func makeRequest() -> TranslationRequest? {
        guard sourceLanguage == Self.detectLanguage else {
            detectedLanguage = nil
            return TranslationRequest(text: sourceText, source: sourceLanguage, target: targetLanguage)
        }
        detectedLanguage = Self.detect(sourceText)
        return detectedLanguage.flatMap { TranslationRequest(text: sourceText, source: $0, target: targetLanguage) }
    }
}
