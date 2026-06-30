import Foundation

final class TranslationProvider: CommandProvider {
    let id = "foundry.translation"

    func results(matching query: String) async -> [CommandResult] {
        guard let request = Self.request(from: query) else { return [] }
        let translated = await AppleTranslator.translate(request.text, to: request.language)
        return [
            CommandResult(
                id: "translate.\(request.text).\(request.language)",
                title: translated,
                subtitle: "Translate to \(request.language.capitalized)",
                icon: CommandIcon(fallback: "TR", systemName: "globe"),
                score: 120,
                primaryAction: CommandAction(id: "translate.copy", title: "Copy Translation", kind: .copyToClipboard(translated)),
                secondaryActions: [
                    CommandAction(id: "translate.open", title: "Open Translator", kind: .openTranslator(text: request.text, language: request.language)),
                    CommandAction(id: "translate.copy-source", title: "Copy Source", kind: .copyToClipboard(request.text))
                ]
            )
        ]
    }

    static func request(from query: String) -> TranslationRequest? {
        var trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 4 else { return nil }
        if trimmed.lowercased().hasPrefix("translate ") {
            trimmed.removeFirst("translate ".count)
        }

        guard let range = trimmed.range(of: " to ", options: [.caseInsensitive, .backwards]) else { return nil }
        let text = String(trimmed[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        let language = String(trimmed[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.isEmpty == false, Self.isKnownLanguage(language) else { return nil }
        return TranslationRequest(text: text, language: language)
    }

    private static func isKnownLanguage(_ value: String) -> Bool {
        Locale.LanguageCode.isoLanguageCodes.contains { code in
            Locale.current.localizedString(forLanguageCode: code.identifier)?.lowercased() == value.lowercased()
        }
    }
}

struct TranslationRequest {
    let text: String
    let language: String
}
