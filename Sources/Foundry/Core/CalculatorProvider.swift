import Foundation

final class CalculatorProvider: CommandProvider {
    let id = "foundry.calculator"

    func results(matching query: String) async -> [CommandResult] {
        let currencyConversions = await Self.convertCurrency(query)
        if currencyConversions.isEmpty == false {
            return Self.conversionResults(currencyConversions)
        }

        let conversions = Self.convert(query)
        if conversions.isEmpty == false {
            return Self.conversionResults(conversions)
        }

        let explicitCalculation = Self.isExplicitCalculation(query)
        let expression = Self.expression(from: query)
        guard expression.isEmpty == false, Self.looksLikeCalculation(expression, explicit: explicitCalculation) else { return [] }

        guard let evaluation = Self.evaluate(expression: expression) else { return [] }
        let result = evaluation.result
        return [
            CommandResult(
                id: "calculator.\(expression)",
                title: result,
                subtitle: evaluation.expression,
                icon: CommandIcon(fallback: "=", systemName: "function"),
                score: 98,
                primaryAction: CommandAction(id: "calculator.\(expression).copy", title: "Copy Result", kind: .copyToClipboard(evaluation.copyValue)),
                secondaryActions: [
                    CommandAction(id: "calculator.\(expression).copy-expression", title: "Copy Expression", kind: .copyToClipboard(evaluation.expression))
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

        return expression
            .replacingOccurrences(of: "×", with: "*")
            .replacingOccurrences(of: "÷", with: "/")
            .replacingOccurrences(of: "−", with: "-")
            .replacingOccurrences(of: "π", with: "pi")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

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

    private static func conversionResults(_ conversions: [CalculatorEvaluation]) -> [CommandResult] {
        conversions.enumerated().map { index, conversion in
            CommandResult(
                id: "calculator.convert.\(conversion.expression).\(index)",
                title: conversion.result,
                subtitle: conversion.expression,
                icon: CommandIcon(fallback: "⇄", systemName: "arrow.left.arrow.right"),
                score: 99 - Double(index) * 0.1,
                primaryAction: CommandAction(id: "calculator.convert.\(index).copy", title: "Copy Result", kind: .copyToClipboard(conversion.copyValue)),
                secondaryActions: [
                    CommandAction(id: "calculator.convert.\(index).copy-expression", title: "Copy Conversion", kind: .copyToClipboard("\(conversion.expression) = \(conversion.result)"))
                ]
            )
        }
    }

    private static func convertCurrency(_ query: String) async -> [CalculatorEvaluation] {
        guard let request = currencyRequest(from: query) else { return [] }
        let quotes = request.quote.map { [$0] } ?? preferredCurrencyQuotes(base: request.base)
        guard quotes.isEmpty == false else { return [] }

        var components = URLComponents(string: "https://api.frankfurter.dev/v2/rates")
        components?.queryItems = [
            URLQueryItem(name: "base", value: request.base),
            URLQueryItem(name: "quotes", value: quotes.joined(separator: ","))
        ]
        guard let url = components?.url,
              let (data, _) = try? await URLSession.shared.data(from: url),
              let rates = try? JSONDecoder().decode([FrankfurterRate].self, from: data) else { return [] }

        let expression = currencyAmount(request.amount, code: request.base)
        let ratesByQuote = Dictionary(uniqueKeysWithValues: rates.map { ($0.quote, $0) })
        return quotes.compactMap { ratesByQuote[$0] }.map { rate in
            let result = currencyAmount(request.amount * rate.rate, code: rate.quote)
            return CalculatorEvaluation(expression: expression, result: result, copyValue: result)
        }
    }

    private static func currencyRequest(from query: String) -> CurrencyRequest? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let symbolPattern = #"^([$€£¥₹])\s*([-+]?\d+(?:[\.,]\d+)?)(?:\s*(?:to|in)\s*([a-z]{3}|[$€£¥₹]))?$"#
        if let request = parseCurrency(trimmed, pattern: symbolPattern, amountIndex: 2, baseIndex: 1, quoteIndex: 3) {
            return request
        }

        let wordPattern = #"^([-+]?\d+(?:[\.,]\d+)?)\s*([a-z]{3}|dollars?|bucks?|usd|euros?|eur|pounds?|gbp|yen|jpy|rupees?|inr|cad|aud|chf|cny)(?:\s*(?:to|in)\s*([a-z]{3}|[$€£¥₹]|dollars?|usd|euros?|eur|pounds?|gbp|yen|jpy|rupees?|inr|cad|aud|chf|cny))?$"#
        return parseCurrency(trimmed, pattern: wordPattern, amountIndex: 1, baseIndex: 2, quoteIndex: 3)
    }

    private static func parseCurrency(_ value: String, pattern: String, amountIndex: Int, baseIndex: Int, quoteIndex: Int) -> CurrencyRequest? {
        guard let match = try? NSRegularExpression(pattern: pattern)
            .firstMatch(in: value, range: NSRange(value.startIndex..<value.endIndex, in: value)),
            let amountRange = Range(match.range(at: amountIndex), in: value),
            let baseRange = Range(match.range(at: baseIndex), in: value),
            let amount = Double(value[amountRange].replacingOccurrences(of: ",", with: ".")),
            let base = currencyCode(String(value[baseRange])) else { return nil }

        let quote: String?
        if match.range(at: quoteIndex).location != NSNotFound,
           let quoteRange = Range(match.range(at: quoteIndex), in: value) {
            quote = currencyCode(String(value[quoteRange]))
        } else {
            quote = nil
        }

        if let quote, quote == base { return nil }
        return CurrencyRequest(amount: amount, base: base, quote: quote)
    }

    private static func convert(_ query: String) -> [CalculatorEvaluation] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            .replacingOccurrences(of: "°", with: "")
        guard let match = try? NSRegularExpression(pattern: #"^([-+]?\d+(?:[\.,]\d+)?)\s*([a-z0-9/ ]+)$"#)
            .firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)),
            let valueRange = Range(match.range(at: 1), in: trimmed),
            let unitRange = Range(match.range(at: 2), in: trimmed) else { return [] }

        let valueText = String(trimmed[valueRange]).replacingOccurrences(of: ",", with: ".")
        guard let value = Double(valueText) else { return [] }
        let unit = String(trimmed[unitRange]).trimmingCharacters(in: .whitespacesAndNewlines)

        let conversions: [String]
        switch unit {
        case "f", "fahrenheit":
            conversions = ["\(formatConversion((value - 32) * 5 / 9)) celsius", "\(formatConversion((value - 32) * 5 / 9 + 273.15)) kelvin"]
        case "c", "celsius":
            conversions = ["\(formatConversion(value * 9 / 5 + 32)) fahrenheit", "\(formatConversion(value + 273.15)) kelvin"]
        case "k", "kelvin":
            conversions = ["\(formatConversion(value - 273.15)) celsius", "\(formatConversion((value - 273.15) * 9 / 5 + 32)) fahrenheit"]
        case "m", "meter", "meters", "metre", "metres":
            conversions = ["\(formatConversion(value / 1_000)) km", "\(formatConversion(value * 3.280839895)) ft", "\(formatConversion(value / 1_609.344)) mi"]
        case "km", "kilometer", "kilometers", "kilometre", "kilometres":
            conversions = ["\(formatConversion(value * 1_000)) m", "\(formatConversion(value * 0.6213711922)) mi"]
        case "cm", "centimeter", "centimeters", "centimetre", "centimetres":
            conversions = ["\(formatConversion(value / 100)) m", "\(formatConversion(value / 2.54)) in"]
        case "mm", "millimeter", "millimeters", "millimetre", "millimetres":
            conversions = ["\(formatConversion(value / 1_000)) m", "\(formatConversion(value / 25.4)) in"]
        case "um", "micrometer", "micrometers", "micron", "microns":
            conversions = ["\(formatConversion(value / 1_000)) mm", "\(formatConversion(value / 25_400)) in"]
        case "nm", "nanometer", "nanometers", "nanometre", "nanometres":
            conversions = ["\(formatConversion(value / 1_000_000)) mm", "\(formatConversion(value / 25_400_000)) in"]
        case "mi", "mile", "miles":
            conversions = ["\(formatConversion(value * 1_609.344)) m", "\(formatConversion(value * 1.609344)) km"]
        case "ft", "foot", "feet":
            conversions = ["\(formatConversion(value * 0.3048)) m", "\(formatConversion(value * 12)) in"]
        case "in", "inch", "inches":
            conversions = ["\(formatConversion(value * 2.54)) cm", "\(formatConversion(value / 12)) ft"]
        case "yd", "yard", "yards":
            conversions = ["\(formatConversion(value * 0.9144)) m", "\(formatConversion(value * 3)) ft"]
        case "nmi", "nauticalmile", "nauticalmiles":
            conversions = ["\(formatConversion(value * 1.852)) km", "\(formatConversion(value * 1.150779448)) mi"]
        case "kg", "kilogram", "kilograms":
            conversions = ["\(formatConversion(value * 2.2046226218)) lb", "\(formatConversion(value * 1_000)) g"]
        case "g", "gram", "grams":
            conversions = ["\(formatConversion(value / 1_000)) kg", "\(formatConversion(value * 0.0352739619)) oz"]
        case "lb", "lbs", "pound", "pounds":
            conversions = ["\(formatConversion(value * 0.45359237)) kg", "\(formatConversion(value * 16)) oz"]
        case "oz", "ounce", "ounces":
            conversions = ["\(formatConversion(value * 28.349523125)) g", "\(formatConversion(value / 16)) lb"]
        case "st", "stone", "stones":
            conversions = ["\(formatConversion(value * 14)) lb", "\(formatConversion(value * 6.35029318)) kg"]
        case "ton", "tons":
            conversions = ["\(formatConversion(value * 2_000)) lb", "\(formatConversion(value * 907.18474)) kg"]
        case "tonne", "tonnes", "t":
            conversions = ["\(formatConversion(value * 1_000)) kg", "\(formatConversion(value * 2_204.6226218)) lb"]
        case "l", "liter", "liters", "litre", "litres":
            conversions = ["\(formatConversion(value * 1_000)) ml", "\(formatConversion(value * 0.2641720524)) gal"]
        case "ml", "milliliter", "milliliters", "millilitre", "millilitres":
            conversions = ["\(formatConversion(value / 1_000)) L", "\(formatConversion(value * 0.0338140227)) fl oz"]
        case "qt", "quart", "quarts":
            conversions = ["\(formatConversion(value * 0.946352946)) L", "\(formatConversion(value * 32)) fl oz"]
        case "pt", "pint", "pints":
            conversions = ["\(formatConversion(value * 0.473176473)) L", "\(formatConversion(value * 16)) fl oz"]
        case "gal", "gallon", "gallons":
            conversions = ["\(formatConversion(value * 3.785411784)) L", "\(formatConversion(value * 128)) fl oz"]
        case "tsp", "teaspoon", "teaspoons":
            conversions = ["\(formatConversion(value * 4.928921594)) ml", "\(formatConversion(value / 3)) tbsp"]
        case "tbsp", "tablespoon", "tablespoons":
            conversions = ["\(formatConversion(value * 14.78676478)) ml", "\(formatConversion(value * 3)) tsp"]
        case "cup", "cups":
            conversions = ["\(formatConversion(value * 236.5882365)) ml", "\(formatConversion(value * 8)) fl oz"]
        case "floz", "fl oz":
            conversions = ["\(formatConversion(value * 29.57352956)) ml", "\(formatConversion(value / 8)) cup"]
        case "mph":
            conversions = ["\(formatConversion(value * 1.609344)) km/h", "\(formatConversion(value * 0.44704)) m/s"]
        case "kph", "kmh", "kmph", "km/h":
            conversions = ["\(formatConversion(value * 0.6213711922)) mph", "\(formatConversion(value / 3.6)) m/s"]
        case "ms", "mps", "m/s":
            conversions = ["\(formatConversion(value * 3.6)) km/h", "\(formatConversion(value * 2.2369362921)) mph"]
        case "kt", "kts", "knot", "knots":
            conversions = ["\(formatConversion(value * 1.852)) km/h", "\(formatConversion(value * 1.150779448)) mph"]
        case "mpg":
            conversions = ["\(formatConversion(235.214583 / value)) L/100km"]
        case "l/100km", "l100km":
            conversions = ["\(formatConversion(235.214583 / value)) mpg"]
        case "kb":
            conversions = ["\(formatConversion(value / 1_000)) MB", "\(formatConversion(value * 1_000)) bytes"]
        case "mb":
            conversions = ["\(formatConversion(value / 1_000)) GB", "\(formatConversion(value * 1_000)) KB"]
        case "gb":
            conversions = ["\(formatConversion(value / 1_000)) TB", "\(formatConversion(value * 1_000)) MB"]
        case "tb":
            conversions = ["\(formatConversion(value * 1_000)) GB", "\(formatConversion(value * 1_000_000)) MB"]
        case "kib":
            conversions = ["\(formatConversion(value / 1_024)) MiB", "\(formatConversion(value * 1_024)) bytes"]
        case "mib":
            conversions = ["\(formatConversion(value / 1_024)) GiB", "\(formatConversion(value * 1_024)) KiB"]
        case "gib":
            conversions = ["\(formatConversion(value / 1_024)) TiB", "\(formatConversion(value * 1_024)) MiB"]
        case "hz":
            conversions = ["\(formatConversion(value / 1_000)) kHz", "\(formatConversion(value * 60)) rpm"]
        case "khz":
            conversions = ["\(formatConversion(value * 1_000)) Hz", "\(formatConversion(value / 1_000)) MHz"]
        case "mhz":
            conversions = ["\(formatConversion(value * 1_000)) kHz", "\(formatConversion(value / 1_000)) GHz"]
        case "ghz":
            conversions = ["\(formatConversion(value * 1_000)) MHz", "\(formatConversion(value * 1_000_000_000)) Hz"]
        case "rpm":
            conversions = ["\(formatConversion(value / 60)) Hz"]
        case "s", "sec", "secs", "second", "seconds":
            conversions = ["\(formatConversion(value / 60)) min", "\(formatConversion(value / 3_600)) hr"]
        case "min", "mins", "minute", "minutes":
            conversions = ["\(formatConversion(value * 60)) sec", "\(formatConversion(value / 60)) hr"]
        case "h", "hr", "hrs", "hour", "hours":
            conversions = ["\(formatConversion(value * 60)) min", "\(formatConversion(value / 24)) days"]
        case "day", "days":
            conversions = ["\(formatConversion(value * 24)) hr", "\(formatConversion(value * 1_440)) min"]
        case "week", "weeks":
            conversions = ["\(formatConversion(value * 7)) days", "\(formatConversion(value * 168)) hr"]
        case "year", "years", "yr", "yrs":
            conversions = ["\(formatConversion(value * 365.25)) days", "\(formatConversion(value * 12)) months"]
        case "sqm", "m2":
            conversions = ["\(formatConversion(value * 10.7639104167)) ft²", "\(formatConversion(value / 1_000_000)) km²"]
        case "sqft", "ft2":
            conversions = ["\(formatConversion(value * 0.09290304)) m²", "\(formatConversion(value / 43_560)) acres"]
        case "acre", "acres":
            conversions = ["\(formatConversion(value * 43_560)) ft²", "\(formatConversion(value * 4_046.8564224)) m²"]
        case "hectare", "hectares", "ha":
            conversions = ["\(formatConversion(value * 10_000)) m²", "\(formatConversion(value * 2.4710538147)) acres"]
        case "sqkm", "km2":
            conversions = ["\(formatConversion(value * 1_000_000)) m²", "\(formatConversion(value * 0.3861021585)) mi²"]
        case "sqmi", "mi2":
            conversions = ["\(formatConversion(value * 2.5899881103)) km²", "\(formatConversion(value * 640)) acres"]
        case "psi":
            conversions = ["\(formatConversion(value * 6.8947572932)) kPa", "\(formatConversion(value * 0.0689475729)) bar"]
        case "pa":
            conversions = ["\(formatConversion(value / 1_000)) kPa", "\(formatConversion(value * 0.0001450377)) psi"]
        case "kpa":
            conversions = ["\(formatConversion(value * 0.1450377377)) psi", "\(formatConversion(value / 100)) bar"]
        case "bar":
            conversions = ["\(formatConversion(value * 100)) kPa", "\(formatConversion(value * 14.503773773)) psi"]
        case "atm":
            conversions = ["\(formatConversion(value * 101.325)) kPa", "\(formatConversion(value * 14.695948775)) psi"]
        case "n", "newton", "newtons":
            conversions = ["\(formatConversion(value * 0.2248089431)) lbf", "\(formatConversion(value / 9.80665)) kgf"]
        case "lbf":
            conversions = ["\(formatConversion(value * 4.4482216153)) N"]
        case "kgf":
            conversions = ["\(formatConversion(value * 9.80665)) N", "\(formatConversion(value * 2.2046226218)) lbf"]
        case "n m", "newtonmeter", "newtonmeters":
            conversions = ["\(formatConversion(value * 0.7375621493)) lb-ft", "\(formatConversion(value * 8.8507457676)) lb-in"]
        case "lbft", "lb-ft", "ftlb", "ft-lb":
            conversions = ["\(formatConversion(value * 1.3558179483)) N m"]
        case "lbin", "lb-in", "inlb", "in-lb":
            conversions = ["\(formatConversion(value * 0.112984829)) N m"]
        case "j", "joule", "joules":
            conversions = ["\(formatConversion(value / 1_000)) kJ", "\(formatConversion(value / 4_184)) kcal"]
        case "kj":
            conversions = ["\(formatConversion(value * 1_000)) J", "\(formatConversion(value / 4.184)) kcal"]
        case "cal", "calorie", "calories":
            conversions = ["\(formatConversion(value * 4.184)) J", "\(formatConversion(value / 1_000)) kcal"]
        case "kcal":
            conversions = ["\(formatConversion(value * 4.184)) kJ", "\(formatConversion(value * 1_000)) cal"]
        case "wh":
            conversions = ["\(formatConversion(value * 3_600)) J", "\(formatConversion(value / 1_000)) kWh"]
        case "kwh":
            conversions = ["\(formatConversion(value * 1_000)) Wh", "\(formatConversion(value * 3.6)) MJ"]
        case "w", "watt", "watts":
            conversions = ["\(formatConversion(value / 1_000)) kW", "\(formatConversion(value / 745.6998716)) hp"]
        case "kw":
            conversions = ["\(formatConversion(value * 1_000)) W", "\(formatConversion(value * 1.34102209)) hp"]
        case "hp", "horsepower":
            conversions = ["\(formatConversion(value * 745.6998716)) W", "\(formatConversion(value * 0.7456998716)) kW"]
        case "a", "amp", "amps", "ampere", "amperes":
            conversions = ["\(formatConversion(value * 1_000)) mA"]
        case "ma", "milliamp", "milliamps":
            conversions = ["\(formatConversion(value / 1_000)) A"]
        case "v", "volt", "volts":
            conversions = ["\(formatConversion(value * 1_000)) mV", "\(formatConversion(value / 1_000)) kV"]
        case "ohm", "ohms":
            conversions = ["\(formatConversion(value / 1_000)) kΩ", "\(formatConversion(value / 1_000_000)) MΩ"]
        case "deg", "degree", "degrees":
            conversions = ["\(formatConversion(value * .pi / 180)) rad"]
        case "rad", "radian", "radians":
            conversions = ["\(formatConversion(value * 180 / .pi)) deg"]
        case "px", "pixel", "pixels":
            conversions = ["\(formatConversion(value * 0.75)) pt", "\(formatConversion(value / 16)) rem"]
        case "pts", "point", "points":
            conversions = ["\(formatConversion(value / 0.75)) px", "\(formatConversion(value / 12)) pica"]
        case "rem", "em":
            conversions = ["\(formatConversion(value * 16)) px", "\(formatConversion(value * 12)) pt"]
        case "m/s2", "mps2":
            conversions = ["\(formatConversion(value / 9.80665)) g", "\(formatConversion(value * 3.280839895)) ft/s²"]
        case "gforce", "gee":
            conversions = ["\(formatConversion(value * 9.80665)) m/s²"]
        case "kg/m3", "kgm3":
            conversions = ["\(formatConversion(value * 0.0624279606)) lb/ft³", "\(formatConversion(value / 1_000)) g/cm³"]
        case "lb/ft3", "lbft3":
            conversions = ["\(formatConversion(value * 16.01846337)) kg/m³"]
        default:
            return []
        }

        let expression = "\(formatConversion(value)) \(displayUnit(unit))"
        return conversions.map { CalculatorEvaluation(expression: expression, result: $0, copyValue: $0) }
    }

    private static func displayUnit(_ unit: String) -> String {
        switch unit {
        case "f": "fahrenheit"
        case "c": "celsius"
        case "k": "kelvin"
        default: unit
        }
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
            return uppercased.count == 3 ? uppercased : nil
        }
    }

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
        let preferred = UserDefaults.standard.string(forKey: "preferredCurrencyQuote")
        return ([preferred].compactMap { $0 } + defaultCurrencyQuotes)
            .filter { $0 != base }
            .reduce(into: []) { result, code in
                if result.contains(code) == false { result.append(code) }
            }
    }

    private static func formatCurrency(_ value: Double) -> String {
        if abs(value.rounded() - value) < 0.0000000001 { return String(Int64(value.rounded())) }
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
        if abs(value.rounded() - value) < 0.0000000001 {
            guard value >= Double(Int64.min), value <= Double(Int64.max) else {
                return String(format: "%.12g", value)
            }
            return String(Int64(value.rounded()))
        }

        return String(format: "%.12g", value)
    }

    private static func formatConversion(_ value: Double) -> String {
        if abs(value.rounded() - value) < 0.0000000001 { return String(Int64(value.rounded())) }
        return String(format: "%.1f", value)
    }
}

