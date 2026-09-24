import Foundation
import CryptoKit

enum ClipboardPayload: Codable, Hashable {
    case text(String)
    case files([URL])
    case image(Data)

    private enum CodingKeys: String, CodingKey { case kind, text, files, image }
    private enum Kind: String, Codable { case text, files, image }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(Kind.self, forKey: .kind) {
        case .text: self = .text(try c.decode(String.self, forKey: .text))
        case .files: self = .files(try c.decode([URL].self, forKey: .files))
        case .image: self = .image(try c.decode(Data.self, forKey: .image))
        }
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let value): try c.encode(Kind.text, forKey: .kind); try c.encode(value, forKey: .text)
        case .files(let value): try c.encode(Kind.files, forKey: .kind); try c.encode(value, forKey: .files)
        case .image(let value): try c.encode(Kind.image, forKey: .kind); try c.encode(value, forKey: .image)
        }
    }
    var byteCount: Int { switch self { case .text(let v): v.utf8.count; case .files(let v): v.reduce(0) { $0 + $1.path.utf8.count }; case .image(let v): v.count } }
    var signature: String {
        let bytes: Data
        switch self { case .text(let v): bytes = Data(v.utf8); case .files(let v): bytes = Data(v.map(\.path).joined(separator: "\0").utf8); case .image(let v): bytes = v }
        return SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }
}

struct ClipboardHistoryItem: Identifiable, Codable, Hashable {
    let id: String
    let createdAt: Date
    let payload: ClipboardPayload
    let signature: String
    var isPinned: Bool
    let sourceBundleIdentifier: String?
    init(id: String = UUID().uuidString, payload: ClipboardPayload, createdAt: Date = Date(), sourceBundleIdentifier: String? = nil, isPinned: Bool = false) {
        self.id = id; self.createdAt = createdAt; self.payload = payload; signature = payload.signature; self.sourceBundleIdentifier = sourceBundleIdentifier; self.isPinned = isPinned
    }
    var memoryCost: Int { payload.byteCount }
    static func isLink(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.contains(where: \.isWhitespace) == false, let url = URL(string: trimmed), let scheme = url.scheme?.lowercased() else { return false }
        return (scheme == "http" || scheme == "https") && url.host != nil
    }
    var title: String { switch payload { case .text(let v): return v.components(separatedBy: .newlines).first?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? (v.components(separatedBy: .newlines).first ?? v) : "Text"; case .files(let v): return v.count == 1 ? v[0].lastPathComponent : "\(v.count) files"; case .image: return "Image" } }
    var subtitle: String { switch payload { case .text(let v): return "\(v.count) chars"; case .files(let v): return v.first?.deletingLastPathComponent().path ?? "Files"; case .image(let v): return ByteCountFormatter.string(fromByteCount: Int64(v.count), countStyle: .file) } }
    var kindLabel: String { switch payload { case .text: "Text"; case .files: "Files"; case .image: "Image" } }
    var systemImage: String { switch payload { case .text(let v): Self.isLink(v) ? "link" : "doc.text"; case .files: "doc.on.doc"; case .image: "photo" } }
    var timeLabel: String { timeLabel(relativeTo: Date()) }
    func timeLabel(relativeTo now: Date) -> String {
        let seconds = max(Int(now.timeIntervalSince(createdAt)), 0)
        if seconds < 60 { return "now" }
        if seconds < 3_600 { return "\(seconds / 60)m" }
        if seconds < 86_400 { return "\(seconds / 3_600)h" }
        return "\(seconds / 86_400)d"
    }
}

struct ClipboardHistoryPolicy: Equatable {
    var maxItems: Int = 1_000
    var maxBytes: Int = 1_024 * 1_024 * 1_024
    var maxTextBytes: Int = 2 * 1024 * 1024
    var maxImageBytes: Int = 4 * 1024 * 1024
    var maxAge: TimeInterval = 90 * 86_400
    func bounded(_ input: [ClipboardHistoryItem], relativeTo now: Date = Date()) -> [ClipboardHistoryItem] {
        var result: [ClipboardHistoryItem] = []
        for item in input where result.contains(where: { $0.signature == item.signature }) == false { result.append(item) }
        let cutoff = now.addingTimeInterval(-maxAge)
        result = result.filter { $0.isPinned || $0.createdAt >= cutoff }
        var unpinnedBudget = max(maxItems - result.filter(\.isPinned).count, 0)
        result = result.filter { item in
            if item.isPinned { return true }
            guard unpinnedBudget > 0 else { return false }
            unpinnedBudget -= 1
            return true
        }
        while result.reduce(0, { $0 + $1.memoryCost }) > maxBytes, !result.isEmpty {
            if let index = result.lastIndex(where: { !$0.isPinned }) { result.remove(at: index) } else { result.removeLast() }
        }
        return result
    }
}
