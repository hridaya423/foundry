import AppKit
import Foundation
import SwiftUI
import FoundryDomain
import FoundryServices

// Direct paste, snippet insertion, and clipboard/shelf image analysis.
extension CommandPanelState {
    func pasteSelectedEmoji() -> Bool {
        guard let value = emojiPicker.takeSelectedEmoji() else { return false }
        if pasteNeedsAccessibility() {
            copyEmoji(value)
            return false
        }
        do {
            try actionRunner.directPasteService.stage(.text(value))
        } catch {
            copyEmoji(value)
            notify(.success(String(localized: "Copied \(value)")), dismissed: true)
        }
        return true
    }

    private func copyEmoji(_ value: String) {
        NSPasteboard.general.copy(value)
    }

    @discardableResult
    func directPasteSelectedClipboardItem() -> Bool {
        guard let item = clipboardHistory.selectedItem else {
            showActionFeedback(.failure(String(localized: "Select an item to paste.")))
            return false
        }
        if pasteNeedsAccessibility() {
            clipboardHistory.copySelected()
            return false
        }
        do {
            try actionRunner.directPasteService.stage(item.payload)
            return true
        } catch {
            diagnostics.log("Could not stage paste: \(error.localizedDescription)")
            clipboardHistory.copySelected()
            showActionFeedback(.info(String(localized: "Copied. Press ⌘V where you want it.")))
            return false
        }
    }

    /// Clipboard image item → Vision OCR → staged text file → Quick Look.
    func extractTextFromClipboardItem(id: String) {
        guard let payload = clipboardHistory.resolvedPayload(for: id),
              case let .image(data) = payload else { return }
        Task {
            do {
                if try await TextPreview.extractText(fromImageData: data, onQuickLook: actionRunner.panel.onQuickLook) == false {
                    showActionFeedback(.failure(String(localized: "No text found in this image. Try a sharper screenshot.")))
                }
            } catch {
                diagnostics.log("Clipboard OCR failed: \(error.localizedDescription)")
                showActionFeedback(.failure(String(localized: "Couldn't read this image.")))
            }
        }
    }

    /// Clipboard image item → barcode/QR decode → staged text → Quick Look.
    func decodeBarcodeFromClipboardItem(id: String) {
        guard let payload = clipboardHistory.resolvedPayload(for: id),
              case let .image(data) = payload else { return }
        Task {
            do {
                if try await TextPreview.decodeBarcode(fromImageData: data, onQuickLook: actionRunner.panel.onQuickLook) == false {
                    showActionFeedback(.failure(String(localized: "No barcode or QR code found in this image.")))
                }
            } catch {
                diagnostics.log("Clipboard barcode decode failed: \(error.localizedDescription)")
                showActionFeedback(.failure(String(localized: "Couldn't read this image.")))
            }
        }
    }

    /// File Shelf image → OCR → staged text → Quick Look.
    func extractTextFromShelfFile(_ url: URL) {
        Task {
            do { _ = try await TextPreview.extractText(at: url, onQuickLook: actionRunner.panel.onQuickLook) }
            catch { diagnostics.log("Shelf OCR failed: \(error.localizedDescription)") }
        }
    }

    /// File Shelf image → barcode/QR decode → staged text → Quick Look.
    func decodeBarcodeFromShelfFile(_ url: URL) {
        Task {
            do { _ = try await TextPreview.decodeBarcode(at: url, onQuickLook: actionRunner.panel.onQuickLook) }
            catch { diagnostics.log("Shelf barcode decode failed: \(error.localizedDescription)") }
        }
    }

    @discardableResult
    func directPasteSelectedSnippet(arguments: [String: String] = [:]) -> Bool {
        guard let snippet = snippets.selectedItem else { return false }
        let rendered = SnippetRenderer.render(snippet.content, arguments: arguments)
        do {
            try actionRunner.directPasteService.stage(.text(rendered.text), cursorOffset: rendered.cursorOffsetFromEnd)
            snippets.markUsed(id: snippet.id)
            return true
        } catch {
            diagnostics.log("Could not stage snippet: \(error.localizedDescription)")
            return false
        }
    }

    @discardableResult
    func insertTranslation() -> Bool {
        guard translator.result.isEmpty == false else { return false }
        do {
            try actionRunner.directPasteService.stage(.text(translator.result), cursorOffset: 0)
            return true
        } catch {
            diagnostics.log("Could not stage paste: \(error.localizedDescription)")
            return false
        }
    }

    func insertOrCopySelectedSnippet() -> Bool {
        guard askForSnippetArguments(copyOnly: false) == false else { return false }
        if pasteNeedsAccessibility() {
            snippets.copySelected()
            return false
        }
        if directPasteSelectedSnippet() == false { snippets.copySelected() }
        return true
    }

    func copySelectedSnippet() -> Bool {
        guard askForSnippetArguments(copyOnly: true) == false else { return false }
        snippets.copySelected()
        showActionFeedback(.success(String(localized: "Copied snippet")))
        return true
    }

    private func askForSnippetArguments(copyOnly: Bool) -> Bool {
        guard let snippet = snippets.selectedItem else { return false }
        let names = SnippetRenderer.argumentNames(in: snippet.content)
        guard names.isEmpty == false else { return false }
        pendingSnippetArguments = SnippetArgumentRequest(names: names, copyOnly: copyOnly)
        return true
    }

    func cancelSnippetArguments() { pendingSnippetArguments = nil }

    @discardableResult
    func submitSnippetArguments(_ values: [String: String]) -> Bool {
        guard let request = pendingSnippetArguments, snippets.selectedItem != nil else { return false }
        pendingSnippetArguments = nil
        if request.copyOnly || directPasteSelectedSnippet(arguments: values) == false {
            snippets.copySelected(arguments: values)
            if request.copyOnly { showActionFeedback(.success(String(localized: "Copied snippet"))) }
        }
        return true
    }

    func pasteOrCopySelectedClipboardItem() {
        directPasteSelectedClipboardItem()
    }

    /// Without Accessibility, paste cannot reach the other app. The item is
    /// already copied; ask in the panel instead of failing after it closes.
    func pasteNeedsAccessibility() -> Bool {
        guard actionRunner.directPasteService.canPaste == false else { return false }
        let app = actionRunner.directPasteService.targetName ?? String(localized: "other apps")
        Task { @MainActor in
            let answer = await requestPrompt(PanelPromptSpec(
                title: "Allow Accessibility to paste into \(app).",
                message: "Your item is copied. Press ⌘V to paste it now.",
                confirmLabel: "Allow",
                cancelLabel: "Not Now"))
            if answer.confirmed { shell?.requestPermission(.accessibility) }
        }
        return true
    }
}

struct SnippetArgumentRequest: Equatable {
    let names: [String]
    let copyOnly: Bool
}
