import AppKit
import Foundation
import SwiftUI
import FoundryDomain
import FoundryServices

// Keyboard dispatch: mode shortcuts, action shortcuts, paste, arrows.
extension CommandPanelState {
    var compactCollapsed: Bool {
        settings.windowMode == .compact
            && mode == .search
            && session.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && session.isShowingActions == false
    }

    func performModeShortcut(_ shortcut: ActionShortcut, dismiss: @escaping @MainActor () -> Void) -> Bool {
        if shortcut.modifiers == [.control], let offset = ["n": 1, "p": -1][shortcut.key] {
            moveSelection(offset: offset)
            return true
        }
        guard shortcut.modifiers == [.command] || shortcut.modifiers == [.shift, .command] else { return false }
        if mode == .search, shortcut.modifiers == [.command], let digit = Int(shortcut.key) {
            return openFavorite(at: digit - 1, dismiss: dismiss)
        }
        if mode == .search {
            guard shortcut.key == "y",
                  case let .file(url)? = session.selectedResult?.payload else { return false }
            shell?.quickLook(url)
            return true
        }
        if feature(for: mode)?.handleModeShortcut(shortcut, panel: self, dismiss: dismiss) == true { return true }
        let sendableDismiss: @MainActor @Sendable () -> Void = { dismiss() }
        guard let action = featureActions(dismiss: sendableDismiss)?.actions.first(where: { $0.behavior.shortcut == shortcut }),
              let run = (action.behavior as? PanelClosureAction)?.run else { return false }
        session.isShowingActions = false
        run()
        return true
    }

    @discardableResult
    func performActionShortcut(_ shortcut: ActionShortcut, dismiss: @escaping @MainActor () -> Void) -> Bool {
        guard mode == .search, isActionInProgress == false, let result = session.selectedResult,
              let actionID = session.actionShortcuts.first(where: { $0.value == shortcut })?.key,
              let action = session.selectedActions.first(where: { $0.id == actionID }) else { return false }
        Task { @MainActor in
            if await executeResult(result, action: action).shouldDismissPanel { dismiss() }
        }
        return true
    }

    /// Space toggles Quick Look for a selected file result — returning true
    /// swallows the event so it never reaches the query field. ⌘Y takes
    /// the same path through `performModeShortcut`.
    func spaceTogglesQuickLook() -> Bool {
        guard mode == .search, session.isShowingActions == false,
              case let .file(url)? = session.selectedResult?.payload else { return false }
        shell?.quickLook(url)
        return true
    }

    func pasteFromClipboard() -> Bool {
        guard let text = NSPasteboard.general.string(forType: .string), text.isEmpty == false else { return false }
        if mode == .search {
            session.query += text
            return true
        }
        guard let feature = feature(for: mode) else { return false }
        feature.pasteText(text)
        return true
    }

    enum SelectionJump {
        case first, last, pageUp, pageDown
    }

    func moveSelection(_ jump: SelectionJump) {
        let page = 7
        let far = max(session.navigableResults.count, 10_000)
        switch jump {
        case .first: moveSelection(offset: -far)
        case .last: moveSelection(offset: far)
        case .pageUp: moveSelection(offset: -page)
        case .pageDown: moveSelection(offset: page)
        }
    }

    private func openFavorite(at index: Int, dismiss: @escaping @MainActor () -> Void) -> Bool {
        guard session.query.isEmpty, session.isShowingActions == false, (0..<8).contains(index),
              session.favoriteResults.indices.contains(index) else { return false }
        let favorite = session.favoriteResults[index]
        session.selectedResultID = favorite.id
        Task { @MainActor in
            if await executeResult(favorite).shouldDismissPanel { dismiss() }
        }
        return true
    }

    func moveSelectionDown() {
        moveSelection(offset: 1)
    }

    func moveSelectionUp() {
        moveSelection(offset: -1)
    }

    private func moveSelection(offset: Int) {
        if pendingDropURLs != nil {
            dropSelection = min(max(dropSelection + offset, 0), dropChoices.count - 1)
            return
        }
        if session.featureActions != nil { return session.moveSelection(offset: offset) }
        switch mode {
        case .fileConversion, .camera, .translator, .scriptOutput: return
        case .emojiPicker, .fileShelf, .snippets, .clipboardHistory:
            feature(for: mode)?.handleMove(offset)
            return
        case .search, .mediaDownloads, .developerTools, .quickAI, .agents:
            session.moveSelection(offset: offset)
        }
    }
}
