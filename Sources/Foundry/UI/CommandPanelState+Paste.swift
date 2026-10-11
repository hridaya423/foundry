import AppKit
import Foundation
import SwiftUI
import FoundryDomain
import FoundryServices

// Direct paste, snippet insertion, and clipboard/shelf image analysis.
extension CommandPanelState {
    @discardableResult
    func directPasteSelectedClipboardItem() -> Bool {
        guard let item = clipboardHistory.selectedItem else {
            clipboardHistory.report(ClipboardDirectPasteError.noSelection)
            return false
        }
        do {
            try actionRunner.directPasteService.stage(item.payload)
            return true
        } catch {
            diagnostics.log("Could not stage paste: \(error.localizedDescription)")
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
                    clipboardHistory.report(ClipboardVisionError.noTextFound)
                }
            } catch {
                diagnostics.log("Clipboard OCR failed: \(error.localizedDescription)")
                clipboardHistory.report(ClipboardVisionError.failed)
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
                    clipboardHistory.report(ClipboardVisionError.noBarcodeFound)
                }
            } catch {
                diagnostics.log("Clipboard barcode decode failed: \(error.localizedDescription)")
                clipboardHistory.report(ClipboardVisionError.failed)
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
        guard let snippet = snippets.selectedItem else { return false }
        let names = SnippetRenderer.argumentNames(in: snippet.content)
        if names.isEmpty == false {
            pendingSnippetArguments = names
            return false
        }
        if directPasteSelectedSnippet() == false { snippets.copySelected() }
        return true
    }

    func cancelSnippetArguments() { pendingSnippetArguments = nil }

    @discardableResult
    func submitSnippetArguments(_ values: [String: String]) -> Bool {
        pendingSnippetArguments = nil
        return directPasteSelectedSnippet(arguments: values)
    }

    func pasteOrCopySelectedClipboardItem() {
        if directPasteSelectedClipboardItem() == false { clipboardHistory.copySelected() }
    }
}

private enum ClipboardDirectPasteError: LocalizedError {
    case noSelection
    var errorDescription: String? { "Select an item to paste." }
}

private enum ClipboardVisionError: LocalizedError {
    case noTextFound, noBarcodeFound, failed
    var errorDescription: String? {
        switch self {
        case .noTextFound: "No text found in that image."
        case .noBarcodeFound: "No barcode found in that image."
        case .failed: "Could not analyze that image."
        }
    }
}
