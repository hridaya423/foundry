import AppKit
import Foundation

/// An action a feature mode lists in ⌘K. It runs on the panel, not through
/// the command executor, because it acts on the feature's own selection.
struct PanelClosureAction: ResultAction {
    let icon: String?
    let shortcut: ActionShortcut?
    let style: ActionStyle
    let run: @MainActor @Sendable () -> Void

    func perform(_ ctx: ActionContext) async -> CommandOutcome {
        await run()
        return .cancelled
    }
}

extension ClipboardHistoryState {
    static func linkURL(in value: String) -> URL? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.contains(" ") == false, trimmed.count > 6,
              let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https", url.host?.contains(".") == true else { return nil }
        return url
    }
}

extension CommandPanelState {
    private func featureAction(_ id: String, _ title: String, icon: String, key: String? = nil,
        modifiers: Set<ActionShortcut.Modifier> = [], destructive: Bool = false,
        run: @escaping @MainActor @Sendable () -> Void) -> CommandAction {
        CommandAction(id: "feature.\(id)", title: title, behavior: PanelClosureAction(icon: icon,
            shortcut: key.map { ActionShortcut(key: $0, modifiers: modifiers) }, style: destructive ? .destructive : .normal, run: run))
    }

    /// What ⌘K lists for the current feature mode's selection, primary first and destructive last.
    func featureActions(dismiss: @escaping @MainActor @Sendable () -> Void) -> (title: String, actions: [CommandAction])? {
        switch mode {
        case .clipboardHistory: clipboardActions(dismiss: dismiss)
        case .snippets: snippetActions(dismiss: dismiss)
        case .fileShelf: shelfActions()
        default: nil
        }
    }

    private func clipboardActions(dismiss: @escaping @MainActor @Sendable () -> Void) -> (title: String, actions: [CommandAction])? {
        guard let item = clipboardHistory.selectedItem else { return nil }
        let history = clipboardHistory
        var actions = [
            featureAction("paste", String(localized: "Paste"), icon: "text.insert", key: "\r") { [weak self] in
                if self?.directPasteSelectedClipboardItem() == true { dismiss() }
            },
            featureAction("copy", String(localized: "Copy"), icon: "doc.on.doc", key: "\r", modifiers: [.command]) { [weak self] in
                history.copySelected()
                self?.notify(.success(String(localized: "Copied \(item.title.prefix(40))")), dismissed: true)
                dismiss()
            },
        ]
        if case let .text(value) = item.payload, let url = ClipboardHistoryState.linkURL(in: value) {
            actions.append(featureAction("open-link", String(localized: "Open Link"), icon: "safari", key: "o", modifiers: [.command]) {
                NSWorkspace.shared.open(url)
                dismiss()
            })
        }
        if case .text = item.payload, history.canMergeSelectedWithPrevious {
            actions.append(featureAction("merge", String(localized: "Copy Merged with Previous"), icon: "text.append") { [weak self] in
                history.copyMergedWithPreviousSelected()
                self?.notify(.success(String(localized: "Copied both items")), dismissed: true)
                dismiss()
            })
        }
        if case .image = item.payload {
            let id = item.id
            actions.append(featureAction("extract-text", String(localized: "Extract Text"), icon: "text.viewfinder") { [weak self] in
                self?.extractTextFromClipboardItem(id: id)
            })
            actions.append(featureAction("read-code", String(localized: "Read QR or Barcode"), icon: "qrcode.viewfinder") { [weak self] in
                self?.decodeBarcodeFromClipboardItem(id: id)
            })
        }
        if case .files = item.payload {
            actions.append(featureAction("add-to-shelf", String(localized: "Add to Shelf"), icon: "tray.and.arrow.down") { [weak self] in
                guard let self else { return }
                history.addSelectedFiles(to: self.fileShelf)
                self.showActionFeedback(.success(String(localized: "Added to File Shelf")))
            })
        }
        actions.append(featureAction("pin", item.isPinned ? String(localized: "Unpin") : String(localized: "Pin"), icon: "pin",
            key: "p", modifiers: [.command]) { history.togglePinSelected() })
        actions.append(featureAction("remove", String(localized: "Remove"), icon: "xmark", key: "\u{7f}", modifiers: [.command],
            destructive: true) { history.removeSelected() })
        actions.append(featureAction("clear", String(localized: "Clear History…"), icon: "trash", key: "\u{7f}", modifiers: [.shift, .command],
            destructive: true) { [weak self] in self?.confirmClearClipboardHistory() })
        return (item.title, actions)
    }

