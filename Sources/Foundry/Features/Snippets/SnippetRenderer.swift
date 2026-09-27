import AppKit
@preconcurrency import ApplicationServices
import Foundation

enum SnippetRenderer {
    static func argumentNames(in content: String) -> [String] {
        var seen = Set<String>()
        var names: [String] = []
        var index = content.startIndex
        while let open = content[index...].firstIndex(of: "{"), let close = content[open...].firstIndex(of: "}") {
            let token = String(content[open...close])
            if let name = argumentName(in: token), seen.insert(name).inserted { names.append(name) }
            index = content.index(after: close)
        }
        return names
    }

    private static func argumentName(in token: String) -> String? {
        guard token.hasPrefix("{argument "), token.hasSuffix("}") else { return nil }
        let body = token.dropFirst("{argument ".count).dropLast()
        guard body.hasPrefix("name=\""), body.hasSuffix("\"") else { return nil }
        let name = body.dropFirst("name=\"".count).dropLast()
        return name.isEmpty ? nil : String(name)
    }

    static func render(_ content: String, context: SnippetRenderContext = .current(), arguments: [String: String] = [:]) -> RenderedSnippet {
        let formatter = DateFormatter()
        formatter.locale = context.locale
        formatter.calendar = context.calendar
        formatter.timeZone = context.calendar.timeZone
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        let date = formatter.string(from: context.now)
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        let time = formatter.string(from: context.now)
            .replacingOccurrences(of: "\u{202F}", with: " ")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
        let replacements = ["{date}": date, "{time}": time, "{clipboard}": context.clipboard, "{selection}": context.selection]
        var result = ""
        var cursorPosition: Int?
        var index = content.startIndex
        while index < content.endIndex {
            guard let open = content[index...].firstIndex(of: "{") else {
                result.append(contentsOf: content[index...])
                break
            }
            result.append(contentsOf: content[index..<open])
            guard let close = content[open...].firstIndex(of: "}") else {
                result.append(contentsOf: content[open...])
                break
            }

            let end = content.index(after: close)
            let token = String(content[open..<end])
            if token == "{cursor}" {
                if cursorPosition == nil { cursorPosition = result.utf16.count }
            } else if token.hasPrefix("{date:"), token.hasSuffix("}") {
                formatter.dateFormat = String(token.dropFirst("{date:".count).dropLast())
                let formatted = formatter.string(from: context.now)
                result.append(contentsOf: formatted.isEmpty ? token : formatted)
            } else if let name = Self.argumentName(in: token) {
                result.append(contentsOf: arguments[name] ?? token)
            } else {
                result.append(contentsOf: replacements[token] ?? token)
            }
            index = end
        }
        let cursorOffset = cursorPosition.map { result.utf16.count - $0 + 1 } ?? 0
        return RenderedSnippet(text: result, cursorOffsetFromEnd: cursorOffset)
    }
}

struct RenderedSnippet: Equatable, Sendable { let text: String; let cursorOffsetFromEnd: Int }
struct SnippetRenderContext: Sendable {
    let now: Date; let locale: Locale; let calendar: Calendar; let clipboard: String; var selection: String = ""
    static func current() -> Self {
        Self(now: Date(), locale: .current, calendar: .current,
             clipboard: NSPasteboard.general.string(forType: .string) ?? "",
             selection: FrontAppSelection.read())
    }
}

enum FrontAppSelection {
    static func read() -> String {
        guard AXIsProcessTrusted() else { return "" }
        var focused: AnyObject?
        guard AXUIElementCopyAttributeValue(AXUIElementCreateSystemWide(), "AXFocusedUIElement" as CFString, &focused) == .success,
              let element = focused else { return "" }
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element as! AXUIElement, "AXSelectedText" as CFString, &value) == .success else { return "" }
        return value as? String ?? ""
    }
}
