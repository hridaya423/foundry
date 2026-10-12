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
        guard shortcut.modifiers == [.command] else { return false }
        if mode == .search {
            guard shortcut.key == "y",
                  case let .file(url)? = session.selectedResult?.payload else { return false }
            shell?.quickLook(url)
            return true
        }
        return feature(for: mode)?.handleModeShortcut(shortcut, panel: self, dismiss: dismiss) ?? false
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

    func moveSelectionDown() {
        moveSelection(offset: 1)
    }

    func moveSelectionUp() {
        moveSelection(offset: -1)
    }

    private func moveSelection(offset: Int) {
        switch mode {
        case .fileConversion, .camera, .translator: return
        case .emojiPicker, .fileShelf, .snippets, .clipboardHistory:
            feature(for: mode)?.handleMove(offset)
            return
        case .search, .mediaDownloads, .developerTools, .quickAI, .agents:
            session.moveSelection(offset: offset)
        }
    }
}
