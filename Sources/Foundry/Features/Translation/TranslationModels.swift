import Foundation

struct TranslationLanguage: Hashable, Sendable {
    let identifier: String
    let displayName: String
    private static let values = ["en":"English", "es":"Spanish", "fr":"French", "de":"German", "it":"Italian", "pt":"Portuguese", "ja":"Japanese", "ko":"Korean", "zh":"Chinese", "zh-Hans":"Chinese (Simplified)", "zh-Hant":"Chinese (Traditional)", "ru":"Russian", "ar":"Arabic", "hi":"Hindi"]
    static func parse(_ value: String) -> Self? {
        let input = normalize(value)
        guard let item = values.first(where: { normalize($0.key) == input || normalize($0.value) == input }) else { return nil }
        return Self(identifier: item.key, displayName: item.value)
    }

    private static func normalize(_ value: String) -> String {
        value.split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .folding(options: .caseInsensitive, locale: nil)
    }
}

struct TranslationRequest: Identifiable, Hashable, Sendable {
    let id: UUID
    let source: TranslationLanguage
    let target: TranslationLanguage
    let text: String
    init?(text: String, source: String, target: String, id: UUID = UUID()) {
        guard let source = TranslationLanguage.parse(source), let target = TranslationLanguage.parse(target) else { return nil }
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.isEmpty == false else { return nil }
        self.id = id; self.source = source; self.target = target; self.text = text
    }
    init?(text: String, language: String) { self.init(text: text, source: "en", target: language) }
}

enum TranslationFailure: Error, Equatable, Hashable, Sendable { case unavailable, unsupportedPair(source: String, target: String), asset, offline, cancelled, backend(String)
    var message: String { switch self { case .unavailable: "Translation is unavailable on this Mac."; case let .unsupportedPair(s, t): "Translation from \(s) to \(t) is not supported."; case .asset: "Translation assets are unavailable."; case .offline: "Translation is offline."; case .cancelled: "Translation was cancelled."; case let .backend(m): "Translation failed: \(m)" } }
}
enum TranslationOutcome: Sendable { case success(String), sessionRequired, failure(TranslationFailure) }

enum TranslationAvailability: Sendable {
    case translationFramework, unavailable

    static var current: Self {
        #if canImport(Translation)
        if #available(macOS 15.0, *) { return .translationFramework }
        #endif
        return .unavailable
    }
}
