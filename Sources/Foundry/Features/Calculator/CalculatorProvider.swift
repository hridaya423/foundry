import Foundation
import FoundryDomain
import FoundryServices
import os

final class CalculatorProvider: CommandProvider {
    typealias RateSource = @Sendable (URL) async -> [FrankfurterRate]?

    let id = "foundry.calculator"
    private let rateSource: RateSource
    private let rateCache: CurrencyRateCache

    init(rateSource: @escaping RateSource = CalculatorProvider.fetchRates, rateCache: CurrencyRateCache = .shared) {
        self.rateSource = rateSource
        self.rateCache = rateCache
    }

    static let fetchRates: RateSource = { url in
        await BestEffort.attempt("fetch exchange rates") {
            let (data, _) = try await URLSession.shared.data(from: url)
            return try JSONDecoder().decode([FrankfurterRate].self, from: data)
        }
    }

    func search(_ request: CommandSearchRequest) async -> [CommandResult] {
        let trimmed = request.query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == "calc" || trimmed == "=" || trimmed.lowercased() == "calc history" {
            return Self.historyResults()
        }

        let conversions = Self.convert(request.query)
        if conversions.isEmpty == false {
            return Self.conversionResults(conversions)
        }

        let currencyConversions = await convertCurrency(request.query)
        if currencyConversions.isEmpty == false {
            return Self.conversionResults(currencyConversions)
        }

        let explicitCalculation = Self.isExplicitCalculation(request.query)
        let expression = Self.expression(from: request.query)
        guard expression.isEmpty == false, Self.looksLikeCalculation(expression, explicit: explicitCalculation) else { return [] }

        guard let evaluation = Self.evaluate(expression: expression) else { return [] }
        let result = evaluation.result
        return [
            CommandResult(
                id: "calculator.\(expression)",
                title: result,
                subtitle: evaluation.expression,
                icon: CommandIcon(fallback: "=", systemName: "function"),
                route: .calculator,
                payload: .calculation(expression: evaluation.expression, value: result),
                primaryAction: CommandAction(id: "calculator.\(expression).copy", title: "Copy", behavior: CopyToClipboardAction(evaluation.copyValue)),
                secondaryActions: [
                    CommandAction(id: "calculator.\(expression).copy-expression", title: "Copy Expression",
                        behavior: CopyToClipboardAction(evaluation.expression))
                ]
            )
        ]
    }

