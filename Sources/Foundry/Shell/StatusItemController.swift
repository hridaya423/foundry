import AppKit
import Carbon

struct StatusItemMenuModel: Equatable {
    enum ItemKind: Equatable {
        case hotkeyWarning
        case openFoundry
        case clipboardHistory
        case clipboardPauseToggle
        case settings
        case welcomeGuide
        case quit
        case separator
    }

    struct Item: Equatable {
        let kind: ItemKind
        let title: String
        let keyEquivalent: String
        let keyEquivalentModifierMask: NSEvent.ModifierFlags
    }

    let items: [Item]

    init(hotkey: FoundryHotkey, clipboardPaused: Bool, hotkeyFailed: Bool) {
        var items: [Item] = []
        if hotkeyFailed {
            items.append(Item(kind: .hotkeyWarning, title: "\(hotkey.displayName) is unavailable — Choose Another Shortcut…", keyEquivalent: "", keyEquivalentModifierMask: []))
            items.append(Item(kind: .separator, title: "", keyEquivalent: "", keyEquivalentModifierMask: []))
        }
        if hotkey.keyCode == UInt32(kVK_Space) {
            items.append(Item(kind: .openFoundry, title: "Open Foundry", keyEquivalent: " ", keyEquivalentModifierMask: Self.menuModifiers(for: hotkey.modifiers)))
        } else {
            items.append(Item(kind: .openFoundry, title: "Open Foundry (\(hotkey.displayName))", keyEquivalent: "", keyEquivalentModifierMask: []))
        }
        items.append(Item(kind: .clipboardHistory, title: "Clipboard History", keyEquivalent: "", keyEquivalentModifierMask: []))
        items.append(Item(kind: .clipboardPauseToggle, title: clipboardPaused ? "Resume Clipboard" : "Pause Clipboard", keyEquivalent: "", keyEquivalentModifierMask: []))
        items.append(Item(kind: .separator, title: "", keyEquivalent: "", keyEquivalentModifierMask: []))
        items.append(Item(kind: .settings, title: "Settings…", keyEquivalent: ",", keyEquivalentModifierMask: .command))
        items.append(Item(kind: .welcomeGuide, title: "Welcome Guide", keyEquivalent: "", keyEquivalentModifierMask: []))
        items.append(Item(kind: .separator, title: "", keyEquivalent: "", keyEquivalentModifierMask: []))
        items.append(Item(kind: .quit, title: "Quit Foundry", keyEquivalent: "q", keyEquivalentModifierMask: .command))
        self.items = items
    }

    private static func menuModifiers(for carbonModifiers: UInt32) -> NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if carbonModifiers & UInt32(cmdKey) != 0 { flags.insert(.command) }
        if carbonModifiers & UInt32(optionKey) != 0 { flags.insert(.option) }
        if carbonModifiers & UInt32(controlKey) != 0 { flags.insert(.control) }
        if carbonModifiers & UInt32(shiftKey) != 0 { flags.insert(.shift) }
        return flags
    }
}

@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let state: CommandPanelState
    private var statusItem: NSStatusItem?
    var onTogglePanel: (() -> Void)?
    var onOpenPanel: (() -> Void)?
    var onWelcomeGuide: (() -> Void)?

    init(state: CommandPanelState) {
        self.state = state
        super.init()
    }

    func setVisible(_ visible: Bool) {
        if visible {
            guard statusItem == nil else { return }
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            if let button = item.button {
                let image = NSImage(systemSymbolName: "command", accessibilityDescription: "Foundry")
                image?.isTemplate = true
                button.image = image
            }
            let menu = NSMenu()
            menu.delegate = self
            item.menu = menu
            statusItem = item
        } else if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
            self.statusItem = nil
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let model = StatusItemMenuModel(
            hotkey: state.hotkey,
            clipboardPaused: state.clipboardHistory.isPaused,
            hotkeyFailed: state.launcherHotkeyFailed
        )
        for item in model.items {
            if item.kind == .separator {
                menu.addItem(.separator())
                continue
            }
            let menuItem = NSMenuItem(title: item.title, action: #selector(performItemAction(_:)), keyEquivalent: item.keyEquivalent)
            menuItem.keyEquivalentModifierMask = item.keyEquivalentModifierMask
            menuItem.representedObject = item.kind
            menuItem.target = self
            if item.kind == .hotkeyWarning {
                menuItem.image = NSImage(systemSymbolName: "exclamationmark.triangle", accessibilityDescription: nil)
            }
            menu.addItem(menuItem)
        }
    }

    @objc private func performItemAction(_ sender: NSMenuItem) {
        guard let kind = sender.representedObject as? StatusItemMenuModel.ItemKind else { return }
        switch kind {
        case .openFoundry:
            onTogglePanel?()
        case .clipboardHistory:
            onOpenPanel?()
            state.openClipboardHistory()
        case .clipboardPauseToggle:
            state.setClipboardPaused(state.clipboardHistory.isPaused == false)
        case .settings, .hotkeyWarning:
            state.openSettings()
        case .welcomeGuide:
            onWelcomeGuide?()
        case .quit:
            NSApp.terminate(nil)
        case .separator:
            break
        }
    }
}
