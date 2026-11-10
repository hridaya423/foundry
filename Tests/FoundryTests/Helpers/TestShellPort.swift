import Foundation
import FoundryDomain
@testable import Foundry

/// Records `ShellPort` calls so tests can assert the panel reached the
/// shell — or inject shell behavior without a real `ShellController`.
@MainActor
final class RecordingShellPort: ShellPort {
    var onHotkeyChanged: ((FoundryHotkey) throws -> Void)?
    var onCommandPreferencesChanged: (() -> Void)?
    var onMenuBarIconVisibilityChanged: ((Bool) -> Void)?
    var onCompactCollapseChanged: ((Bool) -> Void)?
    var onOpenSettings: (() -> Void)?
    var onQuickLook: ((URL) -> Void)?
    var onTransientNotice: ((ActionFeedback) -> Void)?
    var onOpenWelcomeGuide: (() -> Void)?
    var onSnippetExpansionChanged: (() -> Void)?
    var onRequestSnippetAccessibility: (() -> Void)?
    var requestedPermissions: [PermissionKind] = []
    var onOpenSnippetPrivacySettings: (() -> Void)?
    var onResultExecuted: (() -> Void)?
    var onEnsurePanelVisible: (() -> Void)?
    var onQuickLookFollowSelection: (() -> Void)?
    var quickLookShowing = false
    var onCloseQuickLook: (() -> Void)?

    func hotkeyChanged(_ hotkey: FoundryHotkey) throws { try onHotkeyChanged?(hotkey) }
    func commandPreferencesChanged() { onCommandPreferencesChanged?() }
    func menuBarIconVisibilityChanged(_ visible: Bool) { onMenuBarIconVisibilityChanged?(visible) }
    func compactCollapseChanged(_ collapsed: Bool) { onCompactCollapseChanged?(collapsed) }
    func openSettings() { onOpenSettings?() }
    func quickLook(_ url: URL) { onQuickLook?(url) }
    func showTransientNotice(_ feedback: ActionFeedback) { onTransientNotice?(feedback) }
    func openWelcomeGuide() { onOpenWelcomeGuide?() }
    func snippetExpansionChanged() { onSnippetExpansionChanged?() }
    func requestSnippetAccessibility() { onRequestSnippetAccessibility?() }
    func requestPermission(_ kind: PermissionKind) { requestedPermissions.append(kind) }
    func openSnippetPrivacySettings() { onOpenSnippetPrivacySettings?() }
    func resultExecuted() { onResultExecuted?() }
    func ensurePanelVisible() { onEnsurePanelVisible?() }
    func quickLookFollowSelection() { onQuickLookFollowSelection?() }
    var isQuickLookShowing: Bool { quickLookShowing }
    func closeQuickLook() { onCloseQuickLook?() }
}

struct OpenHomeAction: ResultAction, Equatable {
    var icon: String? { "house" }
    func perform(_ ctx: ActionContext) async -> CommandOutcome { .open(route: .home) }
}