    private static func expression(from query: String) -> String {
        var expression = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if expression.lowercased().hasPrefix("calc ") {
            expression.removeFirst(5)
        } else if expression.hasPrefix("=") {
            expression.removeFirst()
        }

        if expression.range(of: #"[a-z]\("#, options: [.regularExpression, .caseInsensitive]) == nil {
            expression = expression.replacingOccurrences(of: #"(?<=\d),(?=\d{3}(?!\d))"#, with: "", options: .regularExpression)
        }
        for (words, symbol) in wordOperators {
            expression = expression.replacingOccurrences(of: words, with: symbol, options: [.regularExpression, .caseInsensitive])
        }

        return expression
            .replacingOccurrences(of: "×", with: "*")
            .replacingOccurrences(of: "÷", with: "/")
            .replacingOccurrences(of: "−", with: "-")
            .replacingOccurrences(of: "π", with: "pi")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static let wordOperators = [
        ("plus", "+"), ("minus", "-"), ("times|multiplied by|x", "*"), ("divided by|over", "/"), ("mod", " % ")
    ].map { (#"(?<=[\d%)])\s+(?:"# + $0 + #")\s+(?=[\d(.-])"#, $1) } + [(#"(?<=%)\s+of\s+(?=[\d(.])"#, "*")]

    private static func isExplicitCalculation(_ query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasPrefix("=") || trimmed.lowercased().hasPrefix("calc ")
    }

    private static func looksLikeCalculation(_ expression: String, explicit: Bool) -> Bool {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.,_ +-*/%^!()=√")
        guard expression.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return false }

        let hasOperator = expression.contains { "+-*/%^!()=√".contains($0) }
        let hasFunction = expression.contains("(") && expression.rangeOfCharacter(from: .letters) != nil
        return explicit || hasOperator || hasFunction
    }

    private static func evaluate(expression: String) -> CalculatorEvaluation? {
        if let solution = solveEquation(expression) {
            return solution
        }

        var parser = CalculatorParser(expression: expression)
        guard let value = try? parser.parse(), value.isFinite else { return nil }
        let result = format(value)
        return CalculatorEvaluation(expression: expression, result: result, copyValue: result)
    }

    private static func historyResults() -> [CommandResult] {
        CalculatorHistoryStore.shared.entries.enumerated().map { index, entry in
            CommandResult(
                id: "calculator.history.\(index).\(entry.expression)",
                title: entry.result,
                subtitle: entry.expression,
                icon: CommandIcon(fallback: "=", systemName: "clock"),
                route: .calculator,
                payload: .calculation(expression: entry.expression, value: entry.result),
                primaryAction: CommandAction(id: "calculator.history.\(index).copy", title: "Copy", behavior: CopyToClipboardAction(entry.result)),
                secondaryActions: [
                    CommandAction(id: "calculator.history.\(index).copy-expression", title: "Copy Expression",
                        behavior: CopyToClipboardAction(entry.expression))
                ]
            )
        }
    }

    private static func conversionResults(_ conversions: [CalculatorEvaluation]) -> [CommandResult] {
        conversions.enumerated().map { index, conversion in
            CommandResult(
                id: "calculator.convert.\(conversion.expression).\(index)",
                title: conversion.result,
                subtitle: conversion.subtitle,
                icon: CommandIcon(fallback: "⇄", systemName: "arrow.left.arrow.right"),
                route: .calculator,
                payload: .calculationConversion(expression: conversion.expression, value: conversion.result),
                primaryAction: CommandAction(id: "calculator.convert.\(index).copy", title: "Copy",
                    behavior: CopyToClipboardAction(conversion.copyValue)),
                secondaryActions: [
                    CommandAction(id: "calculator.convert.\(index).copy-expression", title: "Copy Conversion",
                        behavior: CopyToClipboardAction("\(conversion.expression) = \(conversion.result)"))
                ]
            )
        }
    }

    private func convertCurrency(_ query: String) async -> [CalculatorEvaluation] {
        guard let request = Self.currencyRequest(from: query) else { return [] }
        let quotes = request.quote.map { [$0] } ?? Self.preferredCurrencyQuotes(base: request.base)
        guard quotes.isEmpty == false else { return [] }

        var components = URLComponents(string: "https://api.frankfurter.dev/v2/rates")
        components?.queryItems = [
            URLQueryItem(name: "base", value: request.base),
            URLQueryItem(name: "quotes", value: quotes.joined(separator: ","))
        ]
        guard let url = components?.url else { return [] }
        let cacheKey = "\(request.base):\(quotes.sorted().joined(separator: ","))"
        let rates: [FrankfurterRate]
        if let cached = rateCache.value(for: cacheKey) {
            rates = cached
        } else {
            guard let fetched = await rateSource(url) else { return [] }
            rateCache.store(fetched, for: cacheKey)
            rates = fetched
        }

        let expression = Self.currencyAmount(request.amount, code: request.base)
        let ratesByQuote = Dictionary(rates.map { ($0.quote, $0) }, uniquingKeysWith: { first, _ in first })
        return quotes.compactMap { ratesByQuote[$0] }.map { rate in
            let result = Self.currencyAmount(request.amount * rate.rate, code: rate.quote)
            return CalculatorEvaluation(expression: expression, result: result, copyValue: result, note: rate.date.map(Self.rateNote))
        }
    }

    static func rateNote(isoDay: String) -> String {
        guard let date = try? Date(isoDay, strategy: .iso8601.year().month().day()) else { return String(localized: "Rate from \(isoDay)") }
        return String(localized: "Rate from \(date.formatted(.dateTime.day().month(.abbreviated)))")
    }

    static let numberPattern = #"[-+]?(?:\d{1,3}(?:,\d{3})+(?:\.\d+)?|\d+(?:[\.,]\d+)?)"#

    static func numberValue(_ text: String) -> Double? {
        let groupsThousands = text.range(of: #"^[-+]?\d{1,3}(?:,\d{3})+(?:\.\d+)?$"#, options: .regularExpression) != nil
        return Double(text.replacingOccurrences(of: ",", with: groupsThousands ? "" : "."))
    }

    private static let symbolCurrencyRegex = try! NSRegularExpression(
        pattern: #"^([$€£¥₹])\s*("# + numberPattern + #")(?:\s*(?:to|in)\s*([a-z]{3}|[$€£¥₹]))?$"#
    )
    private static let wordCurrencyRegex = try! NSRegularExpression(
        pattern: #"^("# + numberPattern + #")\s*([a-z]{3}|dollars?|bucks?|usd|euros?|eur|pounds?|gbp|yen|jpy|rupees?|inr|cad|aud|chf|cny)"#
            + #"(?:\s*(?:to|in)\s*([a-z]{3}|[$€£¥₹]|dollars?|usd|euros?|eur|pounds?|gbp|yen|jpy|rupees?|inr|cad|aud|chf|cny))?$"#
    )

    private static func currencyRequest(from query: String) -> CurrencyRequest? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let request = parseCurrency(trimmed, regex: symbolCurrencyRegex, amountIndex: 2, baseIndex: 1, quoteIndex: 3) {
            return request
        }
        return parseCurrency(trimmed, regex: wordCurrencyRegex, amountIndex: 1, baseIndex: 2, quoteIndex: 3)
    }

    private static func parseCurrency(_ value: String, regex: NSRegularExpression, amountIndex: Int, baseIndex: Int, quoteIndex: Int) -> CurrencyRequest? {
        guard let match = regex
            .firstMatch(in: value, range: NSRange(value.startIndex..<value.endIndex, in: value)),
            let amountRange = Range(match.range(at: amountIndex), in: value),
            let baseRange = Range(match.range(at: baseIndex), in: value),
            let amount = numberValue(String(value[amountRange])),
            let base = currencyCode(String(value[baseRange])) else { return nil }

        let quote: String?
        if match.range(at: quoteIndex).location != NSNotFound,
           let quoteRange = Range(match.range(at: quoteIndex), in: value) {
            guard let code = currencyCode(String(value[quoteRange])) else { return nil }
            quote = code
        } else {
            quote = nil
        }

        if let quote, quote == base { return nil }
        return CurrencyRequest(amount: amount, base: base, quote: quote)
    }

    private static func currencyCode(_ value: String) -> String? {
        switch value.lowercased() {
        case "$", "usd", "dollar", "dollars", "buck", "bucks": return "USD"
        case "€", "eur", "euro", "euros": return "EUR"
        case "£", "gbp", "pound", "pounds": return "GBP"
        case "¥", "jpy", "yen": return "JPY"
        case "₹", "inr", "rupee", "rupees": return "INR"
        case "cad": return "CAD"
        case "aud": return "AUD"
        case "chf": return "CHF"
        case "cny": return "CNY"
        default:
            let uppercased = value.uppercased()
            return isoCurrencyCodes.contains(uppercased) ? uppercased : nil
        }
    }

    private static let isoCurrencyCodes: Set<String> = [
        "AED", "ARS", "AUD", "BDT", "BGN", "BRL", "CAD", "CHF", "CLP", "CNY", "COP", "CZK", "DKK", "EGP", "EUR", "GBP", "HKD", "HUF",
        "IDR", "ILS", "INR", "ISK", "JPY", "KRW", "KWD", "MXN", "MYR", "NGN", "NOK", "NZD", "PEN", "PHP", "PKR", "PLN", "QAR", "RON",
        "RUB", "SAR", "SEK", "SGD", "THB", "TRY", "TWD", "UAH", "USD", "VND", "ZAR"
    ]

    private static func currencyName(_ code: String) -> String {
        switch code.uppercased() {
        case "USD": "US Dollar"
        case "EUR": "Euro"
        case "GBP": "British Pound"
        case "JPY": "Japanese Yen"
        case "INR": "Indian Rupee"
        case "CAD": "Canadian Dollar"
        case "AUD": "Australian Dollar"
        case "CHF": "Swiss Franc"
        case "CNY": "Chinese Yuan"
        default: code.uppercased()
        }
    }

    private static func currencyAmount(_ value: Double, code: String) -> String {
        "\(currencySymbol(code))\(formatCurrency(value)) \(currencyName(code))"
    }

    private static func currencySymbol(_ code: String) -> String {
        switch code.uppercased() {
        case "USD": "$"
        case "EUR": "€"
        case "GBP": "£"
        case "JPY": "¥"
        case "INR": "₹"
        case "CAD": "C$"
        case "AUD": "A$"
        case "CNY": "CN¥"
        default: "\(code.uppercased()) "
        }
    }

    private static func preferredCurrencyQuotes(base: String) -> [String] {
        let preferred = LocalStateStore.shared.get(\.preferredCurrencyQuote)
        return ([preferred].compactMap { $0 } + defaultCurrencyQuotes)
            .filter { $0 != base }
            .reduce(into: []) { result, code in
                if result.contains(code) == false { result.append(code) }
            }
    }

    private static func formatCurrency(_ value: Double) -> String {
        if let integer = integerText(value) { return integer }
        return String(format: "%.2f", value)
            .replacingOccurrences(of: #"\.0+$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(\.\d)0$"#, with: "$1", options: .regularExpression)
    }

    private static let defaultCurrencyQuotes = ["USD", "EUR", "GBP", "INR", "JPY", "CAD", "AUD"]

    private static func solveEquation(_ expression: String) -> CalculatorEvaluation? {
        let parts = expression.split(separator: "=", omittingEmptySubsequences: false)
        guard parts.count == 2 else { return nil }

        let left = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
        let right = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
        guard left.isEmpty == false, right.isEmpty == false else { return nil }

        let variables = unknownIdentifiers(in: left + " " + right)
        guard variables.count == 1, let variable = variables.first else { return nil }

        let evaluator: (Double) -> Double? = { value in
            var leftParser = CalculatorParser(expression: left, variables: [variable: value])
            var rightParser = CalculatorParser(expression: right, variables: [variable: value])
            guard let leftValue = try? leftParser.parse(), let rightValue = try? rightParser.parse() else { return nil }
            let difference = leftValue - rightValue
            return difference.isFinite ? difference : nil
        }

        guard let root = findRoot(evaluator) else { return nil }
        let formattedRoot = format(root)
        let result = "\(variable) = \(formattedRoot)"
        return CalculatorEvaluation(expression: "\(left) = \(right)", result: result, copyValue: formattedRoot)
    }

    private static func unknownIdentifiers(in expression: String) -> Set<String> {
        let characters = Array(expression)
        var identifiers = Set<String>()
        var index = 0

        while index < characters.count {
            guard characters[index].isLetter else {
                index += 1
                continue
            }

            let start = index
            while index < characters.count, characters[index].isLetter || characters[index].isNumber || characters[index] == "_" {
                index += 1
            }

            let identifier = String(characters[start..<index]).lowercased()
            if CalculatorParser.isKnownIdentifier(identifier) == false {
                identifiers.insert(identifier)
            }
        }

        return identifiers
    }

    private static func findRoot(_ function: (Double) -> Double?) -> Double? {
        let directCandidates: [Double] = [0, 1, -1, 2, -2, 10, -10, 100, -100]
        for candidate in directCandidates {
            if let value = function(candidate), abs(value) < 0.000000001 {
                return candidate
            }
        }

        let scanPoints = rootScanPoints()
        var previousX: Double?
        var previousY: Double?

        for x in scanPoints {
            guard let y = function(x), y.isFinite else {
                previousX = nil
                previousY = nil
                continue
            }

            if abs(y) < 0.000000001 { return x }
            if let lastX = previousX, let lastY = previousY, lastY.sign != y.sign {
                return bisectRoot(function, lower: lastX, upper: x)
            }

            previousX = x
            previousY = y
        }

        for seed in directCandidates + [-50, 50, -1_000, 1_000] {
            if let root = newtonRoot(function, seed: seed) {
                return root
            }
        }

        return nil
    }

    private static func rootScanPoints() -> [Double] {
        var points = Set<Double>()
        for value in stride(from: -200.0, through: 200.0, by: 1.0) {
            points.insert(value)
        }
        for exponent in -6...6 {
            let value = pow(10, Double(exponent))
            points.insert(value)
            points.insert(-value)
        }
        return points.sorted()
    }

    private static func bisectRoot(_ function: (Double) -> Double?, lower: Double, upper: Double) -> Double? {
        var low = lower
        var high = upper
        guard var lowValue = function(low), let highValue = function(high), lowValue.sign != highValue.sign else { return nil }

        for _ in 0..<80 {
            let middle = (low + high) / 2
            guard let middleValue = function(middle), middleValue.isFinite else { return nil }
            if abs(middleValue) < 0.000000001 { return middle }
            if lowValue.sign == middleValue.sign {
                low = middle
                lowValue = middleValue
            } else {
                high = middle
            }
        }

        return (low + high) / 2
    }

    private static func newtonRoot(_ function: (Double) -> Double?, seed: Double) -> Double? {
        var x = seed
        for _ in 0..<40 {
            guard let y = function(x), y.isFinite else { return nil }
            if abs(y) < 0.000000001 { return x }

            let step = max(0.000001, abs(x) * 0.000001)
            guard let y1 = function(x + step), let y0 = function(x - step) else { return nil }
            let derivative = (y1 - y0) / (2 * step)
            guard derivative.isFinite, abs(derivative) > 0.000000000001 else { return nil }

            let next = x - y / derivative
            guard next.isFinite, abs(next) < 1_000_000_000 else { return nil }
            if abs(next - x) < 0.000000001 { return next }
            x = next
        }
        return nil
    }

    private static func format(_ value: Double) -> String {
        if let integer = integerText(value) { return integer }
        return String(format: "%.12g", value)
    }

    static func formatConversion(_ value: Double) -> String {
        if let integer = integerText(value) { return integer }
        let magnitude = abs(value)
        let digits = magnitude >= 1 ? 2 : min(12, 2 - Int(log10(magnitude).rounded(.down)))
        return String(format: "%.\(digits)f", value).replacingOccurrences(of: #"\.?0+$"#, with: "", options: .regularExpression)
    }

    private static func integerText(_ value: Double) -> String? {
        guard abs(value.rounded() - value) < 0.0000000001, let integer = Int64(exactly: value.rounded()) else { return nil }
        return String(integer)
    }
}
