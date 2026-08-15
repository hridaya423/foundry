import XCTest
@testable import Foundry
import AppKit

@MainActor
final class SnippetExpansionServiceTests: XCTestCase {
    private let date = Date(timeIntervalSince1970: 100)

    private func engine(_ snippets: [StoredSnippet] = [StoredSnippet(content: "Hello", keyword: "brb", updatedAt: Date(timeIntervalSince1970: 1))]) -> SnippetExpansionEngine {
        SnippetExpansionEngine(snippets: snippets, render: { $0.content.uppercased() })
    }

    func testPrefixAndModifierAreBufferedAndModifierResets() {
        var value = engine(); _ = value.receive(.character("b")); _ = value.receive(.character("r")); _ = value.receive(.modifier)
        XCTAssertEqual(value.buffer, "")
        _ = value.receive(.character("b")); _ = value.receive(.character("r")); _ = value.receive(.character("b"))
        XCTAssertEqual(value.buffer, "brb")
    }

    func testBackspaceAndExactDelimiterExpandOnceAndDeleteKeywordOnly() {
        var value = engine(); ["b", "r", "x"].forEach { _ = value.receive(.character($0)) }; _ = value.receive(.backspace); _ = value.receive(.character("b"))
        guard case let .expanded(expansion) = value.receive(.delimiter(" ")) else { return XCTFail("Expected expansion") }
        XCTAssertEqual(expansion, .init(keyword: "brb", renderedContent: "HELLO", delimiter: " ", deleteCount: 3))
        XCTAssertEqual(value.buffer, "")
        XCTAssertEqual(value.receive(.delimiter(" ")), .ignored)
    }

    func testExclusionSecureInputAndAppSwitchReset() {
        var value = SnippetExpansionEngine(snippets: [StoredSnippet(content: "x", keyword: "go")], excludedBundleIdentifiers: ["com.editor"])
        _ = value.receive(.appChanged(bundleIdentifier: "com.editor")); _ = value.receive(.character("g")); _ = value.receive(.character("o"))
        XCTAssertEqual(value.receive(.delimiter("\n")), .ignored)
        _ = value.receive(.appChanged(bundleIdentifier: "com.other")); _ = value.receive(.secureInputChanged(true)); _ = value.receive(.character("g")); _ = value.receive(.character("o"))
        XCTAssertEqual(value.receive(.delimiter(" ")), .ignored)
        _ = value.receive(.secureInputChanged(false)); _ = value.receive(.character("g")); _ = value.receive(.character("o"))
        XCTAssertEqual(value.receive(.delimiter(" ")), .expanded(.init(keyword: "go", renderedContent: "x", delimiter: " ", deleteCount: 2)))
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
            directPaste: DirectPasteService(),
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
            directPaste: DirectPasteService(),
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
