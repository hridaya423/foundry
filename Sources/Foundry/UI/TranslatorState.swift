import AppKit
import Foundation

@MainActor
final class TranslatorState: ObservableObject {
    @Published var sourceText = "" {
        didSet { scheduleTranslation() }
    }
    @Published var targetLanguage = "Spanish" {
        didSet { scheduleTranslation() }
    }
    @Published var result = ""
    @Published var isTranslating = false
    @Published var needsAppleTranslationFallback = false
    @Published var requestVersion = 0

    private var task: Task<Void, Never>?
    private var isResetting = false

    let languages = Locale.LanguageCode.isoLanguageCodes
        .compactMap { Locale.current.localizedString(forLanguageCode: $0.identifier) }
        .map { $0.capitalized }
        .uniqued()
        .sorted()

    func reset() {
        isResetting = true
        sourceText = ""
        targetLanguage = "Spanish"
        result = ""
        isTranslating = false
        needsAppleTranslationFallback = false
        requestVersion = 0
        task?.cancel()
        isResetting = false
    }

    func translate() {
        scheduleTranslation()
    }

    private func scheduleTranslation() {
        guard isResetting == false else { return }
        startTranslation(debounce: true)
    }

    private func startTranslation(debounce: Bool) {
        task?.cancel()
        let text = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.isEmpty == false else {
            result = ""
            isTranslating = false
            needsAppleTranslationFallback = false
            return
        }
        task = Task { [weak self] in
            if debounce {
                do {
                    try await Task.sleep(for: .milliseconds(450))
                } catch {
                    return
                }
            }
            guard Task.isCancelled == false else { return }
            self?.isTranslating = true
            self?.needsAppleTranslationFallback = false
            self?.requestVersion += 1
        }
    }

    func finishTranslation(_ text: String) {
        result = text
        isTranslating = false
        needsAppleTranslationFallback = false
    }

    func requestAppleTranslationFallback() {
        needsAppleTranslationFallback = true
        isTranslating = true
        requestVersion += 1
    }

    func copyResult() {
        guard result.isEmpty == false else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(result, forType: .string)
    }

    func languageCode(for name: String) -> String? {
        Locale.LanguageCode.isoLanguageCodes.first { code in
            Locale.current.localizedString(forLanguageCode: code.identifier)?.capitalized == name
        }?.identifier
    }
}

private extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
