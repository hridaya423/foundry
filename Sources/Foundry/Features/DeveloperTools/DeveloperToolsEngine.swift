import CryptoKit
import Foundation
import FoundryServices
import os

enum DeveloperToolsEngine {
    enum BitwiseOperation {
        case and(UInt64, UInt64)
        case or(UInt64, UInt64)
        case xor(UInt64, UInt64)
        case not(UInt64, Int)
        case shiftLeft(UInt64, UInt64)
        case shiftRight(UInt64, UInt64)
    }

    struct CaseVariant {
        let style: String
        let value: String
    }

    struct TimestampConversion {
        let label: String
        let value: String
    }

    struct WordCount {
        let words: Int
        let characters: Int
        let lines: Int
        let paragraphs: Int
    }

    struct RandomItem {
        let label: String
        let value: String
    }

    struct RadixConversion {
        let label: String
        let value: String
    }

    static func base64Encode(_ value: String) -> String? {
        value.data(using: .utf8)?.base64EncodedString()
    }

    static func base64Decode(_ value: String) -> String? {
        var sanitized = value
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = sanitized.count % 4
        if remainder > 0 { sanitized += String(repeating: "=", count: 4 - remainder) }
        guard let data = Data(base64Encoded: sanitized) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func formatJSON(_ value: String) -> String? {
        let input = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = input.data(using: .utf8) else { return nil }
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data)
        } catch {
            if let decoded = base64Decode(input), let decodedData = decoded.data(using: .utf8),
                let nested = try? JSONSerialization.jsonObject(with: decodedData) {
                object = nested
            } else {
                return nil
            }
        }
        guard let pretty = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]) else { return nil }
        return String(data: pretty, encoding: .utf8)
    }

    static func caseVariants(for value: String) -> [CaseVariant] {
        let words = splitWords(in: value)
        guard words.isEmpty == false else { return [] }

        let lower = words.map { $0.lowercased() }
        let capitalized = lower.map(capitalize)
        return [
            CaseVariant(style: "camelCase", value: lower.prefix(1).joined() + capitalized.dropFirst().joined()),
            CaseVariant(style: "PascalCase", value: capitalized.joined()),
            CaseVariant(style: "snake_case", value: lower.joined(separator: "_")),
            CaseVariant(style: "kebab-case", value: lower.joined(separator: "-")),
            CaseVariant(style: "CONSTANT_CASE", value: lower.joined(separator: "_").uppercased()),
            CaseVariant(style: "Title Case", value: capitalized.joined(separator: " ")),
            CaseVariant(style: "dot.case", value: lower.joined(separator: ".")),
            CaseVariant(style: "path/case", value: lower.joined(separator: "/"))
        ]
    }

    static func timestampConversions(for value: String) -> [TimestampConversion] {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased() == "now" {
            return conversions(for: Date())
        }

        if let numeric = Double(trimmed.replacingOccurrences(of: ",", with: "")), numeric.isFinite {
            let date = abs(numeric) >= 1e12 ? Date(timeIntervalSince1970: numeric / 1000) : Date(timeIntervalSince1970: numeric)
            return conversions(for: date)
        }

        if let date = iso8601Parsers.withLockUnchecked({ parsers in parsers.lazy.compactMap { $0.date(from: trimmed) }.first }) {
            return inputConversions(for: date)
        }
        for formatter in timestampInputFormatters {
            if let date = formatter.date(from: trimmed) { return inputConversions(for: date) }
        }
        return []
    }

    private static func inputConversions(for date: Date) -> [TimestampConversion] {
        [
            TimestampConversion(label: "Unix seconds", value: integerText(date.timeIntervalSince1970)),
            TimestampConversion(label: "Unix milliseconds", value: integerText(date.timeIntervalSince1970 * 1000)),
            TimestampConversion(label: "ISO 8601", value: iso8601Formatter.withLockUnchecked { $0.string(from: date) })
        ]
    }

    static func wordCount(_ value: String) -> WordCount {
        let text = value.trimmingCharacters(in: .newlines)
        let words = text.split { $0.isWhitespace || $0.isNewline }.count
        let lines = max(text.isEmpty ? 0 : text.components(separatedBy: .newlines).count, 1)
        let paragraphs = text
            .components(separatedBy: CharacterSet.newlines)
            .split { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .count
        return WordCount(words: words, characters: value.count, lines: lines, paragraphs: paragraphs)
    }

    static func bitwiseOperation(from value: String) -> BitwiseOperation? {
        let text = value.lowercased().replacingOccurrences(of: ",", with: " ")
        if text.contains(" not ") || text.hasPrefix("not ") {
            let parts = numbers(in: text)
            guard let first = parts.first else { return nil }
            let width = Int(min(max(parts.dropFirst().first ?? 64, 1), 64))
            return .not(first, width)
        }
        if text.contains("<<") || text.contains("shift left") {
            let parts = numbers(in: text)
            guard parts.count >= 2 else { return nil }
            return .shiftLeft(parts[0], parts[1])
        }
        if text.contains(">>") || text.contains("shift right") {
            let parts = numbers(in: text)
            guard parts.count >= 2 else { return nil }
            return .shiftRight(parts[0], parts[1])
        }
        let parts = numbers(in: text)
        guard parts.count >= 2 else { return nil }
        if text.contains(" xor ") || text.hasPrefix("xor ") { return .xor(parts[0], parts[1]) }
        if text.contains(" or ") || text.hasPrefix("or ") || text.contains("|") { return .or(parts[0], parts[1]) }
        if text.contains(" and ") || text.hasPrefix("and ") || text.contains("&") { return .and(parts[0], parts[1]) }
        return nil
    }

    static func baseConversion(from value: String) -> [RadixConversion]? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true).map(String.init)
        guard parts.isEmpty == false else { return nil }

        var radix = 10
        var numberText = trimmed
        if parts.count >= 2, let parsed = Int(parts[0]), (2...36).contains(parsed) {
            radix = parsed
            numberText = parts[1]
        } else if trimmed.hasPrefix("0x") {
            radix = 16
            numberText = String(trimmed.dropFirst(2))
        } else if trimmed.hasPrefix("0b") {
            radix = 2
            numberText = String(trimmed.dropFirst(2))
        } else if trimmed.hasPrefix("0o") {
            radix = 8
            numberText = String(trimmed.dropFirst(2))
        }

        let cleaned = numberText.replacingOccurrences(of: "_", with: "")
        guard let number = UInt64(cleaned, radix: radix) else { return nil }
        return radixConversions(for: number)
    }

    static func parseUnsignedInteger(_ value: String) -> UInt64? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().replacingOccurrences(of: "_", with: "")
        guard trimmed.isEmpty == false else { return nil }
        if trimmed.hasPrefix("0x") { return UInt64(trimmed.dropFirst(2), radix: 16) }
        if trimmed.hasPrefix("0b") { return UInt64(trimmed.dropFirst(2), radix: 2) }
        if trimmed.hasPrefix("0o") { return UInt64(trimmed.dropFirst(2), radix: 8) }
        return UInt64(trimmed, radix: 10)
    }

    static func radixConversions(for number: UInt64) -> [RadixConversion] {
        [
            RadixConversion(label: "Decimal", value: String(number, radix: 10)),
            RadixConversion(label: "Hex", value: String(number, radix: 16).uppercased()),
            RadixConversion(label: "Binary", value: String(number, radix: 2)),
            RadixConversion(label: "Octal", value: String(number, radix: 8))
        ]
    }

    static func lorem(words: Int) -> String {
        let count = max(words, 1)
        let sequence = (0..<count).map { loremWords[$0 % loremWords.count] }
        var output = sequence.joined(separator: " ")
        output.replaceSubrange(output.startIndex...output.startIndex, with: String(output.prefix(1)).capitalized)
        return output + "."
    }

    static func randomItems(matching kind: String) -> [RandomItem] {
        let normalized = kind.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.isEmpty || normalized == "email" {
            let extras: [RandomItem] = normalized.isEmpty ? [
                RandomItem(label: "Random Hex Color", value: randomHexColor()),
                RandomItem(label: "Random Integer", value: randomInteger()),
                RandomItem(label: "Random Slug", value: randomSlug()),
            ] : []
            return [RandomItem(label: "Random Email", value: randomEmail())] + extras
        }
        if normalized.contains("hex") || normalized.contains("color") { return [RandomItem(label: "Random Hex Color", value: randomHexColor())] }
        if normalized.contains("int") || normalized.contains("number") { return [RandomItem(label: "Random Integer", value: randomInteger())] }
        if normalized.contains("slug") { return [RandomItem(label: "Random Slug", value: randomSlug())] }
        if normalized.contains("name") { return [RandomItem(label: "Random Name", value: randomName())] }
        return [
            RandomItem(label: "Random Email", value: randomEmail()),
            RandomItem(label: "Random Hex Color", value: randomHexColor()),
            RandomItem(label: "Random Integer", value: randomInteger()),
            RandomItem(label: "Random Slug", value: randomSlug())
        ]
    }

    static func randomEmail() -> String {
        "\(randomSlug()).\(Int.random(in: 100...999))@example.dev"
    }

    static func randomHexColor() -> String {
        String(format: "#%06X", Int.random(in: 0...0xFFFFFF))
    }

    static func randomInteger() -> String {
        String(Int.random(in: 1000...999999))
    }

    static func randomSlug() -> String {
        let left = ["silent", "rapid", "granite", "lucky", "neon", "delta", "vector", "ember"].randomElement() ?? "silent"
        let right = ["otter", "falcon", "river", "forest", "signal", "pixel", "anchor", "rocket"].randomElement() ?? "otter"
        return "\(left)-\(right)"
    }

    static func randomName() -> String {
        let first = ["Avery", "Jordan", "Mina", "Theo", "Iris", "Noah", "Sage", "Leo"].randomElement() ?? "Avery"
        let last = ["Stone", "Reed", "Patel", "Nguyen", "Diaz", "Kim", "Shaw", "Brooks"].randomElement() ?? "Stone"
        return "\(first) \(last)"
    }

    static func compactPreview(_ value: String, limit: Int = 96) -> String {
        String(value.replacingOccurrences(of: "\n", with: " ").prefix(limit)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func looksLikeBitwiseExpression(_ value: String) -> Bool {
        let text = value.lowercased()
        return text.contains("&") || text.contains("|") || text.contains("^")
            || text.contains("<<") || text.contains(">>")
            || text.contains(" and ") || text.contains(" or ") || text.contains(" xor ")
            || text.hasPrefix("and ") || text.hasPrefix("or ") || text.hasPrefix("xor ")
            || text.hasPrefix("not ") || text.contains("shift left") || text.contains("shift right")
    }

    static func looksLikeRadixValue(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if trimmed.hasPrefix("0x") || trimmed.hasPrefix("0b") || trimmed.hasPrefix("0o") { return true }
        return false
    }

    private static let namedBases = ["hex": "Hex", "hexadecimal": "Hex", "binary": "Binary", "bin": "Binary", "octal": "Octal", "oct": "Octal",
        "decimal": "Decimal", "dec": "Decimal"]

    static func namedBaseConversion(from value: String) -> [RadixConversion]? {
        let parts = value.lowercased().split(separator: " ")
        guard parts.count == 3, ["to", "in", "as"].contains(parts[1]), let label = namedBases[String(parts[2])],
              let number = parseUnsignedInteger(String(parts[0])) else { return nil }
        return radixConversions(for: number).filter { $0.label == label }
    }

    struct HashAlgorithm: Sendable {
        let prefix: String
        let label: String
        let digest: @Sendable (Data) -> String
    }

    private static func hex<D: Sequence>(_ digest: D) -> String where D.Element == UInt8 {
        digest.map { String(format: "%02x", $0) }.joined()
    }

    static let hashAlgorithms = [
        HashAlgorithm(prefix: "md5", label: "MD5") { hex(Insecure.MD5.hash(data: $0)) },
        HashAlgorithm(prefix: "sha1", label: "SHA-1") { hex(Insecure.SHA1.hash(data: $0)) },
        HashAlgorithm(prefix: "sha256", label: "SHA-256") { hex(SHA256.hash(data: $0)) },
        HashAlgorithm(prefix: "sha384", label: "SHA-384") { hex(SHA384.hash(data: $0)) },
        HashAlgorithm(prefix: "sha512", label: "SHA-512") { hex(SHA512.hash(data: $0)) }
    ]

    static func urlEncode(_ value: String) -> String? {
        value.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: "-._~")))
    }

    private static let hexColor = try! NSRegularExpression(pattern: "^#([0-9a-f]{3}|[0-9a-f]{6})$", options: .caseInsensitive)
    private static let rgbColor = try! NSRegularExpression(pattern: #"^rgb\(\s*(\d{1,3})\s*,\s*(\d{1,3})\s*,\s*(\d{1,3})\s*\)$"#,
        options: .caseInsensitive)

    static func colorConversions(for value: String) -> [RadixConversion] {
        let text = value.trimmingCharacters(in: .whitespaces)
        let whole = NSRange(text.startIndex..<text.endIndex, in: text)
        let channels: [Int]
        let isHex: Bool
        if hexColor.firstMatch(in: text, range: whole) != nil {
            let digits = Array(text.dropFirst())
            let pairs = digits.count == 3 ? digits.map { "\($0)\($0)" } : stride(from: 0, to: 6, by: 2).map { String(digits[$0...$0 + 1]) }
            channels = pairs.compactMap { Int($0, radix: 16) }
            isHex = true
        } else if let match = rgbColor.firstMatch(in: text, range: whole) {
            channels = (1...3).compactMap { Range(match.range(at: $0), in: text).flatMap { Int(text[$0]) } }
            guard channels.allSatisfy({ $0 <= 255 }) else { return [] }
            isHex = false
        } else {
            return []
        }

        let (red, green, blue) = (Double(channels[0]) / 255, Double(channels[1]) / 255, Double(channels[2]) / 255)
        let (high, low) = (max(red, green, blue), min(red, green, blue))
        let lightness = (high + low) / 2
        let chroma = high - low
        let saturation = chroma == 0 ? 0 : chroma / (1 - abs(2 * lightness - 1))
        var hue = 0.0
        if chroma > 0 {
            switch high {
            case red: hue = ((green - blue) / chroma).truncatingRemainder(dividingBy: 6)
            case green: hue = (blue - red) / chroma + 2
            default: hue = (red - green) / chroma + 4
            }
            hue = (hue * 60 + 360).truncatingRemainder(dividingBy: 360)
        }
        let hsl = "hsl(\(Int(hue.rounded())), \(Int((saturation * 100).rounded()))%, \(Int((lightness * 100).rounded()))%)"
        let first = isHex
            ? RadixConversion(label: "RGB", value: "rgb(\(channels[0]), \(channels[1]), \(channels[2]))")
            : RadixConversion(label: "Hex", value: "#" + channels.map { String(format: "%02X", $0) }.joined())
        return [first, RadixConversion(label: "HSL", value: hsl)]
    }

    private static func integerText(_ value: Double) -> String {
        if let integer = Int64(exactly: value.rounded()) { return String(integer) }
        return String(format: "%.0f", value)
    }

    private static func conversions(for date: Date) -> [TimestampConversion] {
        [
            TimestampConversion(label: "Local", value: localDateFormatter.string(from: date)),
            TimestampConversion(label: "ISO 8601", value: iso8601Formatter.withLockUnchecked { $0.string(from: date) }),
            TimestampConversion(label: "Unix seconds", value: integerText(date.timeIntervalSince1970)),
            TimestampConversion(label: "Unix milliseconds", value: integerText(date.timeIntervalSince1970 * 1000))
        ]
    }

    private static let camelBoundaryRegex = try! NSRegularExpression(pattern: "([a-z0-9])([A-Z])")

    private static func splitWords(in value: String) -> [String] {
        camelBoundaryRegex
            .stringByReplacingMatches(in: value, range: NSRange(value.startIndex..<value.endIndex, in: value), withTemplate: "$1 $2")
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.isEmpty == false }
    }

    private static let operandRegex = try! NSRegularExpression(pattern: "0x[0-9a-f_]+|0b[01_]+|0o[0-7_]+|[0-9]+")

    private static func numbers(in value: String) -> [UInt64] {
        operandRegex.matches(in: value, range: NSRange(value.startIndex..<value.endIndex, in: value))
            .compactMap { Range($0.range, in: value) }
            .compactMap { parseUnsignedInteger(String(value[$0])) }
    }

    private static func capitalize(_ value: String) -> String {
        guard let first = value.first else { return value }
        return String(first).uppercased() + value.dropFirst()
    }

    private static let loremWords = [
        "lorem", "ipsum", "dolor", "sit", "amet", "consectetur", "adipiscing", "elit",
        "sed", "do", "eiusmod", "tempor", "incididunt", "ut", "labore", "et", "dolore",
        "magna", "aliqua", "ut", "enim", "ad", "minim", "veniam", "quis", "nostrud",
        "exercitation", "ullamco", "laboris", "nisi", "ut", "aliquip", "ex", "ea", "commodo", "consequat"
    ]

    private static let iso8601Formatter = OSAllocatedUnfairLock<ISO8601DateFormatter>(uncheckedState: {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }())

    private static let iso8601Parsers = OSAllocatedUnfairLock<[ISO8601DateFormatter]>(uncheckedState: [
        ISO8601DateFormatter.Options([.withInternetDateTime]),
        ISO8601DateFormatter.Options([.withInternetDateTime, .withFractionalSeconds])
    ].map { options in
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = options
        return formatter
    })

    private static let localDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter
    }()

    private static let timestampInputFormatters: [DateFormatter] = [
        "yyyy-MM-dd HH:mm:ss",
        "yyyy-MM-dd HH:mm",
        "yyyy-MM-dd'T'HH:mm:ss",
        "yyyy-MM-dd'T'HH:mm",
        "yyyy-MM-dd",
        "yyyy/MM/dd HH:mm:ss",
        "yyyy/MM/dd HH:mm",
        "yyyy/MM/dd"
    ].map { pattern in
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = pattern
        return formatter
    }
}
