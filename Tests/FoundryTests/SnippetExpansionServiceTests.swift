import XCTest
@testable import Foundry
import AppKit

@MainActor
final class SnippetExpansionServiceTests: XCTestCase {
    private let date = Date(timeIntervalSince1970: 100)

    private func temporaryStore() -> FileSnippetStore {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("expansion-snippets-\(UUID().uuidString).json")
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return FileSnippetStore(url: url)
    }

    private func isolatedPaste() -> DirectPasteService {
        DirectPasteService.isolated()
    }

    private func engine(_ snippets: [StoredSnippet] = [StoredSnippet(content: "Hello", keyword: "brb", updatedAt: Date(timeIntervalSince1970: 1))]) -> SnippetExpansionEngine {
        SnippetExpansionEngine(snippets: snippets, render: { RenderedSnippet(text: $0.content.uppercased(), cursorOffsetFromEnd: 0) })
    }

    func testPrefixAndModifierAreBufferedAndModifierResets() {
        var value = engine(); _ = value.receive(.character("b")); _ = value.receive(.character("r")); _ = value.receive(.modifier)
        XCTAssertEqual(value.buffer, "")
        _ = value.receive(.character("b")); _ = value.receive(.character("r")); _ = value.receive(.character("b"))
        XCTAssertEqual(value.buffer, "brb")
    }

    func testBackspaceAndExactDelimiterExpandOnceAndDeleteKeywordOnly() {
        var value = engine([StoredSnippet(id: "s1", content: "Hello", keyword: "brb", updatedAt: Date(timeIntervalSince1970: 1))])
        ["b", "r", "x"].forEach { _ = value.receive(.character($0)) }; _ = value.receive(.backspace); _ = value.receive(.character("b"))
        guard case let .expanded(expansion) = value.receive(.delimiter(" ")) else { return XCTFail("Expected expansion") }
        XCTAssertEqual(expansion, .init(snippetID: "s1", rendered: .init(text: "HELLO", cursorOffsetFromEnd: 0), delimiter: " ", deleteCount: 3))
        XCTAssertEqual(value.buffer, "")
        XCTAssertEqual(value.receive(.delimiter(" ")), .ignored)
    }

    func testRepeatedSecureInputOffBetweenKeysKeepsTheBuffer() {
        var value = engine([StoredSnippet(id: "s1", content: "Hello", keyword: "brb", updatedAt: Date(timeIntervalSince1970: 1))])
        for character in ["b", "r", "b"] {
            _ = value.receive(.secureInputChanged(false))
            _ = value.receive(.character(character))
        }
        _ = value.receive(.secureInputChanged(false))
        guard case let .expanded(expansion) = value.receive(.delimiter(" ")) else { return XCTFail("Expected expansion") }
        XCTAssertEqual(expansion.snippetID, "s1")
        XCTAssertEqual(expansion.deleteCount, 3)
    }

    func testCursorPlaceholderPlacesTheCaretBeforeTheTypedDelimiter() {
        var value = SnippetExpansionEngine(snippets: [StoredSnippet(content: "Dear {cursor}, thanks", keyword: "dear")],
            render: { SnippetRenderer.render($0.content, context: SnippetRenderContext(now: .distantPast, locale: .init(identifier: "en_US_POSIX"),
                calendar: .init(identifier: .gregorian), clipboard: "")) })
        "dear".forEach { _ = value.receive(.character(String($0))) }
        guard case let .expanded(expansion) = value.receive(.delimiter(" ")) else { return XCTFail("Expected expansion") }
        XCTAssertEqual(expansion.pasteText, "Dear , thanks ")
        XCTAssertEqual(expansion.cursorOffset, ", thanks ".count)

        var plain = engine(); "brb".forEach { _ = plain.receive(.character(String($0))) }
        guard case let .expanded(plainExpansion) = plain.receive(.delimiter("\t")) else { return XCTFail("Expected expansion") }
        XCTAssertEqual(plainExpansion.pasteText, "HELLO\t")
        XCTAssertEqual(plainExpansion.cursorOffset, 0)
    }

    func testExclusionSecureInputAndAppSwitchReset() {
        var value = SnippetExpansionEngine(snippets: [StoredSnippet(content: "x", keyword: "go")], excludedBundleIdentifiers: ["com.editor"])
        _ = value.receive(.appChanged(bundleIdentifier: "com.editor")); _ = value.receive(.character("g")); _ = value.receive(.character("o"))
        XCTAssertEqual(value.receive(.delimiter("\n")), .ignored)
        _ = value.receive(.appChanged(bundleIdentifier: "com.other")); _ = value.receive(.secureInputChanged(true)); _ = value.receive(.character("g")); _ = value.receive(.character("o"))
        XCTAssertEqual(value.receive(.delimiter(" ")), .ignored)
        _ = value.receive(.secureInputChanged(false)); _ = value.receive(.character("g")); _ = value.receive(.character("o"))
        guard case let .expanded(lateExpansion) = value.receive(.delimiter(" ")) else { return XCTFail("Expected expansion") }
        XCTAssertEqual(lateExpansion.rendered.text, "x")
        XCTAssertEqual(lateExpansion.delimiter, " ")
        XCTAssertEqual(lateExpansion.deleteCount, 2)
    }

    func testDuplicateKeywordsDisableExpansionWhilePrecedenceRemainsDeterministic() {
        let old = StoredSnippet(id: "z", content: "old", keyword: "x", updatedAt: date)
        let newer = StoredSnippet(id: "a", content: "new", keyword: "x", updatedAt: date.addingTimeInterval(1))
        var value = engine([old, newer]); _ = value.receive(.character("x"))
        XCTAssertEqual(value.receive(.delimiter("\t")), .ignored)
        var pinned = old; pinned.isPinned = true; value = engine([newer, pinned]); _ = value.receive(.character("x"))
        XCTAssertEqual(value.receive(.delimiter(" ")), .ignored)
    }

    func testDeniedConfiguredServiceStartsOnceWhenAccessibilityBecomesGranted() {
        var trusted = false
        var promptCount = 0
        var startCount = 0
        var retry: (() -> Void)?
        let service = SnippetExpansionService(
            snippetStore: temporaryStore(),
            directPaste: isolatedPaste(),
            accessibilityTrusted: { trusted },
            requestAccessibilityPrompt: { promptCount += 1 },
            scheduleAccessibilityRetry: { callback in
                retry = callback
                return {}
            },
            startEventTap: {
                startCount += 1
                return true
            }
        )

        service.configure(isEnabled: true, excludedBundleIdentifiers: [])
        service.requestAccessibilityAccess()
        trusted = true
        retry?()
        retry?()

        XCTAssertEqual(promptCount, 1)
        XCTAssertEqual(startCount, 1)
        XCTAssertTrue(service.isRunning)
    }

    func testStoppingConfiguredServiceCancelsAccessibilityRetry() {
        var cancelCount = 0
        let service = SnippetExpansionService(
            snippetStore: temporaryStore(),
            directPaste: isolatedPaste(),
            accessibilityTrusted: { false },
            requestAccessibilityPrompt: {},
            scheduleAccessibilityRetry: { _ in
                return { cancelCount += 1 }
            }
        )

        service.configure(isEnabled: true, excludedBundleIdentifiers: [])
        service.requestAccessibilityAccess()
        service.stop()

        XCTAssertEqual(cancelCount, 1)
    }
}