private struct CalculatorEvaluation {
    let expression: String
    let result: String
    let copyValue: String
}

private struct CurrencyRequest {
    let amount: Double
    let base: String
    let quote: String?
}

private struct FrankfurterRate: Decodable {
    let base: String
    let quote: String
    let rate: Double
}

private struct CalculatorParser {
    enum ParseError: Error {
        case expectedNumber
        case expectedIdentifier
        case expectedClosingParenthesis
        case expectedFunctionArguments
        case unknownIdentifier(String)
        case wrongArgumentCount(String)
        case trailingInput
        case divisionByZero
        case invalidFactorial
    }

    private let characters: [Character]
    private let variables: [String: Double]
    private var index = 0

    init(expression: String, variables: [String: Double] = [:]) {
        self.characters = Array(expression)
        self.variables = variables
    }

    static func isKnownIdentifier(_ identifier: String) -> Bool {
        knownConstants.contains(identifier) || knownFunctions.contains(identifier)
    }

    mutating func parse() throws -> Double {
        let value = try parseExpression()
        skipSpaces()
        guard isAtEnd else { throw ParseError.trailingInput }
        return value
    }

    private mutating func parseExpression() throws -> Double {
        var value = try parseTerm()
        while true {
            skipSpaces()
            if consume("+") {
                value += try parseTerm()
            } else if consume("-") {
                value -= try parseTerm()
            } else {
                return value
            }
        }
    }

