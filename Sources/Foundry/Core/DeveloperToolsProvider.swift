import Foundation

final class DeveloperToolsProvider: CommandProvider {
    let id = "foundry.developer-tools"

    func results(matching query: String) async -> [CommandResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return [] }

        var results = staticCommandResults(query: trimmed)
        results.append(contentsOf: uuidResults(query: trimmed))
        results.append(contentsOf: base64Results(query: trimmed))
        results.append(contentsOf: jsonResults(query: trimmed))
        results.append(contentsOf: caseResults(query: trimmed))
        results.append(contentsOf: unixTimestampResults(query: trimmed))
        results.append(contentsOf: bitwiseResults(query: trimmed))
        results.append(contentsOf: baseConversionResults(query: trimmed))
        results.append(contentsOf: wordCountResults(query: trimmed))
        results.append(contentsOf: loremResults(query: trimmed))
        results.append(contentsOf: randomDataResults(query: trimmed))

        return results
            .sorted { lhs, rhs in
                if lhs.score == rhs.score { return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending }
                return lhs.score > rhs.score
            }
    }

    func defaultResults() async -> [CommandResult] {
        [
            makeResult(
                id: "dev.uuid.default",
                title: "Generate UUID",
                subtitle: "Copy a new UUID",
                icon: "number",
                fallback: "ID",
                score: 2,
                primary: .copyToClipboard(UUID().uuidString)
            ),
            makeResult(
                id: "dev.lorem.default",
                title: "Generate Lorem Ipsum",
                subtitle: "Copy 24 placeholder words",
                icon: "text.alignleft",
                fallback: "LO",
                score: 2,
                primary: .copyToClipboard(DeveloperToolsEngine.lorem(words: 24))
            ),
            makeResult(
                id: "dev.random-email.default",
                title: "Generate Random Email",
                subtitle: "Copy a disposable-looking email address",
                icon: "at",
                fallback: "RD",
                score: 1,
                primary: .copyToClipboard(DeveloperToolsEngine.randomEmail())
            )
        ]
    }

    private func staticCommandResults(query: String) -> [CommandResult] {
        staticCommands.compactMap { command in
            guard let score = SearchScoring.score(query: query, title: command.title, aliases: command.aliases) else { return nil }
            return makeResult(
                id: command.id,
                title: command.title,
                subtitle: command.subtitle,
                icon: command.icon,
                fallback: command.fallback,
                score: score + command.scoreBoost,
                primary: command.action
            )
        }
    }

    private func uuidResults(query: String) -> [CommandResult] {
        guard let payload = payload(in: query, prefixes: ["uuid", "guid"]) else { return [] }
        let count = min(max(Int(payload.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 1, 1), 20)
        let values = (0..<count).map { _ in UUID().uuidString }
        return values.enumerated().map { index, value in
            makeResult(
                id: "dev.uuid.\(index).\(value)",
                title: value,
                subtitle: count == 1 ? "UUID" : "UUID \(index + 1) of \(count)",
                icon: "number",
                fallback: "ID",
                score: 110 - Double(index),
                primary: .copyToClipboard(value)
            )
        }
    }

    private func base64Results(query: String) -> [CommandResult] {
        let encodePrefixes = ["base64 encode", "b64 encode", "encode base64"]
        let decodePrefixes = ["base64 decode", "b64 decode", "decode base64"]

        if let payload = payload(in: query, prefixes: encodePrefixes), payload.isEmpty == false,
           let encoded = DeveloperToolsEngine.base64Encode(payload) {
            return [
                makeResult(
                    id: "dev.base64.encode.\(encoded.hashValue)",
                    title: encoded,
                    subtitle: "Base64 encoded",
                    icon: "lock.doc",
                    fallback: "64",
                    score: 110,
                    primary: .copyToClipboard(encoded),
                    secondary: [CommandAction(id: "dev.base64.encode.paste", title: "Paste", kind: .pasteText(encoded))]
                )
            ]
        }

        if let payload = payload(in: query, prefixes: decodePrefixes), payload.isEmpty == false,
           let decoded = DeveloperToolsEngine.base64Decode(payload) {
            return [
                makeResult(
                    id: "dev.base64.decode.\(decoded.hashValue)",
                    title: decoded,
                    subtitle: "Base64 decoded",
                    icon: "lock.open",
                    fallback: "64",
                    score: 110,
                    primary: .copyToClipboard(decoded),
                    secondary: [CommandAction(id: "dev.base64.decode.paste", title: "Paste", kind: .pasteText(decoded))]
                )
            ]
        }

        guard let payload = payload(in: query, prefixes: ["base64", "b64"]), payload.isEmpty == false else { return [] }
        var results: [CommandResult] = []
        if let encoded = DeveloperToolsEngine.base64Encode(payload) {
            results.append(makeResult(id: "dev.base64.any.encode.\(encoded.hashValue)", title: encoded, subtitle: "Encoded", icon: "lock.doc", fallback: "64", score: 109, primary: .copyToClipboard(encoded)))
        }
        if let decoded = DeveloperToolsEngine.base64Decode(payload) {
            results.append(makeResult(id: "dev.base64.any.decode.\(decoded.hashValue)", title: decoded, subtitle: "Decoded", icon: "lock.open", fallback: "64", score: 108, primary: .copyToClipboard(decoded)))
        }
        return results
    }

    private func jsonResults(query: String) -> [CommandResult] {
        guard let payload = payload(in: query, prefixes: ["json", "format json", "pretty json"]), payload.isEmpty == false,
              let formatted = DeveloperToolsEngine.formatJSON(payload) else { return [] }
        return [
            makeResult(
                id: "dev.json.\(formatted.hashValue)",
                title: "Formatted JSON",
                subtitle: DeveloperToolsEngine.compactPreview(formatted),
                icon: "curlybraces.square",
                fallback: "JS",
                score: 110,
                primary: .copyToClipboard(formatted),
                secondary: [CommandAction(id: "dev.json.paste", title: "Paste", kind: .pasteText(formatted))]
            )
        ]
    }

    private func caseResults(query: String) -> [CommandResult] {
        guard let payload = payload(in: query, prefixes: ["case", "change case", "convert case"]), payload.isEmpty == false else { return [] }
        return DeveloperToolsEngine.caseVariants(for: payload).enumerated().map { index, variant in
            makeResult(
                id: "dev.case.\(variant.style).\(variant.value.hashValue)",
                title: variant.value,
                subtitle: variant.style,
                icon: "character.cursor.ibeam",
                fallback: "Aa",
                score: 109 - Double(index),
                primary: .copyToClipboard(variant.value),
                secondary: [CommandAction(id: "dev.case.\(variant.style).paste", title: "Paste", kind: .pasteText(variant.value))]
            )
        }
    }

    private func unixTimestampResults(query: String) -> [CommandResult] {
        guard let payload = payload(in: query, prefixes: ["unix", "timestamp"]), payload.isEmpty == false else { return [] }
        return DeveloperToolsEngine.timestampConversions(for: payload).enumerated().map { index, conversion in
            makeResult(
                id: "dev.timestamp.\(index).\(conversion.value.hashValue)",
                title: conversion.value,
                subtitle: conversion.label,
                icon: "clock",
                fallback: "TS",
                score: 109 - Double(index),
                primary: .copyToClipboard(conversion.value)
            )
        }
    }

    private func bitwiseResults(query: String) -> [CommandResult] {
        let candidate: String?
        if let payload = payload(in: query, prefixes: ["bit", "bits", "bitwise"]), payload.isEmpty == false {
            candidate = payload
        } else if DeveloperToolsEngine.looksLikeBitwiseExpression(query) {
            candidate = query
        } else {
            candidate = nil
        }
        guard let candidate, let operation = DeveloperToolsEngine.bitwiseOperation(from: candidate) else { return [] }
        switch operation {
        case let .and(lhs, rhs):
            return bitwiseOutputs(lhs: lhs, rhs: rhs, label: "AND", value: lhs & rhs)
        case let .or(lhs, rhs):
            return bitwiseOutputs(lhs: lhs, rhs: rhs, label: "OR", value: lhs | rhs)
        case let .xor(lhs, rhs):
            return bitwiseOutputs(lhs: lhs, rhs: rhs, label: "XOR", value: lhs ^ rhs)
        case let .not(value, width):
            let mask = width >= 64 ? UInt64.max : (1 << width) - 1
            let output = (~value) & mask
            return [bitwiseResult(title: "~\(value)", subtitle: "NOT over \(width)-bit mask", value: output, expression: "~\(value)")]
        case let .shiftLeft(value, amount):
            return [bitwiseResult(title: "\(value) << \(amount)", subtitle: "Shift left", value: value << amount, expression: "\(value) << \(amount)")]
        case let .shiftRight(value, amount):
            return [bitwiseResult(title: "\(value) >> \(amount)", subtitle: "Shift right", value: value >> amount, expression: "\(value) >> \(amount)")]
        }
    }

    private func bitwiseOutputs(lhs: UInt64, rhs: UInt64, label: String, value: UInt64) -> [CommandResult] {
        [
            bitwiseResult(title: String(value), subtitle: "\(lhs) \(label) \(rhs)", value: value, expression: "\(lhs) \(label) \(rhs)"),
            bitwiseResult(title: String(value, radix: 2), subtitle: "Binary", value: value, expression: String(value)),
            bitwiseResult(title: String(value, radix: 16).uppercased(), subtitle: "Hex", value: value, expression: String(value))
        ]
    }

    private func bitwiseResult(title: String, subtitle: String, value: UInt64, expression: String) -> CommandResult {
        makeResult(
            id: "dev.bitwise.\(expression.hashValue).\(subtitle)",
            title: title,
            subtitle: subtitle,
            icon: "candybarphone",
            fallback: "01",
            score: 110,
            primary: .copyToClipboard(title)
        )
    }

    private func baseConversionResults(query: String) -> [CommandResult] {
        let candidate: String?
        if let payload = payload(in: query, prefixes: ["base", "radix", "convert base", "base convert"]), payload.isEmpty == false {
            candidate = payload
        } else if DeveloperToolsEngine.looksLikeRadixValue(query) {
            candidate = query
        } else {
            candidate = nil
        }
        guard let candidate, let conversion = DeveloperToolsEngine.baseConversion(from: candidate) else { return [] }
        return conversion.map { item in
            makeResult(
                id: "dev.base.\(item.label).\(item.value.hashValue)",
                title: item.value,
                subtitle: item.label == "Decimal" ? "Base conversion" : item.label,
                icon: "number",
                fallback: "10",
                score: 110,
                primary: .copyToClipboard(item.value)
            )
        }
    }

    private func wordCountResults(query: String) -> [CommandResult] {
        guard let payload = payload(in: query, prefixes: ["word count", "count words", "wc"]), payload.isEmpty == false else { return [] }
        let stats = DeveloperToolsEngine.wordCount(payload)
        let title = "\(stats.words) words"
        let subtitle = "\(stats.characters) chars · \(stats.lines) lines · \(stats.paragraphs) paragraphs"
        return [
            makeResult(
                id: "dev.wordcount.\(payload.hashValue)",
                title: title,
                subtitle: subtitle,
                icon: "textformat.abc",
                fallback: "WC",
                score: 110,
                primary: .copyToClipboard(String(stats.words)),
                secondary: [
                    CommandAction(id: "dev.wordcount.characters", title: "Copy Characters", kind: .copyToClipboard(String(stats.characters))),
                    CommandAction(id: "dev.wordcount.summary", title: "Copy Summary", kind: .copyToClipboard("\(title) · \(subtitle)"))
                ]
            )
        ]
    }

    private func loremResults(query: String) -> [CommandResult] {
        guard let payload = payload(in: query, prefixes: ["lorem", "ipsum"]), payload.isEmpty == false || SearchScoring.score(query: query, title: "Lorem Ipsum", aliases: ["lorem", "ipsum"]) != nil else { return [] }
        let count = min(max(Int(payload.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 24, 1), 200)
        let text = DeveloperToolsEngine.lorem(words: count)
        return [
            makeResult(
                id: "dev.lorem.\(count)",
                title: "Lorem Ipsum (\(count) words)",
                subtitle: DeveloperToolsEngine.compactPreview(text),
                icon: "text.alignleft",
                fallback: "LO",
                score: 109,
                primary: .copyToClipboard(text),
                secondary: [CommandAction(id: "dev.lorem.paste", title: "Paste", kind: .pasteText(text))]
            )
        ]
    }

    private func randomDataResults(query: String) -> [CommandResult] {
        guard let payload = payload(in: query, prefixes: ["random", "faker"]), payload.isEmpty == false || SearchScoring.score(query: query, title: "Random Data", aliases: ["random", "faker"]) != nil else { return [] }
        let kind = payload.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let items = DeveloperToolsEngine.randomItems(matching: kind)
        return items.enumerated().map { index, item in
            makeResult(
                id: "dev.random.\(item.label).\(item.value.hashValue)",
                title: item.value,
                subtitle: item.label,
                icon: "dice",
                fallback: "RD",
                score: 108 - Double(index),
                primary: .copyToClipboard(item.value),
                secondary: [CommandAction(id: "dev.random.\(item.label).paste", title: "Paste", kind: .pasteText(item.value))]
            )
        }
    }

    private func payload(in query: String, prefixes: [String]) -> String? {
        let normalizedQuery = SearchScoring.normalize(query)
        for prefix in prefixes.map(SearchScoring.normalize) {
            if normalizedQuery == prefix { return "" }
            if normalizedQuery.hasPrefix(prefix + " ") {
                let index = query.index(query.startIndex, offsetBy: prefix.count)
                return query[index...].trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return nil
    }

    private func makeResult(
        id: String,
        title: String,
        subtitle: String,
        icon: String,
        fallback: String,
        score: Double,
        primary: CommandActionKind,
        secondary: [CommandAction] = []
    ) -> CommandResult {
        CommandResult(
            id: id,
            title: title,
            subtitle: subtitle,
            icon: CommandIcon(fallback: fallback, systemName: icon),
            score: score,
            primaryAction: CommandAction(id: id + ".primary", title: "Copy", kind: primary),
            secondaryActions: secondary
        )
    }

    private let staticCommands: [StaticCommand] = [
        StaticCommand(id: "dev.uuid", title: "Generate UUID", subtitle: "Copy a new UUID", aliases: ["uuid", "guid", "identifier"], icon: "number", fallback: "ID", scoreBoost: 4, action: .copyToClipboard(UUID().uuidString)),
        StaticCommand(id: "dev.base64", title: "Base64 Encode or Decode", subtitle: "Transform text to or from base64", aliases: ["base64", "b64", "encode", "decode"], icon: "lock.doc", fallback: "64", scoreBoost: 4, action: .log("Add text after base64 to encode or decode it")),
        StaticCommand(id: "dev.json", title: "Format JSON", subtitle: "Pretty-print JSON into readable output", aliases: ["json", "pretty json", "format json"], icon: "curlybraces.square", fallback: "JS", scoreBoost: 4, action: .log("Add JSON after the command to format it")),
        StaticCommand(id: "dev.case", title: "Change Case", subtitle: "Convert text to camel, snake, kebab, and more", aliases: ["case", "change case", "convert case"], icon: "character.cursor.ibeam", fallback: "Aa", scoreBoost: 4, action: .log("Add text after case to convert it")),
        StaticCommand(id: "dev.timestamp", title: "Unix Timestamp", subtitle: "Convert timestamps and ISO dates", aliases: ["unix", "timestamp", "epoch"], icon: "clock", fallback: "TS", scoreBoost: 4, action: .log("Add a timestamp or date after unix to convert it")),
        StaticCommand(id: "dev.wordcount", title: "Word Count", subtitle: "Count words, characters, lines, and paragraphs", aliases: ["word count", "count words", "wc"], icon: "textformat.abc", fallback: "WC", scoreBoost: 3, action: .log("Add text after word count to inspect it")),
        StaticCommand(id: "dev.lorem", title: "Lorem Ipsum", subtitle: "Generate placeholder copy", aliases: ["lorem", "ipsum", "placeholder text"], icon: "text.alignleft", fallback: "LO", scoreBoost: 3, action: .copyToClipboard(DeveloperToolsEngine.lorem(words: 24))),
        StaticCommand(id: "dev.random", title: "Random Data", subtitle: "Generate emails, hex colors, numbers, and slugs", aliases: ["random", "faker", "fake data"], icon: "dice", fallback: "RD", scoreBoost: 3, action: .copyToClipboard(DeveloperToolsEngine.randomHexColor()))
    ]
}

private struct StaticCommand {
    let id: String
    let title: String
    let subtitle: String
    let aliases: [String]
    let icon: String
    let fallback: String
    let scoreBoost: Double
    let action: CommandActionKind
}

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
