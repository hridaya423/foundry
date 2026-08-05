import XCTest
@testable import Foundry
import FoundryDomain

final class SearchScoringTests: XCTestCase {
    func testExactAliasIsStrongestMatch() {
        let match = SearchScoring.match(query: "ship", title: "Deploy Project", aliases: ["ship"])
        XCTAssertEqual(match?.kind, .exact)
        XCTAssertEqual(match?.field, .alias)
        XCTAssertEqual(match?.tier, .aliasExact)
    }

    func testTitlePrefixBeatsOrderedTokenMatch() {
        let prefixMatch = SearchScoring.match(query: "keyboard", title: "Keyboard Settings")
        let tokenMatch = SearchScoring.match(query: "system settings", title: "Open System Settings")

        XCTAssertEqual(prefixMatch?.kind, .phrasePrefix)
        XCTAssertEqual(prefixMatch?.tier, .titlePrefix)
        XCTAssertEqual(tokenMatch?.kind, .tokenMatch)
        XCTAssertEqual(tokenMatch?.tier, .titleToken)
        XCTAssertTrue(SearchScoring.isBetter(prefixMatch!, than: tokenMatch!))
    }

    func testMultiWordQueriesRequireOrderedTokenCoverage() {
        XCTAssertEqual(SearchScoring.match(query: "system settings", title: "Open System Settings")?.kind, .tokenMatch)
        XCTAssertNil(SearchScoring.match(query: "settings system", title: "Open System Settings"))
    }

    func testTokenMatchKeepsOrderedCoverageAcrossTokens() {
        let match = SearchScoring.match(query: "open settings", title: "Open System Settings")
        XCTAssertEqual(match?.kind, .tokenMatch)
        XCTAssertEqual(match?.exactTokenCount, 2)
        XCTAssertNil(SearchScoring.match(query: "settings open", title: "Open System Settings"))
    }

    func testFuzzyMatchingHandlesTyposButRejectsShortQueries() {
        let match = SearchScoring.match(query: "keybord", title: "Keyboard Settings")
        XCTAssertEqual(match?.kind, .fuzzy)
        XCTAssertEqual(match?.editDistance, 1)
        XCTAssertEqual(SearchScoring.match(query: "calender", title: "Calendar")?.editDistance, 1)
        XCTAssertNil(SearchScoring.match(query: "x", title: "Example Command", allowFuzzy: true))
        XCTAssertNil(SearchScoring.match(query: "keybord", title: "Keyboard Settings", allowFuzzy: false))
    }

    func testExactMetadataMatchBeatsFuzzyMetadataMatch() {
        let exact = SearchScoring.match(query: "workspace", title: "Project", subtitle: "Workspace", keywords: [], aliases: [])
        let fuzzy = SearchScoring.match(query: "workspace", title: "Project", subtitle: "Workspace Tools", keywords: [], aliases: [])

        XCTAssertTrue(SearchScoring.isBetter(exact!, than: fuzzy!))
    }

    func testFuzzyMatchingSupportsRaycastStyleAbbreviations() {
        XCTAssertNotNil(SearchScoring.match(query: "msg", title: "Messages"))
        XCTAssertNotNil(SearchScoring.match(query: "vs code", title: "Visual Studio Code"))
        XCTAssertNotNil(SearchScoring.match(query: "utub vid", title: "Search YouTube Videos"))
        XCTAssertNotNil(SearchScoring.match(query: "wifi settings", title: "Wi-Fi Settings"))
    }

    func testFuzzyMatchingRequiresEveryQueryToken() {
        XCTAssertNotNil(SearchScoring.match(query: "project dash", title: "Open Project Dashboard"))
        XCTAssertNil(SearchScoring.match(query: "project missing", title: "Open Project Dashboard"))
    }

    func testAliasesAreStrictAndDoNotUseFuzzyMatching() {
        XCTAssertEqual(SearchScoring.match(query: "ship", title: "Deploy Project", aliases: ["ship"])?.tier, .aliasExact)
        XCTAssertNil(SearchScoring.match(query: "shp", title: "Deploy Project", aliases: ["ship"]))
        XCTAssertNil(SearchScoring.match(query: "ch", title: "Emoji & Symbols", aliases: ["characters"]))
    }

    func testAliasPrefixRequiresThreeCharacters() {
        XCTAssertEqual(SearchScoring.match(query: "char", title: "Emoji & Symbols", aliases: ["characters"])?.tier, .aliasPrefix)
        XCTAssertNil(SearchScoring.match(query: "ch", title: "Emoji & Symbols", aliases: ["characters"]))
    }

    func testSubtitleAndKeywordMatchesRankBelowTitleMatches() {
        let titleMatch = SearchScoring.match(query: "project dashboard", title: "Project Dashboard", subtitle: "Open the workspace", keywords: [], aliases: [])
        let subtitleMatch = SearchScoring.match(query: "workspace", title: "Project Dashboard", subtitle: "Open the workspace", keywords: [], aliases: [])
        let keywordMatch = SearchScoring.match(query: "deploy", title: "Project Dashboard", subtitle: nil, keywords: ["deploy", "release"], aliases: [])

        XCTAssertEqual(titleMatch?.tier, .titleExact)
        XCTAssertEqual(subtitleMatch?.tier, .subtitle)
        XCTAssertEqual(keywordMatch?.tier, .keyword)
        XCTAssertTrue(SearchScoring.isBetter(titleMatch!, than: subtitleMatch!))
        XCTAssertTrue(SearchScoring.isBetter(subtitleMatch!, than: keywordMatch!))
    }

    func testExactTokenCountBreaksTiesWithinATier() {
        let bothExact = SearchScoring.match(query: "open settings", title: "Open System Settings")
        let oneExact = SearchScoring.match(query: "sys settings", title: "Open System Settings")

        XCTAssertEqual(bothExact?.kind, .tokenMatch)
        XCTAssertEqual(bothExact?.exactTokenCount, 2)
        XCTAssertEqual(oneExact?.exactTokenCount, 1)
        XCTAssertTrue(SearchScoring.isBetter(bothExact!, than: oneExact!))
    }

    func testSensitivityControlsFuzzyBreadth() {
        XCTAssertNil(SearchScoring.match(query: "kbrd", title: "Keyboard Settings", subtitle: nil, keywords: [], aliases: [], sensitivity: .high))
        XCTAssertNotNil(SearchScoring.match(query: "kbrd", title: "Keyboard Settings", subtitle: nil, keywords: [], aliases: [], sensitivity: .medium))
        XCTAssertNotNil(SearchScoring.match(query: "kbrd", title: "Keyboard Settings", subtitle: nil, keywords: [], aliases: [], sensitivity: .low))
    }

    func testLooseSubsequenceRequiresReasonableDensity() {
        XCTAssertNotNil(SearchScoring.match(query: "kbrd", title: "Keyboard Settings"))
        XCTAssertNil(SearchScoring.match(query: "xyz", title: "A Very Long Unrelated Command Name"))
    }
}
