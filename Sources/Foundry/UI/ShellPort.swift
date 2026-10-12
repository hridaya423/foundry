import Foundation
import FoundryDomain
import FoundryServices

/// Everything the panel needs from the surrounding shell — window
/// presentation, the status item, global hotkeys, onboarding, and snippet
/// permissions — behind one seam instead of a dozen ad-hoc closures.
/// `ShellController` is the production implementation.
@MainActor
protocol ShellPort: AnyObject {
    func hotkeyChanged(_ hotkey: FoundryHotkey) throws
    func commandPreferencesChanged()
    func menuBarIconVisibilityChanged(_ visible: Bool)
    func compactCollapseChanged(_ collapsed: Bool)
    /// Makes the panel visible without resetting session state — for
    /// prompts that must surface while the panel is hidden (e.g. a
    /// destructive action invoked by hotkey).
    func ensurePanelVisible()
    func openSettings()
    func quickLook(_ url: URL)
    /// Selection moved while Quick Look is open — the preview follows it.
    func quickLookFollowSelection()
    /// Quick Look is up — Esc dismisses it before the panel.
    var isQuickLookShowing: Bool { get }
    func closeQuickLook()
    func showTransientNotice(_ feedback: ActionFeedback)
    func openWelcomeGuide()
    func snippetExpansionChanged()
    func requestSnippetAccessibility()
    func openSnippetPrivacySettings()
    func resultExecuted()
}