    private mutating func parseTerm() throws -> Double {
        var value = try parsePower()
        while true {
            skipSpaces()
            if consume("*") {
                value *= try parsePower()
            } else if consume("/") {
                let divisor = try parsePower()
                guard divisor != 0 else { throw ParseError.divisionByZero }
                value /= divisor
            } else if consume("%") {
                let divisor = try parsePower()
                guard divisor != 0 else { throw ParseError.divisionByZero }
                value = value.truncatingRemainder(dividingBy: divisor)
            } else if canStartImplicitFactor {
                value *= try parsePower()
            } else {
                return value
            }
        }
    }

    private mutating func parsePower() throws -> Double {
        var value = try parseUnary()
        skipSpaces()
        if consume("^") {
            value = pow(value, try parsePower())
        }
        return value
    }

    private mutating func parseUnary() throws -> Double {
        skipSpaces()
        if consume("+") { return try parseUnary() }
        if consume("-") { return -(try parseUnary()) }
        if consume("√") { return sqrt(try parseUnary()) }
        return try parsePostfix()
    }

    private mutating func parsePostfix() throws -> Double {
        var value = try parsePrimary()
        while true {
            skipSpaces()
            if consume("!") {
                value = try factorial(value)
            } else if consumePostfixPercent() {
                value /= 100
            } else {
                return value
            }
        }
    }

