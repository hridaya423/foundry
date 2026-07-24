import XCTest
@testable import Foundry

final class AIChatStoreTests: XCTestCase {
    func testChatThreadCodableRoundTrip() throws {
        let thread = AIChatThread(title: "Test", messages: [
            AIChatMessage(role: .user, content: "Hello"),
            AIChatMessage(role: .assistant, content: "World")
        ])

        let data = try JSONEncoder().encode([thread])
        let restored = try JSONDecoder().decode([AIChatThread].self, from: data)

        XCTAssertEqual(restored.first?.title, "Test")
        XCTAssertEqual(restored.first?.messages.count, 2)
        XCTAssertEqual(restored.first?.messages.first?.content, "Hello")
    }

    func testConversationContextRespectsBudgetAndExcludesTools() {
        let messages = [
            AIChatMessage(role: .user, content: String(repeating: "a", count: 200)),
            AIChatMessage(role: .tool, content: "complete:web_search"),
            AIChatMessage(role: .assistant, content: String(repeating: "b", count: 200))
        ]
        let context = AIConversationContext.build(from: messages, maxCharacters: 120)
        XCTAssertNotNil(context)
        XCTAssertLessThanOrEqual(context?.count ?? 0, 120)
        XCTAssertFalse(context?.contains("web_search") == true)
    }

    func testChatStorePersistsToAnInjectedURL() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("foundry-chat-\(UUID().uuidString).json")
        let thread = AIChatThread(title: "Saved", messages: [AIChatMessage(role: .user, content: "Hello")])
        let store = AIChatStore(url: url)

        store.save([thread])

        XCTAssertEqual(store.load().first?.messages.first?.content, "Hello")
        try? FileManager.default.removeItem(at: url)
    }

    func testChatStoreReturnsEmptyForCorruptData() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("foundry-chat-\(UUID().uuidString).json")
        try Data("not json".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertTrue(AIChatStore(url: url).load().isEmpty)
    }
}
