import Foundation

final class CalculatorProvider: CommandProvider {
    let id = "foundry.calculator"

    func results(matching query: String) async -> [CommandResult] {
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
}

private struct CalculatorEvaluation {
    let expression: String
    let result: String
    let copyValue: String
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
