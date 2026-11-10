import AppKit
import XCTest

final class SymbolNameTests: XCTestCase {
    func testEverySymbolNameInTheSourcesExists() throws {
        let sources = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources")
        let pattern = try NSRegularExpression(pattern:
            #"(?:systemName|systemImage|systemIcon|symbol|icon)\s*:\s*"([a-z0-9]+(?:\.[a-z0-9]+)+)"|var (?:icon|symbol)[^=\n]*\{\s*"([a-z0-9.]+)"\s*\}"#)
        var missing: [String] = []
        var checked = 0
        for case let file as URL in FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil)! where file.pathExtension == "swift" {
            let text = try String(contentsOf: file, encoding: .utf8)
            for match in pattern.matches(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text)) {
                guard let range = Range(match.range(at: 1), in: text) ?? Range(match.range(at: 2), in: text) else { continue }
                checked += 1
                if NSImage(systemSymbolName: String(text[range]), accessibilityDescription: nil) == nil {
                    missing.append("\(text[range]) in \(file.lastPathComponent)")
                }
            }
        }
        XCTAssertGreaterThan(checked, 150)
        XCTAssertEqual(missing, [])
    }
}
