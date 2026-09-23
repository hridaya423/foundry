import XCTest

@MainActor
func waitUntil(timeout: Duration = .seconds(3), file: StaticString = #filePath, line: UInt = #line, _ condition: () async -> Bool) async {
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
        if await condition() { return }
        try? await Task.sleep(for: .milliseconds(10))
    }
    XCTFail("Condition not met within \(timeout)", file: file, line: line)
}
