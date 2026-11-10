import Foundation
import FoundryDomain

final class DeveloperToolsProvider: CommandProvider {
    let id = "foundry.developer-tools"

    func search(_ request: CommandSearchRequest) async -> [CommandResult] {
        let trimmed = request.query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return [] }

        var results = staticCommandResults(query: SearchScoring.PreparedQuery(query: trimmed),
            customAliases: request.customAliases, sensitivity: request.sensitivity)
        results.append(contentsOf: uuidResults(query: trimmed))
        results.append(contentsOf: base64Results(query: trimmed))
        results.append(contentsOf: jsonResults(query: trimmed))
        results.append(contentsOf: caseResults(query: trimmed))
        results.append(contentsOf: unixTimestampResults(query: trimmed))
        results.append(contentsOf: bitwiseResults(query: trimmed))
        results.append(contentsOf: baseConversionResults(query: trimmed))
        results.append(contentsOf: hashResults(query: trimmed))
        results.append(contentsOf: urlCodingResults(query: trimmed))
        results.append(contentsOf: colorResults(query: trimmed))
        results.append(contentsOf: wordCountResults(query: trimmed))
        results.append(contentsOf: loremResults(query: trimmed, sensitivity: request.sensitivity))
        results.append(contentsOf: randomDataResults(query: trimmed, sensitivity: request.sensitivity))