    private func snippetActions(dismiss: @escaping @MainActor @Sendable () -> Void) -> (title: String, actions: [CommandAction])? {
        let library = snippets
        let new = featureAction("new", String(localized: "New Snippet"), icon: "plus", key: "n", modifiers: [.command]) {
            library.newSnippet()
        }
        guard let snippet = library.selectedItem else { return (String(localized: "Snippets"), [new]) }
        let actions = [
            featureAction("insert", String(localized: "Insert"), icon: "text.insert", key: "\r") { [weak self] in
                if self?.insertOrCopySelectedSnippet() == true { dismiss() }
            },
            featureAction("copy", String(localized: "Copy"), icon: "doc.on.doc", key: "\r", modifiers: [.command]) { [weak self] in
                if self?.copySelectedSnippet() == true { dismiss() }
            },
            new,
            featureAction("duplicate", String(localized: "Duplicate"), icon: "plus.square.on.square", key: "d", modifiers: [.command]) {
                library.duplicateSelected()
            },
            featureAction("pin", snippet.isPinned ? String(localized: "Unpin") : String(localized: "Pin"), icon: "pin",
                key: "p", modifiers: [.command]) { library.togglePinnedSelected() },
            featureAction("delete", String(localized: "Delete…"), icon: "trash", key: "\u{7f}", modifiers: [.command], destructive: true) {
                [weak self] in self?.confirmDeleteSnippet()
            },
        ]
        return (snippet.title, actions)
    }

    func confirmDeleteSnippet() {
        guard let snippet = snippets.selectedItem else { return }
        Task { @MainActor in
            let answer = await requestPrompt(.confirmation(title: "Delete “\(snippet.title)”?", message: "This can’t be undone.",
                confirmLabel: "Delete", isDestructive: true))
            if answer.confirmed { snippets.removeSelected() }
        }
    }

    private func shelfActions() -> (title: String, actions: [CommandAction])? {
        let shelf = fileShelf
        let files = shelf.selectedFiles
        guard files.isEmpty == false else { return nil }
        let urls = files.map(\.url)
        var actions = [
            featureAction("open", String(localized: "Open"), icon: "arrow.up.forward.app", key: "\r") {
                urls.forEach { NSWorkspace.shared.open($0) }
            },
            featureAction("reveal", String(localized: "Show in Finder"), icon: "folder", key: "o", modifiers: [.command]) {
                NSWorkspace.shared.activateFileViewerSelecting(urls)
            },
        ]
        if let first = urls.first {
            actions.append(featureAction("quick-look", String(localized: "Quick Look"), icon: "eye", key: "y", modifiers: [.command]) {
                [weak self] in self?.shell?.quickLook(first)
            })
        }
        actions.append(featureAction("remove", String(localized: "Remove from Shelf"), icon: "xmark", destructive: true) {
            shelf.removeSelected()
        })
        actions.append(featureAction("clear", String(localized: "Clear Shelf…"), icon: "trash", key: "\u{7f}", modifiers: [.shift, .command],
            destructive: true) { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                let answer = await self.requestPrompt(.confirmation(title: "Remove all \(shelf.files.count) files from the shelf?",
                    message: "The files stay where they are.", confirmLabel: "Clear Shelf", isDestructive: true))
                if answer.confirmed { shelf.clear() }
            }
        })
        let title = files.count == 1 ? files[0].url.lastPathComponent : String(localized: "\(files.count) files")
        return (title, actions)
    }

    func confirmClearClipboardHistory() {
        let total = clipboardHistory.items.count
        let pinned = clipboardHistory.items.filter(\.isPinned).count
        Task { @MainActor in
            let answer = await requestPrompt(.confirmation(
                title: pinned > 0 ? "Clear all \(total) items, including \(pinned) pinned?" : "Clear all \(total) items?",
                message: "This can’t be undone.",
                confirmLabel: "Clear All",
                isDestructive: true))
            if answer.confirmed { clipboardHistory.clear() }
        }
    }

    func toggleActions(dismiss: @escaping @MainActor @Sendable () -> Void) {
        guard mode != .search else { return session.toggleActions() }
        if session.isShowingActions { return session.isShowingActions = false }
        guard let listed = featureActions(dismiss: dismiss), listed.actions.isEmpty == false else { return }
        session.featureActions = listed.actions
        session.featureActionsTitle = listed.title
        session.actionFilter = ""
        session.isShowingActions = true
        session.selectedActionID = listed.actions.first?.id
    }

    /// Return on a surface with no text field runs its first listed action.
    func runPrimaryFeatureAction() -> Bool {
        guard mode == .fileShelf, session.isShowingActions == false,
              let run = featureActions(dismiss: {})?.actions.first.flatMap({ ($0.behavior as? PanelClosureAction)?.run }) else { return false }
        run()
        return true
    }

    /// Runs the highlighted ⌘K row in a feature mode. False when no feature list is open.
    @discardableResult
    func runSelectedFeatureAction() -> Bool {
        guard session.featureActions != nil else { return false }
        guard let action = session.selectedAction, let run = (action.behavior as? PanelClosureAction)?.run else { return true }
        session.isShowingActions = false
        run()
        return true
    }
}
