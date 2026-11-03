import Foundation

enum FallbackKind: String, CaseIterable, Codable, Identifiable, Sendable {
    case suggestions, askAI, searchWeb, searchFiles, define

    var id: String { rawValue }

    var title: String {
        switch self {
        case .suggestions: String(localized: "Browser history and other matches")
        case .askAI: String(localized: "Ask AI")
        case .searchWeb: String(localized: "Search the web")
        case .searchFiles: String(localized: "Search Files")
        case .define: String(localized: "Define in Dictionary")
        }
    }
}

struct FallbackConfig: Codable, Equatable, Sendable {
    private(set) var order: [FallbackKind]
    var disabled: Set<FallbackKind>

    static let `default` = FallbackConfig(order: FallbackKind.allCases, disabled: [.define])

    init(order: [FallbackKind], disabled: Set<FallbackKind>) {
        var seen = Set<FallbackKind>()
        self.order = (order + FallbackKind.allCases).filter { seen.insert($0).inserted }
        self.disabled = disabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let order = try container.decodeIfPresent([String].self, forKey: .order) ?? []
        let disabled = try container.decodeIfPresent([String].self, forKey: .disabled)
        self.init(order: order.compactMap(FallbackKind.init(rawValue:)),
            disabled: disabled.map { Set($0.compactMap(FallbackKind.init(rawValue:))) } ?? Self.default.disabled)
    }

    var enabledInOrder: [FallbackKind] { order.filter { disabled.contains($0) == false } }

    mutating func move(_ kind: FallbackKind, by offset: Int) {
        guard let index = order.firstIndex(of: kind) else { return }
        order.remove(at: index)
        order.insert(kind, at: min(max(index + offset, 0), order.count))
    }
}
