import AppKit
import SwiftUI
import XCTest
import FoundryDomain
import FoundryServices
@testable import Foundry

@MainActor
final class PreviewSnapshotTests: XCTestCase {
    func testRenderPreviews() async throws {
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
            try render(ClipboardHistoryView(state: clipboard), name: "clipboard-text", appearance: appearance)
            clipboard.select(id: clipboard.visibleItems[1].id)
            try render(ClipboardHistoryView(state: clipboard), name: "clipboard-file", appearance: appearance)
        }
        var paused = config.current.clipboard
        paused.isPaused = true
        clipboard.updateConfiguration(paused)
        try render(ClipboardHistoryView(state: clipboard), name: "clipboard-paused", appearance: .aqua)
        let shelfFiles = [URL(fileURLWithPath: #filePath), URL(fileURLWithPath: "/Library/Desktop Pictures/Sonoma.heic"),
                          URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app")]
        shelf.add(urls: shelfFiles)
        shelf.select(id: shelf.files[1].id)
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            try render(FileShelfView(state: shelf, convertSelected: { _ in }), name: "shelf", appearance: appearance)
        }
        let conversion = FileConversionState(assess: { _, _ in .ready })
        conversion.setSource(url: URL(fileURLWithPath: "/tmp/photo.png"))
        await conversion.refreshCapabilities()
        conversion.convert()
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            try render(FileConversionView(state: conversion), name: "conversion", appearance: appearance)
        }

