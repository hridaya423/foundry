import Foundation

enum ResultSection: String, CaseIterable {
    case applications = "Applications"
    case commands = "Commands"
    case files = "Files"
    case notes = "Notes"
    case snippets = "Snippets"
    case browser = "Browser"
    case fallback = "Use Query With"

    static func of(_ result: CommandResult) -> ResultSection {
        switch result.route {
        case .browserTab, .browserBookmark, .browserHistory: return .browser
        case .notesSearch: return .notes
        default: break
        }
        if result.id.hasPrefix("file.") { return .files }
        switch result.primaryAction.kind {
        case .openApp: return .applications
        case .openQuickAI: return .fallback
        case .copySnippet, .pasteSnippet, .pasteText, .createSnippetFromClipboard, .importSnippets: return .snippets
        default: return .commands
        }
    }

    static func group(_ results: [CommandResult]) -> [(section: ResultSection, results: [CommandResult])] {
        guard let first = results.first else { return [] }
        var buckets: [ResultSection: [CommandResult]] = [:]
        for result in results {
            buckets[of(result), default: []].append(result)
        }
        let lead = of(first) == .fallback ? nil : of(first)
        let order = (lead.map { [$0] } ?? []) + allCases.filter { $0 != lead }
        return order.compactMap { section in
            buckets[section].map { (section, $0) }
        }
    }

    static func ordered(_ results: [CommandResult]) -> [CommandResult] {
        group(results).flatMap(\.results)
    }
}
