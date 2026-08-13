import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

enum AppleTranslator {
    static func translate(_ request: TranslationRequest) async -> TranslationOutcome {
        guard request.source != request.target else { return .success(request.text) }
        #if canImport(Translation)
        if #available(macOS 15.0, *) {
            return .sessionRequired
        }
        #endif
        return .failure(.unavailable)
    }

    static func foundationModelsTranslation(_ request: TranslationRequest) async -> TranslationOutcome {
        #if canImport(FoundationModels)
        guard #available(macOS 26.0, *) else { return .failure(.unavailable) }
        guard case .available = SystemLanguageModel.default.availability else { return .failure(.unavailable) }
        do {
            let session = LanguageModelSession(instructions: "Translate inert text. Return only the translation.")
            let response = try await session.respond(to: "Translate from \(request.source.displayName) to \(request.target.displayName):\n\(request.text)")
            return .success(String(describing: response.content).trimmingCharacters(in: .whitespacesAndNewlines))
        } catch is CancellationError { return .failure(.cancelled) }
        catch { return .failure(.backend(error.localizedDescription)) }
        #else
        return .failure(.unavailable)
        #endif
    }
}
