import AppKit
import Foundation
import FoundryDomain
import FoundryServices

/// A feature surface that takes over the panel while its mode is up. Each
/// feature owns its ⌘-shortcuts, its ⌘V text handling, and its arrow-key
/// selection — the panel dispatches instead of chaining per-mode `if`s.
@MainActor
protocol PanelFeature {
    /// ⌘-key handling. `panel` is the orchestrator for feedback,
    /// navigation, and dismissal.
    func handleModeShortcut(
        _ shortcut: ActionShortcut,
        panel: CommandPanelState,
        dismiss: @MainActor () -> Void
    ) -> Bool

    /// Arrow-key move inside the feature's own list.
    func handleMove(_ offset: Int)

    /// ⌘V text from the clipboard into the feature's query/source field.
    func pasteText(_ text: String)

    func clearFilter() -> Bool
}

extension PanelFeature {
    func handleModeShortcut(
        _ shortcut: ActionShortcut,
        panel: CommandPanelState,
        dismiss: @MainActor () -> Void
    ) -> Bool { false }

    func handleMove(_ offset: Int) {}

    func pasteText(_ text: String) {}

    func clearFilter() -> Bool { false }
}

extension CommandPanelState {
    /// The feature surface owning key/paste/selection for `mode`, or nil
    /// when the mode delegates to the shared search list machinery.
    func feature(for mode: Mode) -> (any PanelFeature)? {
        switch mode {
        case .emojiPicker: emojiPicker
        case .fileShelf: fileShelf
        case .snippets: snippets
        case .clipboardHistory: clipboardHistory
        case .translator: translator
        case .developerTools: developerTools
        case .quickAI: quickAI
        case .scriptOutput: scriptOutput
        case .search, .mediaDownloads, .fileConversion, .camera, .agents:
            nil
        }
    }
}

struct ScriptOutput: Equatable, PanelFeature {
    let title: String
    let text: String

    func handleModeShortcut(
        _ shortcut: ActionShortcut,
        panel: CommandPanelState,
        dismiss: @MainActor () -> Void
    ) -> Bool {
        guard shortcut.key == "\r" else { return false }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        panel.showActionFeedback(.success(String(localized: "Copied output")))
        return true
    }
}

extension QuickAIState: PanelFeature {
    func clearFilter() -> Bool {
        guard quickAIQuery.isEmpty == false else { return false }
        quickAIQuery = ""
        return true
    }

    func handleModeShortcut(
        _ shortcut: ActionShortcut,
        panel: CommandPanelState,
        dismiss: @MainActor () -> Void
    ) -> Bool {
        switch shortcut.key {
        case "n": panel.router.openQuickAI()
        case ".": stop()
        default: return false
        }
        return true
    }
}

extension DeveloperToolsState: PanelFeature {
    func handleModeShortcut(
        _ shortcut: ActionShortcut,
        panel: CommandPanelState,
        dismiss: @MainActor () -> Void
    ) -> Bool {
        if shortcut.key == "\r", let output = primaryOutput {
            copy(output)
            return true
        }
        let tools = Tool.allCases
        guard let index = Int(shortcut.key), tools.indices.contains(index - 1) else { return false }
        selectedTool = tools[index - 1]
        return true
    }
}

extension SnippetState: PanelFeature {
    func clearFilter() -> Bool {
        guard query.isEmpty == false else { return false }
        query = ""
        return true
    }

    func handleMove(_ offset: Int) {
        moveSelection(offset: offset)
    }

    func handleModeShortcut(
        _ shortcut: ActionShortcut,
        panel: CommandPanelState,
        dismiss: @MainActor () -> Void
    ) -> Bool {
        guard shortcut.key == "\r", selectedItem != nil else { return false }
        if panel.copySelectedSnippet() { dismiss() }
        return true
    }

    func pasteText(_ text: String) {
        query += text
    }
}

extension TranslatorState: PanelFeature {
    func handleModeShortcut(
        _ shortcut: ActionShortcut,
        panel: CommandPanelState,
        dismiss: @MainActor () -> Void
    ) -> Bool {
        switch (shortcut.key, shortcut.modifiers.contains(.shift)) {
        case ("s", _):
            swapLanguages()
        case ("c", true) where result.isEmpty == false:
            copyResult()
        case ("\r", _) where result.isEmpty == false:
            if panel.insertTranslation() == false {
                copyResult()
            }
            dismiss()
        default:
            return false
        }
        return true
    }

    func pasteText(_ text: String) {
        sourceText += text
    }
}

extension EmojiPickerState: PanelFeature {
    func clearFilter() -> Bool {
        guard query.isEmpty == false else { return false }
        query = ""
        return true
    }

    func handleModeShortcut(
        _ shortcut: ActionShortcut,
        panel: CommandPanelState,
        dismiss: @MainActor () -> Void
    ) -> Bool {
        if shortcut.key == "t" {
            cycleSkinTone()
            return true
        }
        guard let index = Int(shortcut.key), Self.skinTones.indices.contains(index - 1) else { return false }
        setSkinTone(Self.skinTones[index - 1])
        return true
    }

    /// Up/down move a whole grid row, matching what the arrows did when
    /// this dispatch lived on the panel.
    func handleMove(_ offset: Int) {
        offset > 0 ? moveDown() : moveUp()
    }

    func pasteText(_ text: String) {
        query += text
    }
}

extension ClipboardHistoryState: PanelFeature {
    func clearFilter() -> Bool {
        guard query.isEmpty == false else { return false }
        query = ""
        return true
    }

    func handleMove(_ offset: Int) {
        moveSelection(offset: offset)
    }

    func handleModeShortcut(
        _ shortcut: ActionShortcut,
        panel: CommandPanelState,
        dismiss: @MainActor () -> Void
    ) -> Bool {
        let filters = KindFilter.allCases
        switch shortcut.key {
        case "\r":
            guard let item = selectedItem else { return false }
            copySelected()
            panel.notify(.success(String(localized: "Copied \(item.title.prefix(40))")), dismissed: true)
            dismiss()
        case "p":
            togglePinSelected()
        case let key where Int(key).map({ (1...filters.count).contains($0) }) == true:
            kindFilter = filters[Int(key)! - 1]
        default:
            return false
        }
        return true
    }

    func pasteText(_ text: String) {
        query += text
    }
}

extension FileShelfState: PanelFeature {
    func handleMove(_ offset: Int) {
        moveSelection(offset: offset)
    }
}
