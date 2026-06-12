import Foundation

enum SearchScoring {
    static func score(query: String, title: String, aliases: [String] = []) -> Double? {
        let normalizedQuery = normalize(query)
        guard normalizedQuery.isEmpty == false else { return nil }

        let candidates = ([title] + aliases).map(normalize).filter { $0.isEmpty == false }
        return candidates.compactMap { score(normalizedQuery: normalizedQuery, candidate: $0) }.max()
    }

    private static func score(normalizedQuery query: String, candidate: String) -> Double? {
        if candidate == query { return 100 }
        if candidate.hasPrefix(query) { return 92 - Double(candidate.count - query.count) * 0.12 }

        let words = candidate.split(separator: " ").map(String.init)
        if words.contains(where: { $0.hasPrefix(query) }) { return 84 }

        let acronym = words.compactMap(\.first).map(String.init).joined()
        if acronym.hasPrefix(query) { return 80 }

        if candidate.contains(query) { return 68 - Double(candidate.count - query.count) * 0.08 }

        guard isSubsequence(query, of: candidate) else { return nil }
        let density = Double(query.count) / Double(candidate.count)
        return 42 + density * 18
    }

    private static func normalize(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private static func isSubsequence(_ needle: String, of haystack: String) -> Bool {
        var remaining = needle[...]
        for character in haystack where remaining.first == character {
            remaining.removeFirst()
            if remaining.isEmpty { return true }
        }
        return remaining.isEmpty
    }
}
