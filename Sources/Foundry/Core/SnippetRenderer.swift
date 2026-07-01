import AppKit
import Foundation

enum SnippetRenderer {
    static func render(_ content: String) -> String {
        var value = content
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        value = value.replacingOccurrences(of: "{date}", with: formatter.string(from: Date()))
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        value = value.replacingOccurrences(of: "{time}", with: formatter.string(from: Date()))
        value = value.replacingOccurrences(of: "{clipboard}", with: NSPasteboard.general.string(forType: .string) ?? "")
        return value.replacingOccurrences(of: "{cursor}", with: "")
    }
}