    private mutating func parsePrimary() throws -> Double {
        skipSpaces()

        if consume("(") {
            let value = try parseExpression()
            skipSpaces()
            guard consume(")") else { throw ParseError.expectedClosingParenthesis }
            return value
        }

        if currentIsLetter {
            let identifier = parseIdentifier().lowercased()
            skipSpaces()
            if consume("(") {
                let arguments = try parseArguments()
                return try evaluateFunction(identifier, arguments)
            }
            return try constant(identifier)
        }

        return try parseNumber()
    }

    private mutating func parseArguments() throws -> [Double] {
        skipSpaces()
        if consume(")") { return [] }

        var arguments: [Double] = []
        while true {
            arguments.append(try parseExpression())
            skipSpaces()
            if consume(")") { return arguments }
            guard consume(",") else { throw ParseError.expectedClosingParenthesis }
        }
    }

    private mutating func parseNumber() throws -> Double {
        skipSpaces()
        let start = index
        var hasDecimalPoint = false

        while isAtEnd == false {
            let character = characters[index]
            if character == ".", hasDecimalPoint == false {
                hasDecimalPoint = true
                index += 1
            } else if character.isNumber || character == "_" {
                index += 1
            } else {
                break
            }
        }

        if isAtEnd == false, characters[index].lowercased() == "e", index > start {
            let exponentStart = index
            index += 1
            if isAtEnd == false, characters[index] == "+" || characters[index] == "-" {
                index += 1
            }

            let digitsStart = index
            while isAtEnd == false, characters[index].isNumber {
                index += 1
            }

            if digitsStart == index {
                index = exponentStart
            }
        }

        guard index > start else { throw ParseError.expectedNumber }
        let number = String(characters[start..<index]).replacingOccurrences(of: "_", with: "")
        guard let value = Double(number) else { throw ParseError.expectedNumber }
        return value
    }

