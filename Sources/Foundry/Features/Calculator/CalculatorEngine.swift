import Foundation
import os

struct CalculatorEvaluation {
    let expression: String
    let result: String
    let copyValue: String
    var note: String? = nil

    var subtitle: String { [expression, note].compactMap { $0 }.joined(separator: " · ") }
}

struct CurrencyRequest {
    let amount: Double
    let base: String
    let quote: String?
}

struct FrankfurterRate: Decodable {
    let quote: String
    let rate: Double
    let date: String?
}

final class CalculatorHistoryStore: Sendable {
    static let shared = CalculatorHistoryStore()

    struct Entry: Equatable {
        let expression: String
        let result: String
    }

    private let localState: LocalStateStore
    private let limit = 10

    init(localState: LocalStateStore = .shared) { self.localState = localState }

    var entries: [Entry] {
        localState.get(\.calculatorHistory).compactMap { pair in
            guard pair.count == 2 else { return nil }
            return Entry(expression: pair[0], result: pair[1])
        }
    }

    func record(expression: String, result: String) {
        guard result.isEmpty == false else { return }
        localState.update { state in
            let entry = [expression, result]
            var raw = state.calculatorHistory.filter { $0 != entry }
            raw.insert(entry, at: 0)
            state.calculatorHistory = Array(raw.prefix(limit))
        }
    }
}

final class CurrencyRateCache: Sendable {
    static let shared = CurrencyRateCache()

    private struct Entry {
        let createdAt: Date
        let rates: [FrankfurterRate]
    }

    private let entries = OSAllocatedUnfairLock<[String: Entry]>(initialState: [:])
    private let lifetime: TimeInterval = 5 * 60

    func value(for key: String) -> [FrankfurterRate]? {
        entries.withLock { entries in
            guard let entry = entries[key] else { return nil }
            guard Date().timeIntervalSince(entry.createdAt) < lifetime else {
                entries[key] = nil
                return nil
            }
            return entry.rates
        }
    }

    func store(_ rates: [FrankfurterRate], for key: String) {
        entries.withLock { $0[key] = Entry(createdAt: Date(), rates: rates) }
    }
}

struct CalculatorParser {
    enum ParseError: Error {
        case expectedNumber
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
    private var lastWasPercent = false
    private var termIsPercent = false

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
                let term = try parseTerm()
                value += termIsPercent ? value * term : term
            } else if consume("-") {
                let term = try parseTerm()
                value -= termIsPercent ? value * term : term
            } else {
                return value
            }
        }
    }

    private mutating func parseTerm() throws -> Double {
        var value = try parseUnary()
        var isPercent = lastWasPercent
        while true {
            skipSpaces()
            if consume("*") {
                value *= try parseUnary()
            } else if consume("/") {
                let divisor = try parseUnary()
                guard divisor != 0 else { throw ParseError.divisionByZero }
                value /= divisor
            } else if consume("%") {
                let divisor = try parseUnary()
                guard divisor != 0 else { throw ParseError.divisionByZero }
                value = value.truncatingRemainder(dividingBy: divisor)
            } else if canStartImplicitFactor {
                value *= try parseUnary()
            } else {
                termIsPercent = isPercent
                return value
            }
            isPercent = false
        }
    }

    private mutating func parseUnary() throws -> Double {
        skipSpaces()
        if consume("+") { return try parseUnary() }
        if consume("-") { return -(try parseUnary()) }
        return try parsePower()
    }

    private mutating func parsePower() throws -> Double {
        var value = try parseRadical()
        skipSpaces()
        if consume("^") {
            value = pow(value, try parseUnary())
            lastWasPercent = false
        }
        return value
    }

    private mutating func parseRadical() throws -> Double {
        skipSpaces()
        if consume("√") {
            let value = sqrt(try parseRadical())
            lastWasPercent = false
            return value
        }
        return try parsePostfix()
    }

    private mutating func parsePostfix() throws -> Double {
        var value = try parsePrimary()
        lastWasPercent = false
        while true {
            skipSpaces()
            if consume("!") {
                value = try factorial(value)
                lastWasPercent = false
            } else if consumePostfixPercent() {
                value /= 100
                lastWasPercent = true
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
        case "log": return try arguments.count == 1 ? log10(arguments[0]) : binary(name, arguments) { log($0) / log($1) }
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
        case "root": return try binary(name, arguments) { pow($0, 1 / $1) }
        case "hypot": return try binary(name, arguments, hypot)
        case "mod": return try binary(name, arguments) { $0.truncatingRemainder(dividingBy: $1) }
        case "clamp": return try ternary(name, arguments) { min(max($0, $1), $2) }
        case "atan2": return try binary(name, arguments, atan2)
        case "min": return try many(arguments, min)
        case "max": return try many(arguments, max)
        case "sum": return arguments.reduce(0, +)
        case "avg", "mean": return try average(arguments)
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

    private func many(_ arguments: [Double], _ function: (Double, Double) -> Double) throws -> Double {
        guard let first = arguments.first else { throw ParseError.expectedFunctionArguments }
        return arguments.dropFirst().reduce(first, function)
    }

    private func average(_ arguments: [Double]) throws -> Double {
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
