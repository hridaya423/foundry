import AppKit
import SwiftUI
import XCTest
import FoundryServices
@testable import Foundry

@MainActor
final class PreviewSnapshotTests: XCTestCase {
    func testRenderPreviews() throws {
        guard let dir = ProcessInfo.processInfo.environment["FOUNDRY_QA_SNAPSHOT_DIR"] else { throw XCTSkip("snapshot dir not set") }
        let archive = FileManager.default.temporaryDirectory.appendingPathComponent("clip-snap-\(UUID()).json")
        let persistence = ClipboardHistoryPersistence(url: archive)
        try persistence.save([
            ClipboardHistoryItem(payload: .text("func greet(_ name: String) -> String {\n    \"Hello, \\(name)!\"\n}\n\nprint(greet(\"Foundry\"))"), sourceBundleIdentifier: "com.apple.dt.Xcode"),
            ClipboardHistoryItem(payload: .files([URL(fileURLWithPath: #filePath)]), createdAt: Date().addingTimeInterval(-600), sourceBundleIdentifier: "com.apple.finder"),
            ClipboardHistoryItem(payload: .text("https://raycast.com/manual"), createdAt: Date().addingTimeInterval(-7_200), isPinned: true)
        ])
        let diagnostics = DiagnosticsService()
        let config = ConfigService(diagnostics: diagnostics, url: FileManager.default.temporaryDirectory.appendingPathComponent("snap-\(UUID()).json"))
        let clipboard = ClipboardHistoryState(pasteboard: TestClipboardPasteboard(), persistence: persistence, configuration: config.current.clipboard)
        let shelf = FileShelfState()

        func render<V: View>(_ view: V, name: String, appearance: NSAppearance.Name) throws {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 736, height: 420), styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
            window.appearance = NSAppearance(named: appearance)
            let host = NSHostingView(rootView: view.background(Color(nsColor: .windowBackgroundColor)))
            host.frame = window.contentLayoutRect
            window.contentView = host
            RunLoop.main.run(until: Date().addingTimeInterval(0.6))
            let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: rep)
            try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name)-\(appearance == .aqua ? "light" : "dark").png"))
        }

        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            clipboard.select(id: clipboard.visibleItems[0].id)
            try render(ClipboardHistoryView(state: clipboard, fileShelf: shelf), name: "clipboard-text", appearance: appearance)
            clipboard.select(id: clipboard.visibleItems[1].id)
            try render(ClipboardHistoryView(state: clipboard, fileShelf: shelf), name: "clipboard-file", appearance: appearance)
        }
    }
}
