import AppKit
import SwiftUI
import XCTest
@testable import Foundry

@MainActor
final class MaterialFallbackTests: XCTestCase {
    private func luminance(of fill: Color, appearance: NSAppearance.Name) throws -> CGFloat {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 40, height: 40), styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: appearance)
        let host = NSHostingView(rootView: Rectangle().fill(fill).background(Color(nsColor: .windowBackgroundColor)))
        host.frame = NSRect(x: 0, y: 0, width: 40, height: 40)
        window.contentView = host
        let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        let color = try XCTUnwrap(rep.colorAt(x: 20, y: 20)?.usingColorSpace(.sRGB))
        return 0.2126 * color.redComponent + 0.7152 * color.greenComponent + 0.0722 * color.blueComponent
    }

    func testFloatingOverlayFallbackIsLightInLightMode() throws {
        XCTAssertGreaterThan(try luminance(of: FoundryMaterialRole.floatingOverlay.fallbackFill, appearance: .aqua), 0.85)
    }

    func testFloatingOverlayFallbackIsDarkInDarkMode() throws {
        XCTAssertLessThan(try luminance(of: FoundryMaterialRole.floatingOverlay.fallbackFill, appearance: .darkAqua), 0.25)
    }
}
