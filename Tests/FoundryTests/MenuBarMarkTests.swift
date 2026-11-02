import AppKit
import XCTest
@testable import Foundry

@MainActor
final class MenuBarMarkTests: XCTestCase {
    private func alphaGrid(scale: Int) throws -> [[UInt8]] {
        let image = MarkTiles.menuBarImage
        let side = 16 * scale
        let rep = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8,
                                                 samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                                 bytesPerRow: 0, bitsPerPixel: 0))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(x: 0, y: 0, width: side, height: side))
        NSGraphicsContext.restoreGraphicsState()
        return (0..<side).map { y in (0..<side).map { x in UInt8((rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) * 255) } }
    }

    func testMenuBarMarkIsASixteenPointTemplate() {
        XCTAssertTrue(MarkTiles.menuBarImage.isTemplate)
        XCTAssertEqual(MarkTiles.menuBarImage.size, NSSize(width: 16, height: 16))
    }

    func testMenuBarMarkLandsOnWholePixelsAtOneX() throws {
        let grid = try alphaGrid(scale: 1)
        let partial = grid.joined().filter { $0 > 20 && $0 < 235 }.count
        XCTAssertEqual(partial, 0, "anti-aliased pixels at 1x")
        XCTAssertEqual(grid[0][0], 0, "corner padding is transparent")
        XCTAssertGreaterThan(grid[2][2], 235, "left half is solid")
        XCTAssertEqual(grid[2][7], 0, "the sprue channel is open")
        XCTAssertGreaterThan(grid[8][7], 235, "the cast is drawn")
        XCTAssertEqual(grid[9][12], 0, "the right half is split")
    }
}