        let snippetStore = FileSnippetStore(url: FileManager.default.temporaryDirectory.appendingPathComponent("snap-snippets-\(UUID()).json"))
        try snippetStore.save([
            StoredSnippet(id: "a", title: "Address", content: "1 Infinite Loop\nCupertino, CA", keyword: ";addr", useCount: 4),
            StoredSnippet(id: "b", title: "Sign-off", content: "Thanks,\n{argument name=\"name\"}", keyword: ";sig", useCount: 2),
            StoredSnippet(id: "c", title: "Old sign-off", content: "Cheers", keyword: ";sig"),
        ]).get()
        let snippets = SnippetState(store: snippetStore)
        snippets.load()
        snippets.select(id: "b")
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            try render(SnippetsView(state: snippets, expansionWarning: "Keywords won’t expand. Allow Accessibility in Settings › Snippets.",
                insert: { false }, copy: { false }), name: "snippets-editor", appearance: appearance)
            try render(ZStack {
                SnippetsView(state: snippets, insert: { false }, copy: { false })
                SnippetArgumentPrompt(names: ["name"], onCancel: {}, onSubmit: { _ in })
            }, name: "snippets-argument", appearance: appearance)
        }
    }

    func testRenderSettings() throws {
        guard let dir = ProcessInfo.processInfo.environment["FOUNDRY_QA_SNAPSHOT_DIR"] else { throw XCTSkip("snapshot dir not set") }
        let diagnostics = DiagnosticsService()
        let config = ConfigService(diagnostics: diagnostics, url: FileManager.default.temporaryDirectory.appendingPathComponent("settings-\(UUID()).json"))
        let state = CommandPanelState.isolated(
            registry: CommandRegistry(providers: [], usageRanking: UsageRankingStore.scratch(diagnostics), diagnostics: diagnostics, configService: config),
            actionRunner: ActionRunner.isolated(diagnostics: diagnostics),
            diagnostics: diagnostics,
            config: config
        )
        for pane in ["general", "agents", "clipboard"] {
            let defaults = try XCTUnwrap(UserDefaults(suiteName: isolatedDefaultsSuite("settings-snap")))
            defaults.set(pane, forKey: "settings.lastPane")
            for appearance in [NSAppearance.Name.aqua, .darkAqua] {
                let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 820, height: 600),
                    styleMask: [.titled, .closable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
                window.appearance = NSAppearance(named: appearance)
                window.contentViewController = NSHostingController(rootView: SettingsView(state: state).defaultAppStorage(defaults))
                window.setContentSize(NSSize(width: 820, height: 600))
                window.orderFront(nil)
                RunLoop.main.run(until: Date().addingTimeInterval(0.8))
                let name = "settings-\(pane)-\(appearance == .aqua ? "light" : "dark").png"
                let capture = Process()
                capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
                capture.arguments = ["-x", "-o", "-l", "\(window.windowNumber)", URL(fileURLWithPath: dir).appendingPathComponent(name).path]
                try capture.run()
                capture.waitUntilExit()
                window.orderOut(nil)
            }
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
        let registry = CommandRegistry(providers: [], usageRanking: UsageRankingStore.scratch(diagnostics), diagnostics: diagnostics, configService: config)
        let state = CommandPanelState.isolated(registry: registry, actionRunner: ActionRunner.isolated(diagnostics: diagnostics), diagnostics: diagnostics, config: config)
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
        try renderPanel(state, named: "actions", dir: dir)
        state.session.toggleActions()
        state.session.results = []
        state.session.isHomeLoading = true
        try renderPanel(state, named: "loading", dir: dir)
        state.session.isHomeLoading = false
        state.router.openQuickAI()
        try renderPanel(state, named: "quickai-empty", dir: dir)
        state.showHome()
        state.pendingDropURLs = [URL(fileURLWithPath: #filePath), URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app")]
        state.moveSelectionDown()
        try renderPanel(state, named: "drop-chooser", dir: dir)
        state.cancelDrop()
        state.open(.emojiPicker)
        state.emojiPicker.reset()
        try renderPanel(state, named: "emoji", dir: dir)
        state.router.openMediaDownloads()
        try renderPanel(state, named: "media-empty", dir: dir)
        let done = UUID(), failed = UUID(), active = UUID()
        state.mediaDownloads.start(id: done, sourceURL: "https://example.com/talk.mp4")
        state.mediaDownloads.complete(id: done, message: "")
        state.mediaDownloads.start(id: failed, sourceURL: "https://example.com/clip.mov")
        state.mediaDownloads.fail(id: failed, message: "The server refused the request.")
        state.mediaDownloads.start(id: active, sourceURL: "https://example.com/podcast.mp3")
        state.mediaDownloads.moveSelection(offset: 1)
        state.mediaDownloads.moveSelection(offset: 1)
        try renderPanel(state, named: "media", dir: dir)
        state.router.openDeveloperTools()
        state.developerTools.baseInput = "255"
        try renderPanel(state, named: "devtools", dir: dir)
        state.shutdown()
    }

    func testRenderClipboardActions() throws {
        guard let dir = ProcessInfo.processInfo.environment["FOUNDRY_QA_SNAPSHOT_DIR"] else { throw XCTSkip("snapshot dir not set") }
        let pasteboard = TestClipboardPasteboard()
        let diagnostics = DiagnosticsService()
        let config = ConfigService(diagnostics: diagnostics, url: FileManager.default.temporaryDirectory.appendingPathComponent("snap-\(UUID()).json"))
        let clipboard = ClipboardHistoryState(pasteboard: pasteboard, persistence: nil, configuration: config.current.clipboard)
        let registry = CommandRegistry(providers: [], usageRanking: UsageRankingStore.scratch(diagnostics), diagnostics: diagnostics, configService: config)
        let state = CommandPanelState.isolated(registry: registry, actionRunner: ActionRunner.isolated(diagnostics: diagnostics), diagnostics: diagnostics,
            config: config, clipboardHistory: clipboard)
        for text in ["Meeting notes for Thursday", "https://foundry.app/download"] {
            pasteboard.snapshotValue = PasteboardSnapshot(types: [.string], payload: .text(text), sourceBundleIdentifier: "com.apple.Safari")
            pasteboard.changeCountValue += 1
            clipboard.captureIfChanged()
        }
        clipboard.select(id: clipboard.visibleItems[0].id)
        state.mode = .clipboardHistory
        state.toggleActions {}
        try renderPanel(state, named: "clipboard-actions", dir: dir)
        state.shutdown()
    }

    private func renderPanel(_ state: CommandPanelState, named prefix: String, dir: String) throws {
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 736, height: 474), styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
            window.appearance = NSAppearance(named: appearance)
            let host = NSHostingView(rootView: CommandPanelView(state: state) {}.background(Color(nsColor: .windowBackgroundColor)))
            host.frame = window.contentLayoutRect
            window.contentView = host
            RunLoop.main.run(until: Date().addingTimeInterval(0.6))
            let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: rep)
            let name = "\(prefix)-\(appearance == .aqua ? "light" : "dark").png"
            try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: dir).appendingPathComponent(name))
        }
    }

}