        return results.map { result in
            CommandResult(
                id: result.id,
                title: result.title,
                subtitle: result.subtitle,
                icon: result.icon,
                searchAliases: result.searchAliases,
                searchKeywords: result.searchKeywords,
                route: .developerTool,
                payload: result.payload,
                primaryAction: result.primaryAction,
                secondaryActions: result.secondaryActions
            )
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
                primary: CopyToClipboardAction(UUID().uuidString),
                isValue: false
            ),
            makeResult(
                id: "dev.lorem.default",
                title: "Generate Lorem Ipsum",
                subtitle: "Copy 24 placeholder words",
                icon: "text.alignleft",
                fallback: "LO",
                primary: CopyToClipboardAction(DeveloperToolsEngine.lorem(words: 24)),
                isValue: false
            ),
            makeResult(
                id: "dev.random-email.default",
                title: "Generate Random Email",
                subtitle: "Copy a disposable-looking email address",
                icon: "at",
                fallback: "RD",
                primary: CopyToClipboardAction(DeveloperToolsEngine.randomEmail()),
                isValue: false
            )
        ]
    }

    private func staticCommandResults(query: SearchScoring.PreparedQuery, customAliases: [String: [String]],
                                      sensitivity: SearchSensitivity) -> [CommandResult] {
        staticCommands.compactMap { command in
            let aliases = customAliases[command.id] ?? []
            guard SearchScoring.match(
                query: query,
                title: command.title,
                subtitle: command.subtitle,
                keywords: [],
                aliases: command.aliases + aliases,
                sensitivity: sensitivity
            ) != nil else { return nil }
            return makeResult(
                id: command.id,
                title: command.title,
                subtitle: command.subtitle,
                icon: command.icon,
                fallback: command.fallback,
                searchAliases: command.aliases + aliases,
                searchKeywords: [],
                primary: command.action,
                isValue: false
            )
        }
    }

    private func uuidResults(query: String) -> [CommandResult] {
        guard let payload = SearchScoring.payload(in: query, prefixes: ["uuid", "guid"]) else { return [] }
        let count = min(max(Int(payload.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 1, 1), 20)
        let values = (0..<count).map { _ in UUID().uuidString }
        return values.enumerated().map { index, value in
            makeResult(
                id: "dev.uuid.\(index).\(value)",
                title: value,
                subtitle: count == 1 ? "UUID" : "UUID \(index + 1) of \(count)",
                icon: "number",
                fallback: "ID",
                primary: CopyToClipboardAction(value)
            )
        }
    }

    private func base64Results(query: String) -> [CommandResult] {
        let encodePrefixes = ["base64 encode", "b64 encode", "encode base64"]
        let decodePrefixes = ["base64 decode", "b64 decode", "decode base64"]

        if let payload = SearchScoring.payload(in: query, prefixes: encodePrefixes), payload.isEmpty == false,
           let encoded = DeveloperToolsEngine.base64Encode(payload) {
            return [
                makeResult(
                    id: "dev.base64.encode.\(encoded.hashValue)",
                    title: encoded,
                    subtitle: "Base64 encoded",
                    icon: "lock.doc",
                    fallback: "64",
                    primary: CopyToClipboardAction(encoded),
                    secondary: [CommandAction(id: "dev.base64.encode.paste", title: "Paste", behavior: PasteTextAction(encoded))]
                )
            ]
        }

        if let payload = SearchScoring.payload(in: query, prefixes: decodePrefixes), payload.isEmpty == false,
           let decoded = DeveloperToolsEngine.base64Decode(payload) {
            return [
                makeResult(
                    id: "dev.base64.decode.\(decoded.hashValue)",
                    title: decoded,
                    subtitle: "Base64 decoded",
                    icon: "lock.open",
                    fallback: "64",
                    primary: CopyToClipboardAction(decoded),
                    secondary: [CommandAction(id: "dev.base64.decode.paste", title: "Paste", behavior: PasteTextAction(decoded))]
                )
            ]
        }

        guard let payload = SearchScoring.payload(in: query, prefixes: ["base64", "b64"]), payload.isEmpty == false else { return [] }
        var results: [CommandResult] = []
        if let encoded = DeveloperToolsEngine.base64Encode(payload) {
            results.append(makeResult(id: "dev.base64.any.encode.\(encoded.hashValue)", title: encoded, subtitle: "Encoded", icon: "lock.doc",
                fallback: "64", primary: CopyToClipboardAction(encoded)))
        }
        if let decoded = DeveloperToolsEngine.base64Decode(payload) {
            results.append(makeResult(id: "dev.base64.any.decode.\(decoded.hashValue)", title: decoded, subtitle: "Decoded", icon: "lock.open",
                fallback: "64", primary: CopyToClipboardAction(decoded)))
        }
        return results
    }

    private func jsonResults(query: String) -> [CommandResult] {
        guard let payload = SearchScoring.payload(in: query, prefixes: ["json", "format json", "pretty json"]), payload.isEmpty == false,
              let formatted = DeveloperToolsEngine.formatJSON(payload) else { return [] }
        return [
            makeResult(
                id: "dev.json.\(formatted.hashValue)",
                title: "Formatted JSON",
                subtitle: DeveloperToolsEngine.compactPreview(formatted),
                icon: "curlybraces.square",
                fallback: "JS",
                primary: CopyToClipboardAction(formatted),
                secondary: [CommandAction(id: "dev.json.paste", title: "Paste", behavior: PasteTextAction(formatted))],
                isValue: false
            )
        ]
    }

    private func caseResults(query: String) -> [CommandResult] {
        guard let payload = SearchScoring.payload(in: query, prefixes: ["case", "change case", "convert case"]), payload.isEmpty == false else { return [] }
        return DeveloperToolsEngine.caseVariants(for: payload).enumerated().map { index, variant in
            makeResult(
                id: "dev.case.\(variant.style).\(variant.value.hashValue)",
                title: variant.value,
                subtitle: variant.style,
                icon: "character.cursor.ibeam",
                fallback: "Aa",
                primary: CopyToClipboardAction(variant.value),
                secondary: [CommandAction(id: "dev.case.\(variant.style).paste", title: "Paste", behavior: PasteTextAction(variant.value))]
            )
        }
    }

    private func unixTimestampResults(query: String) -> [CommandResult] {
        let isBareTimestamp = query.range(of: #"^\d{10}(\d{3})?$"#, options: .regularExpression) != nil
        guard let payload = isBareTimestamp ? query : SearchScoring.payload(in: query, prefixes: ["unix", "timestamp"]),
              payload.isEmpty == false else { return [] }
        return DeveloperToolsEngine.timestampConversions(for: payload).enumerated().map { index, conversion in
            makeResult(
                id: "dev.timestamp.\(index).\(conversion.value.hashValue)",
                title: conversion.value,
                subtitle: conversion.label,
                icon: "clock",
                fallback: "TS",
                primary: CopyToClipboardAction(conversion.value)
            )
        }
    }

    private func bitwiseResults(query: String) -> [CommandResult] {
        let candidate: String?
        if let payload = SearchScoring.payload(in: query, prefixes: ["bit", "bits", "bitwise"]), payload.isEmpty == false {
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
            return [
                bitwiseResult(title: String(output), subtitle: "~\(value) over \(width)-bit mask", expression: String(output)),
                bitwiseResult(title: String(output, radix: 2), subtitle: "Binary", expression: String(output)),
                bitwiseResult(title: String(output, radix: 16).uppercased(), subtitle: "Hex", expression: String(output))
            ]
        case let .shiftLeft(value, amount):
            return shiftResults(output: amount >= 64 ? 0 : value << amount, subtitle: "Shift left")
        case let .shiftRight(value, amount):
            return shiftResults(output: amount >= 64 ? 0 : value >> amount, subtitle: "Shift right")
        }
    }

    private func shiftResults(output: UInt64, subtitle: String) -> [CommandResult] {
        [
            bitwiseResult(title: String(output), subtitle: subtitle, expression: String(output)),
            bitwiseResult(title: String(output, radix: 2), subtitle: "Binary", expression: String(output)),
            bitwiseResult(title: String(output, radix: 16).uppercased(), subtitle: "Hex", expression: String(output))
        ]
    }

    private func bitwiseOutputs(lhs: UInt64, rhs: UInt64, label: String, value: UInt64) -> [CommandResult] {
        [
            bitwiseResult(title: String(value), subtitle: "\(lhs) \(label) \(rhs)", expression: "\(lhs) \(label) \(rhs)"),
            bitwiseResult(title: String(value, radix: 2), subtitle: "Binary", expression: String(value)),
            bitwiseResult(title: String(value, radix: 16).uppercased(), subtitle: "Hex", expression: String(value))
        ]
    }

    private func bitwiseResult(title: String, subtitle: String, expression: String) -> CommandResult {
        makeResult(
            id: "dev.bitwise.\(expression.hashValue).\(subtitle)",
            title: title,
            subtitle: subtitle,
            icon: "candybarphone",
            fallback: "01",
            primary: CopyToClipboardAction(title)
        )
    }

    private func baseConversionResults(query: String) -> [CommandResult] {
        let candidate: String?
        if let payload = SearchScoring.payload(in: query, prefixes: ["base", "radix", "convert base", "base convert"]), payload.isEmpty == false {
            candidate = payload
        } else if DeveloperToolsEngine.looksLikeRadixValue(query) {
            candidate = query
        } else {
            candidate = nil
        }
        guard let conversion = candidate.flatMap(DeveloperToolsEngine.baseConversion) ?? DeveloperToolsEngine.namedBaseConversion(from: query)
        else { return [] }
        return conversion.map { item in
            makeResult(
                id: "dev.base.\(item.label).\(item.value.hashValue)",
                title: item.value,
                subtitle: item.label,
                icon: "number",
                fallback: "10",
                primary: CopyToClipboardAction(item.value)
            )
        }
    }

    private func hashResults(query: String) -> [CommandResult] {
        DeveloperToolsEngine.hashAlgorithms.compactMap { algorithm in
            guard let payload = SearchScoring.payload(in: query, prefixes: [algorithm.prefix]), payload.isEmpty == false else { return nil }
            let digest = algorithm.digest(Data(payload.utf8))
            return makeResult(id: "dev.hash.\(algorithm.prefix).\(digest)", title: digest, subtitle: algorithm.label, icon: "number.square",
                fallback: "#", primary: CopyToClipboardAction(digest))
        }
    }

    private func urlCodingResults(query: String) -> [CommandResult] {
        let codings: [(prefixes: [String], label: String, transform: (String) -> String?)] = [
            (["url encode", "urlencode", "encode url"], "URL encoded", DeveloperToolsEngine.urlEncode),
            (["url decode", "urldecode", "decode url"], "URL decoded", { $0.removingPercentEncoding })
        ]
        return codings.compactMap { coding in
            guard let payload = SearchScoring.payload(in: query, prefixes: coding.prefixes), payload.isEmpty == false,
                  let output = coding.transform(payload) else { return nil }
            return makeResult(id: "dev.url.\(coding.label).\(output.hashValue)", title: output, subtitle: coding.label, icon: "link", fallback: "%",
                primary: CopyToClipboardAction(output),
                secondary: [CommandAction(id: "dev.url.\(coding.label).paste", title: "Paste", behavior: PasteTextAction(output))])
        }
    }

    private func colorResults(query: String) -> [CommandResult] {
        DeveloperToolsEngine.colorConversions(for: query).map { item in
            makeResult(id: "dev.color.\(item.label).\(item.value)", title: item.value, subtitle: item.label, icon: "paintpalette", fallback: "C",
                primary: CopyToClipboardAction(item.value))
        }
    }

    private func wordCountResults(query: String) -> [CommandResult] {
        guard let payload = SearchScoring.payload(in: query, prefixes: ["word count", "count words", "wc"]), payload.isEmpty == false else { return [] }
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
                primary: CopyToClipboardAction(String(stats.words)),
                secondary: [
                    CommandAction(id: "dev.wordcount.characters", title: "Copy Characters", behavior: CopyToClipboardAction(String(stats.characters))),
                    CommandAction(id: "dev.wordcount.summary", title: "Copy Summary", behavior: CopyToClipboardAction("\(title) · \(subtitle)"))
                ],
                isValue: false
            )
        ]
    }

    private func loremResults(query: String, sensitivity: SearchSensitivity) -> [CommandResult] {
        guard let payload = SearchScoring.payload(in: query, prefixes: ["lorem", "ipsum"]),
              payload.isEmpty == false
                || SearchScoring.match(
                    query: query, title: "Lorem Ipsum", subtitle: nil, keywords: [],
                    aliases: ["lorem", "ipsum"], sensitivity: sensitivity
                ) != nil
        else { return [] }
        let count = min(max(Int(payload.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 24, 1), 200)
        let text = DeveloperToolsEngine.lorem(words: count)
        return [
            makeResult(
                id: "dev.lorem.\(count)",
                title: "Lorem Ipsum (\(count) words)",
                subtitle: DeveloperToolsEngine.compactPreview(text),
                icon: "text.alignleft",
                fallback: "LO",
                primary: CopyToClipboardAction(text),
                secondary: [CommandAction(id: "dev.lorem.paste", title: "Paste", behavior: PasteTextAction(text))],
                isValue: false
            )
        ]
    }

    private func randomDataResults(query: String, sensitivity: SearchSensitivity) -> [CommandResult] {
        guard let payload = SearchScoring.payload(in: query, prefixes: ["random", "faker"]),
              payload.isEmpty == false
                || SearchScoring.match(
                    query: query, title: "Random Data", subtitle: nil, keywords: [],
                    aliases: ["random", "faker"], sensitivity: sensitivity
                ) != nil
        else { return [] }
        let kind = payload.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let items = DeveloperToolsEngine.randomItems(matching: kind)
        return items.enumerated().map { index, item in
            makeResult(
                id: "dev.random.\(item.label).\(item.value.hashValue)",
                title: item.value,
                subtitle: item.label,
                icon: "dice",
                fallback: "RD",
                primary: CopyToClipboardAction(item.value),
                secondary: [CommandAction(id: "dev.random.\(item.label).paste", title: "Paste", behavior: PasteTextAction(item.value))]
            )
        }
    }

    private func makeResult(
        id: String,
        title: String,
        subtitle: String,
        icon: String,
        fallback: String,
        searchAliases: [String] = [],
        searchKeywords: [String] = [],
        primary: any ResultAction,
        secondary: [CommandAction] = [],
        isValue: Bool = true
    ) -> CommandResult {
        CommandResult(
            id: id,
            title: title,
            subtitle: subtitle,
            icon: CommandIcon(fallback: fallback, systemName: icon),
            searchAliases: searchAliases,
            searchKeywords: searchKeywords,
            payload: isValue ? .value(label: subtitle) : .command,
            primaryAction: CommandAction(id: id + ".primary", title: "Copy", behavior: primary),
            secondaryActions: secondary
        )
    }

    private var staticCommands: [StaticCommand] { [
        StaticCommand(id: "dev.uuid", title: "Generate UUID", subtitle: "Copy a new UUID", aliases: ["uuid", "guid", "identifier"], icon: "number",
            fallback: "ID",  action: CopyToClipboardAction(UUID().uuidString)),
        StaticCommand(
            id: "dev.base64", title: "Base64 Encode or Decode", subtitle: "Transform text to or from base64",
            aliases: ["base64", "b64", "encode", "decode"], icon: "lock.doc", fallback: "64",
            action: OpenDeveloperToolsAction(tool: "base64")
        ),
        StaticCommand(
            id: "dev.json", title: "Format JSON", subtitle: "Pretty-print JSON into readable output",
            aliases: ["json", "pretty json", "format json"], icon: "curlybraces.square", fallback: "JS",
            action: OpenDeveloperToolsAction(tool: "json")
        ),
        StaticCommand(
            id: "dev.case", title: "Change Case", subtitle: "Convert text to camel, snake, kebab, and more",
            aliases: ["case", "change case", "convert case"], icon: "character.cursor.ibeam", fallback: "Aa",
            action: OpenDeveloperToolsAction(tool: "case")
        ),
        StaticCommand(id: "dev.timestamp", title: "Unix Timestamp", subtitle: "Convert timestamps and ISO dates", aliases: ["unix", "timestamp",
            "epoch"], icon: "clock", fallback: "TS",  action: OpenDeveloperToolsAction(tool: "timestamp")),
        StaticCommand(
            id: "dev.wordcount", title: "Word Count", subtitle: "Count words, characters, lines, and paragraphs",
            aliases: ["word count", "count words", "wc"], icon: "textformat.abc", fallback: "WC",
            action: OpenDeveloperToolsAction(tool: "wordCount")
        ),
        StaticCommand(
            id: "dev.lorem", title: "Lorem Ipsum", subtitle: "Generate placeholder copy",
            aliases: ["lorem", "ipsum", "placeholder text"], icon: "text.alignleft", fallback: "LO",
            action: CopyToClipboardAction(DeveloperToolsEngine.lorem(words: 24))
        ),
        StaticCommand(
            id: "dev.random", title: "Random Data", subtitle: "Generate emails, hex colors, numbers, and slugs",
            aliases: ["random", "faker", "fake data"], icon: "dice", fallback: "RD",
            action: CopyToClipboardAction(DeveloperToolsEngine.randomHexColor())
        )
    ] }
}

private struct StaticCommand {
    let id: String
    let title: String
    let subtitle: String
    let aliases: [String]
    let icon: String
    let fallback: String
    let action: any ResultAction
}
