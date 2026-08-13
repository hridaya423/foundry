import Foundation

/// The event-driven, platform-independent core of snippet expansion. AppKit event
/// taps translate keyboard events into these inputs; this type never observes them.
struct SnippetExpansionEngine {
    enum Input: Equatable {
        case character(String)
        case delimiter(String)
        case backspace
        case modifier
        case navigation
        case appChanged(bundleIdentifier: String?)
        case secureInputChanged(Bool)
        case nonText
        case oversize
        case reset
    }

    struct Expansion: Equatable {
        let keyword: String
        let renderedContent: String
        let delimiter: String
        let deleteCount: Int
    }

    enum Output: Equatable {
        case ignored
        case expanded(Expansion)
    }

    private(set) var buffer = ""
    private(set) var isEnabled = true
    private(set) var isSecureInput = false
    private(set) var currentBundleIdentifier: String?

    private let snippets: [String: StoredSnippet]
    private let ambiguousKeywords: Set<String>
    private let excludedBundleIdentifiers: Set<String>
    private let render: (StoredSnippet) -> String
    private let maxBufferLength: Int

    init(
        snippets: [StoredSnippet],
        excludedBundleIdentifiers: [String] = [],
        maxBufferLength: Int = 64,
        render: @escaping (StoredSnippet) -> String = { $0.content }
    ) {
        self.snippets = Self.normalized(snippets)
        self.ambiguousKeywords = Set(Dictionary(grouping: snippets.filter { !$0.keyword.isEmpty }, by: \ .keyword).filter { $0.value.count > 1 }.keys)
        self.excludedBundleIdentifiers = Set(excludedBundleIdentifiers)
        self.maxBufferLength = max(1, maxBufferLength)
        self.render = render
    }

    mutating func receive(_ input: Input) -> Output {
        switch input {
        case let .character(value):
            guard isEnabled, !isSecureInput, value.count == 1, value.first?.isWhitespace == false else {
                buffer = ""
                return .ignored
            }
            buffer.append(contentsOf: value)
            if buffer.count > maxBufferLength { buffer = "" }
            return .ignored
        case let .delimiter(value):
            guard isEnabled, !isSecureInput else { buffer = ""; return .ignored }
            return expand(using: value)
        case .backspace:
            guard buffer.isEmpty == false else { return .ignored }
            buffer.removeLast()
            return .ignored
        case .modifier, .navigation, .nonText, .oversize, .reset:
            buffer = ""
            return .ignored
        case let .appChanged(bundleIdentifier):
            currentBundleIdentifier = bundleIdentifier
            buffer = ""
            return .ignored
        case let .secureInputChanged(value):
            isSecureInput = value
            buffer = ""
            return .ignored
        }
    }

    mutating func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        if !enabled { buffer = "" }
    }

    private mutating func expand(using delimiter: String) -> Output {
        defer { buffer = "" }
        guard !isExcluded, !ambiguousKeywords.contains(buffer), let snippet = snippets[buffer] else { return .ignored }
        return .expanded(Expansion(keyword: buffer, renderedContent: render(snippet), delimiter: delimiter, deleteCount: buffer.count))
    }

    private var isExcluded: Bool {
        guard let currentBundleIdentifier else { return false }
        return excludedBundleIdentifiers.contains(currentBundleIdentifier)
    }

    private static func normalized(_ snippets: [StoredSnippet]) -> [String: StoredSnippet] {
        // Pinned, then newest, then id makes duplicate precedence deterministic.
        let ordered = snippets.sorted {
            if $0.isPinned != $1.isPinned { return $0.isPinned }
            if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
            return $0.id < $1.id
        }
        var result: [String: StoredSnippet] = [:]
        for snippet in ordered where snippet.keyword.isEmpty == false {
            result[snippet.keyword] = result[snippet.keyword] ?? snippet
        }
        return result
    }
}
