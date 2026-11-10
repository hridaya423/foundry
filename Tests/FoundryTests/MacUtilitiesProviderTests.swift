import XCTest
@testable import Foundry

final class MacUtilitiesProviderTests: XCTestCase {
    func testPortResultsRequireExplicitPortIntent() async {
        let provider = MacUtilitiesProvider()

        let bareDigits = await provider.results(matching: "2024")
        XCTAssertFalse(bareDigits.contains { $0.id.hasPrefix("mac.port.") })

        let explicit = await provider.results(matching: "port 1")
        XCTAssertTrue(explicit.contains { $0.id == "mac.port.1" })
    }

    func testQuitQueriesNameAnAppByWordPrefix() {
        XCTAssertEqual(MacUtilitiesProvider.quitRequest(in: "quit saf")?.needle, "saf")
        XCTAssertEqual(MacUtilitiesProvider.quitRequest(in: "quit")?.needle, "")
        XCTAssertEqual(MacUtilitiesProvider.quitRequest(in: "force quit chrome")?.force, true)
        XCTAssertEqual(MacUtilitiesProvider.quitRequest(in: "quit chrome")?.force, false)
        XCTAssertNil(MacUtilitiesProvider.quitRequest(in: "quite"))

        XCTAssertTrue(MacUtilitiesProvider.appName("Google Chrome", matches: "chr"))
        XCTAssertTrue(MacUtilitiesProvider.appName("Safari", matches: ""))
        XCTAssertFalse(MacUtilitiesProvider.appName("Wallpaper", matches: "all"))
    }

    func testVolumeQueriesCarryALevel() {
        XCTAssertEqual(MacUtilitiesProvider.volumeLevel(in: "volume 50"), 50)
        XCTAssertEqual(MacUtilitiesProvider.volumeLevel(in: "set volume to 30%"), 30)
        XCTAssertEqual(MacUtilitiesProvider.volumeLevel(in: "vol 0"), 0)
        XCTAssertNil(MacUtilitiesProvider.volumeLevel(in: "volume 150"))
        XCTAssertNil(MacUtilitiesProvider.volumeLevel(in: "volume"))
        XCTAssertNil(MacUtilitiesProvider.volumeLevel(in: "50"))
    }

    func testVolumeAndAddressQueriesProduceRows() async {
        let provider = MacUtilitiesProvider()
        let volume = await provider.results(matching: "volume 40")
        XCTAssertEqual(volume.first { $0.id == "mac.volume.40" }?.title, "Set Volume to 40%")
        for query in ["my ip", "ip", "IP address", "what's my ip"] {
            XCTAssertTrue(MacUtilitiesProvider.asksForAddress(query), query)
        }
        XCTAssertFalse(MacUtilitiesProvider.asksForAddress("zip"))
    }

    func testKillPortLooksUpListenersOnly() {
        let arguments = TerminatePortAction.lookupArguments(port: 3000)
        XCTAssertTrue(arguments.contains("-sTCP:LISTEN"))
        XCTAssertTrue(arguments.contains("-iTCP:3000"))
    }

    func testKillPortNeverTargetsItsOwnProcess() {
        XCTAssertEqual(TerminatePortAction.targets(fromLookupOutput: "12\n34\n12\n\n", excluding: 34), ["12"])
    }

    func testAudioQueriesOfferEachDeviceOnlyForTheSideItHas() {
        XCTAssertEqual(MacUtilitiesProvider.audioKind(query: "input audio", hasInput: true, hasOutput: false), .input)
        XCTAssertNil(MacUtilitiesProvider.audioKind(query: "input audio", hasInput: false, hasOutput: true))
        XCTAssertEqual(MacUtilitiesProvider.audioKind(query: "audio", hasInput: true, hasOutput: true), .output)
        XCTAssertNil(MacUtilitiesProvider.audioKind(query: "audio", hasInput: true, hasOutput: false))
        XCTAssertEqual(MacUtilitiesProvider.audioKind(query: "mic", hasInput: true, hasOutput: true), .input)
    }

    func testKillRowsNameAppsWithSpacesAndSkipUnreadablePIDs() async {
        let provider = MacUtilitiesProvider(processSnapshotProvider: FixedProcesses(rows: [
            ProcessInfoRow(pid: "4242", startedAt: nil, args: "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
                executablePath: "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"),
            ProcessInfoRow(pid: "not-a-pid", startedAt: nil, args: "/Applications/Google Drive.app/Contents/MacOS/Google Drive")
        ]))

        let results = await provider.results(matching: "kill google")

        XCTAssertEqual(results.filter { $0.id.hasPrefix("mac.kill.") }.map(\.title), ["Kill Google Chrome"])
    }
}

private struct FixedProcesses: ProcessSnapshotProviding {
    let rows: [ProcessInfoRow]
    func capture() -> [ProcessInfoRow] { rows }
}
