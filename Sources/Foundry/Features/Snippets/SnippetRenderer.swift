import AppKit
import Foundation

enum SnippetRenderer {
    static func render(_ content: String, context: SnippetRenderContext = .current()) -> RenderedSnippet {
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
        let replacements = ["{date}": date, "{time}": time, "{clipboard}": context.clipboard]
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
    let now: Date; let locale: Locale; let calendar: Calendar; let clipboard: String
    static func current() -> Self { Self(now: Date(), locale: .current, calendar: .current, clipboard: NSPasteboard.general.string(forType: .string) ?? "") }
}