    private mutating func parseIdentifier() -> String {
        let start = index
        while isAtEnd == false, characters[index].isLetter || characters[index].isNumber || characters[index] == "_" {
            index += 1
        }
        return String(characters[start..<index])
    }

    private func constant(_ identifier: String) throws -> Double {
        if let value = variables[identifier] {
            return value
        }

        switch identifier {
        case "pi": return Double.pi
        case "tau": return 2 * Double.pi
        case "e": return M_E
        case "phi", "golden", "goldenratio": return 1.6180339887498948
        default: throw ParseError.unknownIdentifier(identifier)
        }
    }

    private func evaluateFunction(_ name: String, _ arguments: [Double]) throws -> Double {
        switch name {
        case "sin": return try unary(name, arguments, sin)
        case "cos": return try unary(name, arguments, cos)
        case "tan": return try unary(name, arguments, tan)
        case "sec": return try unary(name, arguments) { 1 / cos($0) }
        case "csc": return try unary(name, arguments) { 1 / sin($0) }
        case "cot": return try unary(name, arguments) { 1 / tan($0) }
        case "asin", "arcsin": return try unary(name, arguments, asin)
        case "acos", "arccos": return try unary(name, arguments, acos)
        case "atan", "arctan": return try unary(name, arguments, atan)
        case "asec", "arcsec": return try unary(name, arguments) { acos(1 / $0) }
        case "acsc", "arccsc": return try unary(name, arguments) { asin(1 / $0) }
        case "acot", "arccot": return try unary(name, arguments) { atan(1 / $0) }
        case "sinh": return try unary(name, arguments, sinh)
        case "cosh": return try unary(name, arguments, cosh)
        case "tanh": return try unary(name, arguments, tanh)
        case "asinh", "arcsinh": return try unary(name, arguments, asinh)
        case "acosh", "arccosh": return try unary(name, arguments, acosh)
        case "atanh", "arctanh": return try unary(name, arguments, atanh)
        case "sqrt": return try unary(name, arguments, sqrt)
        case "cbrt": return try unary(name, arguments, cbrt)
        case "abs": return try unary(name, arguments, abs)
        case "sign", "signum": return try unary(name, arguments) { $0.sign == .minus ? -1 : ($0 == 0 ? 0 : 1) }
        case "ln": return try unary(name, arguments, log)
        case "log": return try arguments.count == 1 ? log10(arguments[0]) : binary(name, arguments) { log($1) / log($0) }
        case "log2": return try unary(name, arguments, log2)
        case "log10": return try unary(name, arguments, log10)
        case "exp": return try unary(name, arguments, exp)
        case "floor": return try unary(name, arguments, floor)
        case "ceil", "ceiling": return try unary(name, arguments, ceil)
        case "round": return try unary(name, arguments) { $0.rounded() }
        case "trunc": return try unary(name, arguments) { $0.rounded(.towardZero) }
        case "deg": return try unary(name, arguments) { $0 * 180 / Double.pi }
        case "rad": return try unary(name, arguments) { $0 * Double.pi / 180 }
        case "pow": return try binary(name, arguments, pow)
        case "root": return try binary(name, arguments) { pow($1, 1 / $0) }
        case "hypot": return try binary(name, arguments, hypot)
        case "mod": return try binary(name, arguments) { $0.truncatingRemainder(dividingBy: $1) }
        case "clamp": return try ternary(name, arguments) { min(max($0, $1), $2) }
        case "atan2": return try binary(name, arguments, atan2)
        case "min": return try many(name, arguments, min)
        case "max": return try many(name, arguments, max)
        case "sum": return arguments.reduce(0, +)
        case "avg", "mean": return try average(name, arguments)
        default: throw ParseError.unknownIdentifier(name)
        }
    }

