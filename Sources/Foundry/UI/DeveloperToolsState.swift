import AppKit
import Foundation

@MainActor
final class DeveloperToolsState: ObservableObject {
    enum Tool: String, CaseIterable, Identifiable {
        case base = "Base Conversion"
        case bitwise = "Bit Operations"
        case base64 = "Base64"
        case json = "Format JSON"
        case textCase = "Change Case"
        case timestamp = "Unix Timestamp"
        case wordCount = "Word Count"

        var id: String { rawValue }

        init?(commandID: String) {
            switch commandID {
            case "base64": self = .base64
            case "json": self = .json
            case "case": self = .textCase
            case "timestamp": self = .timestamp
            case "wordCount": self = .wordCount
            default: return nil
            }
        }
    }

    enum Base64Operation: String, CaseIterable, Identifiable {
        case encode = "Encode"
        case decode = "Decode"

        var id: String { rawValue }
    }

    enum BitOperation: String, CaseIterable, Identifiable {
        case and = "AND"
        case or = "OR"
        case xor = "XOR"
        case not = "NOT"
        case shiftLeft = "<<"
        case shiftRight = ">>"

        var id: String { rawValue }
    }

    struct OutputRow: Identifiable {
        let label: String
        let value: String

        var id: String { label }
    }

    @Published var selectedTool: Tool = .base
    @Published var baseInput = "255" {
        didSet { refreshBase() }
    }
    @Published private(set) var baseRows: [OutputRow] = []
    @Published private(set) var baseError: String?

    @Published var bitOperation: BitOperation = .and {
        didSet { refreshBitwise() }
    }
    @Published var bitLeftInput = "5" {
        didSet { refreshBitwise() }
    }
    @Published var bitRightInput = "3" {
        didSet { refreshBitwise() }
    }
    @Published var bitWidthInput = "8" {
        didSet { refreshBitwise() }
    }
    @Published private(set) var bitExpression = ""
    @Published private(set) var bitRows: [OutputRow] = []
    @Published private(set) var bitError: String?

    @Published var base64Operation: Base64Operation = .encode {
        didSet { refreshBase64() }
    }
    @Published var base64Input = "" {
        didSet { refreshBase64() }
    }
    @Published private(set) var base64Output = ""
    @Published private(set) var base64Error: String?

    @Published var jsonInput = "" {
        didSet { refreshJSON() }
    }
    @Published private(set) var jsonOutput = ""
    @Published private(set) var jsonError: String?

    @Published var caseInput = "" {
        didSet { refreshCase() }
    }
    @Published private(set) var caseRows: [OutputRow] = []

    @Published var timestampInput = "" {
        didSet { refreshTimestamp() }
    }
    @Published private(set) var timestampRows: [OutputRow] = []

    @Published var wordCountInput = "" {
        didSet { refreshWordCount() }
    }
    @Published private(set) var wordCountRows: [OutputRow] = []

    init() {
        refreshBase()
        refreshBitwise()
        refreshBase64()
        refreshJSON()
        refreshCase()
        refreshTimestamp()
        refreshWordCount()
    }

    func reset() {
        selectedTool = .base
        baseInput = "255"
        bitOperation = .and
        bitLeftInput = "5"
        bitRightInput = "3"
        bitWidthInput = "8"
        base64Operation = .encode
        base64Input = ""
        jsonInput = ""
        caseInput = ""
        timestampInput = ""
        wordCountInput = ""
        refreshBase()
        refreshBitwise()
        refreshBase64()
        refreshJSON()
        refreshCase()
        refreshTimestamp()
        refreshWordCount()
    }

    func copy(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }

