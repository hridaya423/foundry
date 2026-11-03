import AppKit
import SwiftUI
import XCTest
@testable import Foundry

final class BrandTokensTests: XCTestCase {
    private func tokens() throws -> [String: String] {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("docs/brand/tokens.json")
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        return try XCTUnwrap(json?["color"] as? [String: String])
    }

    private func hex(_ color: Color) throws -> String {
        let rgb = try XCTUnwrap(NSColor(color).usingColorSpace(.sRGB))
        let channel = { (value: CGFloat) in String(format: "%02x", Int((value * 255).rounded())) }
        return "#" + channel(rgb.redComponent) + channel(rgb.greenComponent) + channel(rgb.blueComponent)
    }

    func testAppBrandColorsMatchTheWebsiteTokens() throws {
        let file = try tokens()
        let pairs: [(String, Color)] = [
            ("ink", FoundryTheme.Brand.ink),
            ("text", FoundryTheme.Brand.text),
            ("muted", FoundryTheme.Brand.muted),
            ("line", FoundryTheme.Brand.line),
            ("orange", FoundryTheme.Brand.accent),
        ]
        for (name, color) in pairs {
            XCTAssertEqual(try hex(color), file[name], name)
        }
    }
}