    private func unary(_ name: String, _ arguments: [Double], _ function: (Double) -> Double) throws -> Double {
        guard arguments.count == 1 else { throw ParseError.wrongArgumentCount(name) }
        return function(arguments[0])
    }

    private func binary(_ name: String, _ arguments: [Double], _ function: (Double, Double) -> Double) throws -> Double {
        guard arguments.count == 2 else { throw ParseError.wrongArgumentCount(name) }
        return function(arguments[0], arguments[1])
    }

    private func ternary(_ name: String, _ arguments: [Double], _ function: (Double, Double, Double) -> Double) throws -> Double {
        guard arguments.count == 3 else { throw ParseError.wrongArgumentCount(name) }
        return function(arguments[0], arguments[1], arguments[2])
    }

    private func many(_ name: String, _ arguments: [Double], _ function: (Double, Double) -> Double) throws -> Double {
        guard let first = arguments.first else { throw ParseError.expectedFunctionArguments }
        return arguments.dropFirst().reduce(first, function)
    }

    private func average(_ name: String, _ arguments: [Double]) throws -> Double {
        guard arguments.isEmpty == false else { throw ParseError.expectedFunctionArguments }
        return arguments.reduce(0, +) / Double(arguments.count)
    }

    private func factorial(_ value: Double) throws -> Double {
        guard value >= 0, value <= 170, value.rounded() == value else { throw ParseError.invalidFactorial }
        if value == 0 { return 1 }
        return (1...Int(value)).map(Double.init).reduce(1, *)
    }

