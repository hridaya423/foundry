import AppKit
import SwiftUI
import XCTest
@testable import Foundry

/// Renders a SwiftUI view offscreen at a fixed 1x scale and compares it
/// against the checked-in reference in Tests/Fixtures/Snapshots.
///
/// Text antialiasing differs between a Mac's display and the CI VM, so the
/// references are CI renders and the comparison runs only where `CI` is set.
/// When a view changes, CI fails and uploads its renders as the `snapshots`
/// artifact; commit those PNGs as the new references.
///
/// - `FOUNDRY_QA_SNAPSHOT_DIR` writes the live capture to that directory.
/// - `FOUNDRY_SNAPSHOT_RECORD=1` writes the reference instead of asserting.
@MainActor
enum SnapshotHarness {
    static let referenceDirectory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures/Snapshots", isDirectory: true)

    /// Per-channel difference above this counts as a changed pixel.
    static let channelTolerance: UInt8 = 20
    /// Fraction of changed pixels still accepted — covers rasterisation
    /// differences between hosts without hiding layout regressions.
    static let maxMismatchFraction = 0.001

    static func render<V: View>(_ view: V, size: CGSize, appearance: NSAppearance.Name = .aqua) throws -> NSBitmapImageRep {
        let named = try XCTUnwrap(NSAppearance(named: appearance))
        let hostAppearance = NSApplication.shared.appearance
        NSApplication.shared.appearance = named
        defer { NSApplication.shared.appearance = hostAppearance }
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.appearance = named
        let host = NSHostingView(rootView: view.background(Color(nsColor: .windowBackgroundColor)))
        host.frame = window.contentLayoutRect
        window.contentView = host
        RunLoop.main.run(until: Date().addingTimeInterval(0.6))

        // Fixed 1x rep — host scale factor must not leak into comparisons.
        let rep = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width),
            pixelsHigh: Int(size.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ))
        named.performAsCurrentDrawingAppearance { host.cacheDisplay(in: host.bounds, to: rep) }
        return rep
    }

    static func assertMatchesReference(_ rep: NSBitmapImageRep, name: String, file: StaticString = #filePath, line: UInt = #line) throws {
        let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
        if let qaDir = ProcessInfo.processInfo.environment["FOUNDRY_QA_SNAPSHOT_DIR"] {
            try png.write(to: URL(fileURLWithPath: qaDir).appendingPathComponent("\(name).png"))
        }
        let referenceURL = referenceDirectory.appendingPathComponent("\(name).png")
        if ProcessInfo.processInfo.environment["FOUNDRY_SNAPSHOT_RECORD"] == "1" {
            try FileManager.default.createDirectory(at: referenceDirectory, withIntermediateDirectories: true)
            try png.write(to: referenceURL, options: .atomic)
            return
        }
        guard ProcessInfo.processInfo.environment["CI"] != nil else {
            throw XCTSkip("snapshot references are CI renders; set CI=1 to compare on this host")
        }
        guard let referenceData = try? Data(contentsOf: referenceURL),
              let reference = NSBitmapImageRep(data: referenceData) else {
            XCTFail("No snapshot reference at Tests/Fixtures/Snapshots/\(name).png — record it with FOUNDRY_SNAPSHOT_RECORD=1", file: file, line: line)
            return
        }
        XCTAssertEqual(rep.pixelsWide, reference.pixelsWide, "snapshot width changed", file: file, line: line)
        XCTAssertEqual(rep.pixelsHigh, reference.pixelsHigh, "snapshot height changed", file: file, line: line)
        guard rep.pixelsWide == reference.pixelsWide, rep.pixelsHigh == reference.pixelsHigh else { return }

        var mismatched = 0
        for y in 0..<rep.pixelsHigh {
            for x in 0..<rep.pixelsWide {
                guard let a = rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
                      let b = reference.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                let delta = max(
                    abs(a.redComponent - b.redComponent),
                    abs(a.greenComponent - b.greenComponent),
                    abs(a.blueComponent - b.blueComponent)
                )
                if delta > Double(channelTolerance) / 255 { mismatched += 1 }
            }
        }
        let fraction = Double(mismatched) / Double(rep.pixelsWide * rep.pixelsHigh)
        XCTAssertLessThanOrEqual(
            fraction, maxMismatchFraction,
            "snapshot \(name) diverged: \(String(format: "%.2f", fraction * 100))% of pixels differ",
            file: file, line: line
        )
    }
}
