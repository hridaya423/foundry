import AppKit
import SwiftUI
import XCTest
import FoundryDomain
import FoundryServices
@testable import Foundry

/// Pixel-diff snapshot tests compared against checked-in light-mode
/// references in Tests/Fixtures/Snapshots. Record with
/// `FOUNDRY_SNAPSHOT_RECORD=1 swift test --filter SnapshotReferenceTests`.
@MainActor
final class SnapshotReferenceTests: XCTestCase {
    /// Row anatomy, as 1.1 shipped it: 44pt rows, 28pt icons, a detail line
    /// under the title (hidden for commands), filled badges, kind label,
    /// outlined selection, tracked-caps section headers.
    func testRowAnatomyMatchesReference() throws {
        func makeResult(_ id: String, _ title: String, subtitle: String? = nil, icon: String = "app",
                        payload: ResultPayload = .command) -> CommandResult {
            CommandResult(
                id: id,
                title: title,
                subtitle: subtitle,
                icon: CommandIcon(fallback: String(title.prefix(2)).uppercased(), systemName: icon),
                payload: payload,
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
                                        icon: "doc", payload: .file(URL(fileURLWithPath: "/tmp/long.txt"))),
                      isSelected: false, kindLabel: "File")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)

        let rep = try SnapshotHarness.render(rows, size: CGSize(width: 736, height: 300))
        try SnapshotHarness.assertMatchesReference(rep, name: "rows-light")
    }

    /// The Reduce-Transparency backdrop must paint windowBackgroundColor —
    /// the 5.6 regression was a dark wash over light mode.
    func testOpaqueBackdropMatchesReference() throws {
        let rep = try SnapshotHarness.render(
            FoundryBackdrop(isOpaque: true),
            size: CGSize(width: 300, height: 160)
        )
        try SnapshotHarness.assertMatchesReference(rep, name: "backdrop-opaque-light")
    }

    /// The in-panel confirmation prompt that replaced every modal NSAlert —
    /// title, message, destructive-style primary, cancel.
    func testConfirmPromptMatchesReference() throws {
        let prompt = ZStack {
            FoundryTheme.fillSubtle
            PanelPromptOverlay(
                spec: PanelPromptSpec(
                    title: "Empty Trash?",
                    message: "This permanently deletes the items in the Trash.",
                    confirmLabel: "Empty Trash",
                    cancelLabel: "Cancel",
                    isDestructive: true
                ),
                resolve: { _ in }
            )
        }
        let rep = try SnapshotHarness.render(prompt, size: CGSize(width: 736, height: 420))
        try SnapshotHarness.assertMatchesReference(rep, name: "prompt-confirm-light")
    }
}
