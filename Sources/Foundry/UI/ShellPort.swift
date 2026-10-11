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
    func openSettings()
    func quickLook(_ url: URL)
    func showTransientNotice(_ feedback: ActionFeedback)
    func openWelcomeGuide()
    func snippetExpansionChanged()
    func requestSnippetAccessibility()
    func openSnippetPrivacySettings()
    func resultExecuted()
}
