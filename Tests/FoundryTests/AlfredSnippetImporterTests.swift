import XCTest
@testable import Foundry

final class AlfredSnippetImporterTests: XCTestCase {
    func testImportsAlfredSnippetsFromPreferencesBundle() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("alfred-\(UUID().uuidString)/Alfred.alfredpreferences")
        let collection = root.appendingPathComponent("snippets/Work")
        try FileManager.default.createDirectory(at: collection, withIntermediateDirectories: true)
        let files = [
            ("Signature [A1].json", #"{"alfredsnippet":{"snippet":"Best,\nSam","uid":"A1","name":"Signature","keyword":"sig"}}"#),
            ("Address [A2].json", #"{"alfredsnippet":{"snippet":"1 Infinite Loop","uid":"A2","name":"Address","keyword":"addr"}}"#),
            ("Short sig [A3].json", #"{"alfredsnippet":{"snippet":"Sam","uid":"A3","name":"","keyword":"sig"}}"#),
            ("info.plist", "not json"),
        ]
        for (name, body) in files {
            try body.write(to: collection.appendingPathComponent(name), atomically: true, encoding: .utf8)
        }
        let snippets = AlfredSnippetImporter(preferencesRoot: root).snippets()
        XCTAssertEqual(snippets.count, 3)
        XCTAssertEqual(Set(snippets.map(\.title)), ["Signature", "Address", "Sam"])
        XCTAssertEqual(snippets.first { $0.title == "Signature" }?.content, "Best,\nSam")
        XCTAssertEqual(AlfredSnippetImporter.duplicateKeywords(in: snippets), ["sig"])
    }

    func testMissingPreferencesBundleImportsNothing() {
        XCTAssertEqual(AlfredSnippetImporter(preferencesRoot: nil).snippets().count, 0)
        XCTAssertEqual(AlfredSnippetImporter(preferencesRoot: URL(fileURLWithPath: "/nonexistent")).snippets().count, 0)
    }
}
