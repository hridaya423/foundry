import AppKit
import SwiftUI
import XCTest
import FoundryDomain
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

    /// 5.2 row anatomy: 40pt single-line rows, 24pt icons, inline subtitle,
    /// alias badge + bordered keycap + kind label, fill-only selection,
    /// Title Case 11pt semibold section headers.
    func testRenderRowAnatomy() throws {
        guard let dir = ProcessInfo.processInfo.environment["FOUNDRY_QA_SNAPSHOT_DIR"] else { throw XCTSkip("snapshot dir not set") }

        func makeResult(_ id: String, _ title: String, subtitle: String? = nil, icon: String = "app") -> CommandResult {
            CommandResult(
                id: id,
                title: title,
                subtitle: subtitle,
                icon: CommandIcon(fallback: String(title.prefix(2)).uppercased(), systemName: icon),
                payload: .command,
                primaryAction: CommandAction(id: "\(id).open", title: "Open", behavior: OpenHomeAction()),
                secondaryActions: []
            )
        }

        let rows = VStack(alignment: .leading, spacing: 0) {
            HomeSectionHeader(title: "Recent")
            ResultRow(result: makeResult("r1", "Safari", icon: "safari"), isSelected: false, kindLabel: "App")
            FoundrySectionHeader(title: "Suggestions", count: "4 items")
            ResultRow(result: makeResult("r2", "Xcode", subtitle: "Developer Tools", icon: "hammer"),
                      isSelected: true, kindLabel: "App")
            ResultRow(result: makeResult("r3", "Empty Trash", subtitle: "System", icon: "trash"),
                      isSelected: false, alias: "trash", hotkey: "⌃⌥⇧T", kindLabel: "Command")
            ResultRow(result: makeResult("r4", "Terminal", subtitle: "Utilities",
                                        icon: "chevron.left.forwardslash.chevron.right"),
                      isSelected: false, isRunning: true, kindLabel: "App")
            ResultRow(result: makeResult("r5", "A Very Long Result Title That Keeps Going",
                                        subtitle: "and an equally long subtitle that must truncate on one line",
                                        icon: "doc"),
                      isSelected: false, kindLabel: "File")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(width: 736)

        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 736, height: 280), styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
            window.appearance = NSAppearance(named: appearance)
            let host = NSHostingView(rootView: rows.background(Color(nsColor: .windowBackgroundColor)))
            host.frame = window.contentLayoutRect
            window.contentView = host
            RunLoop.main.run(until: Date().addingTimeInterval(0.6))
            let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: rep)
            try XCTUnwrap(rep.representation(using: .png, properties: [:]))
                .write(to: URL(fileURLWithPath: dir).appendingPathComponent("rows-\(appearance == .aqua ? "light" : "dark").png"))
        }
    }

    /// 5.6 material fix: the Reduce-Transparency backdrop paints
    /// `windowBackgroundColor` with no black wash — the light panel must stay
    /// light (the old wash pushed it to ≈0.65 luminance) and the dark panel
    /// must stay dark. Samples the bottom edge, past the brand gradient.
    func testOpaqueBackdropPaintsSemanticWindowBackground() throws {
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 160), styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
            window.appearance = try XCTUnwrap(NSAppearance(named: appearance))
            let host = NSHostingView(rootView: FoundryBackdrop(isOpaque: true).frame(width: 300, height: 160))
            host.frame = window.contentLayoutRect
            window.contentView = host
            RunLoop.main.run(until: Date().addingTimeInterval(0.6))

            let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: rep)
            let pixel = try XCTUnwrap(rep.colorAt(x: 150, y: 20)?.usingColorSpace(.deviceRGB))
            let luminance = 0.2126 * pixel.redComponent + 0.7152 * pixel.greenComponent + 0.0722 * pixel.blueComponent

            if appearance == .aqua {
                XCTAssertGreaterThan(luminance, 0.80, "light-mode opaque backdrop must be windowBackgroundColor, not a dark wash")
            } else {
                XCTAssertLessThan(luminance, 0.45, "dark-mode opaque backdrop must stay dark")
            }

            if let dir = ProcessInfo.processInfo.environment["FOUNDRY_QA_SNAPSHOT_DIR"] {
                try XCTUnwrap(rep.representation(using: .png, properties: [:]))
                    .write(to: URL(fileURLWithPath: dir).appendingPathComponent("backdrop-opaque-\(appearance == .aqua ? "light" : "dark").png"))
            }
        }
    }

    func testRenderOverlaysAndNotices() throws {
        guard let dir = ProcessInfo.processInfo.environment["FOUNDRY_QA_SNAPSHOT_DIR"] else { throw XCTSkip("snapshot dir not set") }
        let spec = PanelPromptSpec.confirmation(title: "Move “Report.pdf” to the Trash?", message: "You can put it back from the Trash.",
            confirmLabel: "Move to Trash", isDestructive: true)
        let notice = InlineNotice(level: .error,
            text: "The AI provider rejected the sign-in. Check the API key or account in Settings › AI.")
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 260), styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
            window.appearance = NSAppearance(named: appearance)
            let view = VStack(spacing: 24) {
                FoundryGlassSurface(role: .floatingOverlay, shape: RoundedRectangle(cornerRadius: 16, style: .continuous)) {
                    PanelPromptOverlay(spec: spec) { _ in }
                }
                .frame(width: 380)
                notice.frame(width: 460)
            }
            .padding(24)
            .frame(width: 520, height: 260)
            .background(Color(nsColor: .windowBackgroundColor))
            let host = NSHostingView(rootView: view)
            host.frame = window.contentLayoutRect
            window.contentView = host
            RunLoop.main.run(until: Date().addingTimeInterval(0.4))
            let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: rep)
            let name = "overlay-\(appearance == .aqua ? "light" : "dark").png"
            try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: dir).appendingPathComponent(name))
        }
    }

    func testRenderActionsOverlay() throws {
        guard let dir = ProcessInfo.processInfo.environment["FOUNDRY_QA_SNAPSHOT_DIR"] else { throw XCTSkip("snapshot dir not set") }
        let diagnostics = DiagnosticsService()
        let config = ConfigService(diagnostics: diagnostics, url: FileManager.default.temporaryDirectory.appendingPathComponent("snap-\(UUID()).json"))
        let registry = CommandRegistry(providers: [], usageRanking: UsageRankingStore(diagnostics: diagnostics), diagnostics: diagnostics, configService: config)
        let state = CommandPanelState(registry: registry, actionRunner: ActionRunner(diagnostics: diagnostics), diagnostics: diagnostics, config: config)
        let file = CommandResult(id: "file.a", title: "Report.pdf", subtitle: "~/Documents", icon: CommandIcon(fallback: "F", systemName: "doc"),
            payload: .file(URL(fileURLWithPath: "/tmp/Report.pdf")),
            primaryAction: CommandAction(id: "file.open", title: "Open", behavior: OpenHomeAction()),
            secondaryActions: [
                CommandAction(id: "file.trash", title: "Move to Trash", behavior: MoveToTrashAction(path: "/tmp/Report.pdf")),
                CommandAction(id: "file.copy", title: "Copy Path", behavior: CopyToClipboardAction("/tmp/Report.pdf")),
            ])
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        state.session.results = [file]
        state.session.selectedResultID = file.id
        state.session.toggleActions()
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 736, height: 474), styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
            window.appearance = NSAppearance(named: appearance)
            let host = NSHostingView(rootView: CommandPanelView(state: state) {}.background(Color(nsColor: .windowBackgroundColor)))
            host.frame = window.contentLayoutRect
            window.contentView = host
            RunLoop.main.run(until: Date().addingTimeInterval(0.6))
            let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: rep)
            let name = "actions-\(appearance == .aqua ? "light" : "dark").png"
            try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: dir).appendingPathComponent(name))
        }
        state.shutdown()
    }

}
