import Foundation

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
        let sanitized = value.replacingOccurrences(of: " ", with: "")
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
            if let decoded = base64Decode(input), let decodedData = decoded.data(using: .utf8), let nested = try? JSONSerialization.jsonObject(with: decodedData) {
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

        if let numeric = Double(trimmed.replacingOccurrences(of: ",", with: "")) {
            let date = trimmed.count >= 13 ? Date(timeIntervalSince1970: numeric / 1000) : Date(timeIntervalSince1970: numeric)
            return conversions(for: date)
        }

        for formatter in dateFormatters() {
            if let date = formatter.date(from: trimmed) {
                return [
                    TimestampConversion(label: "Unix seconds", value: String(Int(date.timeIntervalSince1970.rounded()))),
                    TimestampConversion(label: "Unix milliseconds", value: String(Int((date.timeIntervalSince1970 * 1000).rounded()))),
                    TimestampConversion(label: "ISO 8601", value: isoFormatter().string(from: date))
                ]
            }
        }
        return []
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
            let width = Int(parts.dropFirst().first ?? 64)
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
            RadixConversion(label: "Binary", value: String(number, radix: 2)),
            RadixConversion(label: "Octal", value: String(number, radix: 8)),
            RadixConversion(label: "Decimal", value: String(number, radix: 10)),
            RadixConversion(label: "Hex", value: String(number, radix: 16).uppercased())
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
        if normalized.isEmpty || normalized == "email" { return [RandomItem(label: "Random Email", value: randomEmail())] + (normalized.isEmpty ? [RandomItem(label: "Random Hex Color", value: randomHexColor()), RandomItem(label: "Random Integer", value: randomInteger()), RandomItem(label: "Random Slug", value: randomSlug())] : []) }
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
        return text.contains("&") || text.contains("|") || text.contains("^") || text.contains("<<") || text.contains(">>") || text.contains(" and ") || text.contains(" or ") || text.contains(" xor ") || text.hasPrefix("and ") || text.hasPrefix("or ") || text.hasPrefix("xor ") || text.hasPrefix("not ") || text.contains("shift left") || text.contains("shift right")
    }

    static func looksLikeRadixValue(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if trimmed.hasPrefix("0x") || trimmed.hasPrefix("0b") || trimmed.hasPrefix("0o") { return true }
        let parts = trimmed.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        if parts.count == 2, let radix = Int(parts[0]), (2...36).contains(radix) { return true }
        return false
    }

    private static func conversions(for date: Date) -> [TimestampConversion] {
        [
            TimestampConversion(label: "ISO 8601", value: isoFormatter().string(from: date)),
            TimestampConversion(label: "Unix seconds", value: String(Int(date.timeIntervalSince1970.rounded()))),
            TimestampConversion(label: "Unix milliseconds", value: String(Int((date.timeIntervalSince1970 * 1000).rounded()))),
            TimestampConversion(label: "Local", value: localFormatter().string(from: date))
        ]
    }

    private static func splitWords(in value: String) -> [String] {
        value
            .replacingOccurrences(of: "([a-z0-9])([A-Z])", with: "$1 $2", options: .regularExpression)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.isEmpty == false }
    }

    private static func numbers(in value: String) -> [UInt64] {
        value
            .split { !$0.isNumber }
            .compactMap { UInt64($0) }
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

    private static func isoFormatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }

    private static func localFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter
    }

    private static func dateFormatters() -> [DateFormatter] {
        let patterns = [
            "yyyy-MM-dd HH:mm:ss",
            "yyyy-MM-dd HH:mm",
            "yyyy-MM-dd",
            "yyyy/MM/dd HH:mm:ss",
            "yyyy/MM/dd HH:mm",
            "yyyy/MM/dd"
        ]
        return patterns.map { pattern in
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = pattern
            return formatter
        }
    }
}
