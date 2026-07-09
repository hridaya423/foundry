import AppKit
import Foundation

@MainActor
final class DeveloperToolsState: ObservableObject {
    enum Tool: String, CaseIterable, Identifiable {
        case base = "Base Conversion"
        case bitwise = "Bit Operations"

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

    init() {
        refreshBase()
        refreshBitwise()
    }

    func reset() {
        selectedTool = .base
        baseInput = "255"
        bitOperation = .and
        bitLeftInput = "5"
        bitRightInput = "3"
        bitWidthInput = "8"
        refreshBase()
        refreshBitwise()
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
}