    private mutating func consume(_ character: Character) -> Bool {
        guard isAtEnd == false, characters[index] == character else { return false }
        index += 1
        return true
    }

    private mutating func consumePostfixPercent() -> Bool {
        guard isAtEnd == false, characters[index] == "%" else { return false }
        let nextIndex = nextNonSpaceIndex(after: index)
        guard canStartFactor(at: nextIndex) == false else { return false }
        index += 1
        return true
    }

    private mutating func skipSpaces() {
        while isAtEnd == false, characters[index].isWhitespace {
            index += 1
        }
    }

    private func nextNonSpaceIndex(after position: Int) -> Int {
        var nextIndex = position + 1
        while nextIndex < characters.count, characters[nextIndex].isWhitespace {
            nextIndex += 1
        }
        return nextIndex
    }

    private func canStartFactor(at position: Int) -> Bool {
        guard position < characters.count else { return false }
        let character = characters[position]
        return character == "(" || character == "√" || character == "." || character.isNumber || character.isLetter
    }

    private var canStartImplicitFactor: Bool {
        canStartFactor(at: index)
    }

    private var currentIsLetter: Bool {
        isAtEnd == false && characters[index].isLetter
    }

    private var isAtEnd: Bool {
        index >= characters.count
    }
}

private let knownConstants: Set<String> = [
    "pi", "tau", "e", "phi", "golden", "goldenratio"
]

private let knownFunctions: Set<String> = [
    "sin", "cos", "tan", "sec", "csc", "cot",
    "asin", "arcsin", "acos", "arccos", "atan", "arctan", "atan2",
    "asec", "arcsec", "acsc", "arccsc", "acot", "arccot",
    "sinh", "cosh", "tanh", "asinh", "arcsinh", "acosh", "arccosh", "atanh", "arctanh",
    "sqrt", "cbrt", "root", "abs", "sign", "signum",
    "ln", "log", "log2", "log10", "exp",
    "floor", "ceil", "ceiling", "round", "trunc", "deg", "rad",
    "pow", "hypot", "mod", "clamp", "min", "max", "sum", "avg", "mean"
]
