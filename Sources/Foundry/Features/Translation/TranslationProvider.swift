import Foundation
import FoundryDomain

final class TranslationProvider: CommandProvider {
    typealias Translator = @Sendable (TranslationRequest) async -> TranslationOutcome
    private let translator: Translator
    let id = "foundry.translation"
    var searchPolicy: CommandProviderSearchPolicy { CommandProviderSearchPolicy(tier: .deferred) }
    init(translator: @escaping Translator = TranslationProvider.defaultTranslator) { self.translator = translator }
    func isActive(for query: String) -> Bool { Self.request(from: query) != nil }
    func search(_ searchRequest: CommandSearchRequest) async -> [CommandResult] {
        guard let request = Self.request(from: searchRequest.query) else { return [] }
        switch await translator(request) {
        case let .failure(failure): return [failureResult(request, failure)]
        case .sessionRequired: return [openTranslatorResult(request)]
        case let .success(text): return [CommandResult(id: "translate.\(request.id)", title: text, subtitle: "Apple Translation • Translate to \(request.target.displayName)", icon: CommandIcon(fallback: "TR", systemName: "globe"), route: .translation, primaryAction: CommandAction(id: "translate.copy", title: "Copy Translation", kind: .copyToClipboard(text)), secondaryActions: [CommandAction(id: "translate.open", title: "Open Translator", kind: .openTranslator(text: request.text, language: request.target.identifier)), CommandAction(id: "translate.copy-source", title: "Copy Source", kind: .copyToClipboard(request.text)), CommandAction(id: "translate.ai", title: "Try Apple Intelligence", kind: .openTranslator(text: request.text, language: request.target.identifier))])]
        }
    }
    static func request(from query: String) -> TranslationRequest? {
        var value = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.lowercased().hasPrefix("translate ") { value.removeFirst("translate ".count) }
        guard let range = value.range(of: " to ", options: [.caseInsensitive, .backwards]) else { return nil }
        return TranslationRequest(text: String(value[..<range.lowerBound]), source: "en", target: String(value[range.upperBound...]))
    }
    private func failureResult(_ request: TranslationRequest, _ failure: TranslationFailure) -> CommandResult { CommandResult(id: "translate.\(request.id)", title: failure.message, subtitle: "Open Translator to try again", icon: CommandIcon(fallback: "TR", systemName: "globe"), route: .translation, primaryAction: CommandAction(id: "translate.open", title: "Open Translator", kind: .openTranslator(text: request.text, language: request.target.identifier)), secondaryActions: [CommandAction(id: "translate.copy-source", title: "Copy Source", kind: .copyToClipboard(request.text))]) }
    private func openTranslatorResult(_ request: TranslationRequest) -> CommandResult { CommandResult(id: "translate.\(request.id)", title: "Translate with Apple Translation", subtitle: "Open Translator to complete the request", icon: CommandIcon(fallback: "TR", systemName: "globe"), route: .translation, primaryAction: CommandAction(id: "translate.open", title: "Translate", kind: .openTranslator(text: request.text, language: request.target.identifier)), secondaryActions: [CommandAction(id: "translate.copy-source", title: "Copy Source", kind: .copyToClipboard(request.text))]) }
    private static let defaultTranslator: Translator = { request in
        await AppleTranslator.translate(request)
    }
}