    private func refreshBase() {
        let trimmed = baseInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            baseRows = []
            baseError = nil
            return
        }
        guard let rows = DeveloperToolsEngine.baseConversion(from: trimmed) else {
            baseRows = []
            baseError = "Enter a decimal value, prefixed value like 0xff, or radix notation like 16 ff."
            return
        }
        baseRows = rows.map { OutputRow(label: $0.label, value: $0.value) }
        baseError = nil
    }

    private func refreshBitwise() {
        guard let lhs = DeveloperToolsEngine.parseUnsignedInteger(bitLeftInput) else {
            bitExpression = ""
            bitRows = []
            bitError = "Enter a valid left value like 5, 0xff, or 0b1010."
            return
        }

        let result: UInt64
        switch bitOperation {
        case .and:
            guard let rhs = DeveloperToolsEngine.parseUnsignedInteger(bitRightInput) else {
                invalidateBitwise("Enter a valid right value.")
                return
            }
            bitExpression = "\(lhs) AND \(rhs)"
            result = lhs & rhs
        case .or:
            guard let rhs = DeveloperToolsEngine.parseUnsignedInteger(bitRightInput) else {
                invalidateBitwise("Enter a valid right value.")
                return
            }
            bitExpression = "\(lhs) OR \(rhs)"
            result = lhs | rhs
        case .xor:
            guard let rhs = DeveloperToolsEngine.parseUnsignedInteger(bitRightInput) else {
                invalidateBitwise("Enter a valid right value.")
                return
            }
            bitExpression = "\(lhs) XOR \(rhs)"
            result = lhs ^ rhs
        case .shiftLeft:
            guard let rhs = DeveloperToolsEngine.parseUnsignedInteger(bitRightInput), rhs < 64 else {
                invalidateBitwise("Shift amount must be between 0 and 63.")
                return
            }
            bitExpression = "\(lhs) << \(rhs)"
            result = lhs << rhs
        case .shiftRight:
            guard let rhs = DeveloperToolsEngine.parseUnsignedInteger(bitRightInput), rhs < 64 else {
                invalidateBitwise("Shift amount must be between 0 and 63.")
                return
            }
            bitExpression = "\(lhs) >> \(rhs)"
            result = lhs >> rhs
        case .not:
            let width = Int(bitWidthInput) ?? 0
            guard (1...64).contains(width) else {
                invalidateBitwise("Mask width must be between 1 and 64.")
                return
            }
            let mask = width == 64 ? UInt64.max : (UInt64(1) << UInt64(width)) - 1
            bitExpression = "NOT \(lhs) over \(width)-bit mask"
            result = (~lhs) & mask
        }

        bitRows = DeveloperToolsEngine.radixConversions(for: result).map { OutputRow(label: $0.label, value: $0.value) }
        bitError = nil
    }

    private func invalidateBitwise(_ message: String) {
        bitExpression = ""
        bitRows = []
        bitError = message
    }

    private func refreshBase64() {
        let input = base64Input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard input.isEmpty == false else {
            base64Output = ""
            base64Error = nil
            return
        }
        let output = base64Operation == .encode
            ? DeveloperToolsEngine.base64Encode(input)
            : DeveloperToolsEngine.base64Decode(input)
        guard let output else {
            base64Output = ""
            base64Error = "Enter valid Base64 text to decode."
            return
        }
        base64Output = output
        base64Error = nil
    }

    private func refreshJSON() {
        let input = jsonInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard input.isEmpty == false else {
            jsonOutput = ""
            jsonError = nil
            return
        }
        guard let output = DeveloperToolsEngine.formatJSON(input) else {
            jsonOutput = ""
            jsonError = "Enter valid JSON."
            return
        }
        jsonOutput = output
        jsonError = nil
    }

    private func refreshCase() {
        let input = caseInput.trimmingCharacters(in: .whitespacesAndNewlines)
        caseRows = input.isEmpty ? [] : DeveloperToolsEngine.caseVariants(for: input).map {
            OutputRow(label: $0.style, value: $0.value)
        }
    }

    private func refreshTimestamp() {
        let input = timestampInput.trimmingCharacters(in: .whitespacesAndNewlines)
        timestampRows = input.isEmpty ? [] : DeveloperToolsEngine.timestampConversions(for: input).map {
            OutputRow(label: $0.label, value: $0.value)
        }
    }

    private func refreshWordCount() {
        guard wordCountInput.isEmpty == false else {
            wordCountRows = []
            return
        }
        let stats = DeveloperToolsEngine.wordCount(wordCountInput)
        wordCountRows = [
            OutputRow(label: "Words", value: String(stats.words)),
            OutputRow(label: "Characters", value: String(stats.characters)),
            OutputRow(label: "Lines", value: String(stats.lines)),
            OutputRow(label: "Paragraphs", value: String(stats.paragraphs))
        ]
    }
}
