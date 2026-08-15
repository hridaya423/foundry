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
    init(payload: ClipboardPayload, createdAt: Date = Date(), sourceBundleIdentifier: String? = nil, isPinned: Bool = false) {
        id = UUID().uuidString; self.createdAt = createdAt; self.payload = payload; signature = payload.signature; self.sourceBundleIdentifier = sourceBundleIdentifier; self.isPinned = isPinned
    }
    var memoryCost: Int { payload.byteCount }
    var title: String { switch payload { case .text(let v): return v.components(separatedBy: .newlines).first?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? (v.components(separatedBy: .newlines).first ?? v) : "Text"; case .files(let v): return v.count == 1 ? v[0].lastPathComponent : "\(v.count) files"; case .image: return "Image" } }
    var subtitle: String { switch payload { case .text(let v): return "\(v.count) chars"; case .files(let v): return v.first?.deletingLastPathComponent().path ?? "Files"; case .image(let v): return ByteCountFormatter.string(fromByteCount: Int64(v.count), countStyle: .file) } }
    var kindLabel: String { switch payload { case .text: "Text"; case .files: "Files"; case .image: "Image" } }
    var systemImage: String { switch payload { case .text: "doc.text"; case .files: "doc.on.doc"; case .image: "photo" } }
    var timeLabel: String { "now" }
}

struct ClipboardHistoryPolicy: Equatable {
    var maxItems: Int = 40
    var maxBytes: Int = 16 * 1024 * 1024
    var maxTextBytes: Int = 2 * 1024 * 1024
    var maxImageBytes: Int = 4 * 1024 * 1024
    func bounded(_ input: [ClipboardHistoryItem]) -> [ClipboardHistoryItem] {
        var result: [ClipboardHistoryItem] = []
        for item in input where result.contains(where: { $0.signature == item.signature }) == false { result.append(item) }
        result = Array(result.prefix(maxItems))
        while result.reduce(0, { $0 + $1.memoryCost }) > maxBytes, !result.isEmpty {
            if let index = result.lastIndex(where: { !$0.isPinned }) { result.remove(at: index) } else { result.removeLast() }
        }
        return result
    }
}
