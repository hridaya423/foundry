import XCTest
@testable import Foundry
import FoundryDomain

final class WindowManagerTests: XCTestCase {
    private let foundryPID: pid_t = 100
    private let safariPID: pid_t = 200
    private let terminalPID: pid_t = 300

    func testFrontmostExternalAppIsTheTarget() {
        XCTAssertEqual(
            NativeWindowManager.resolvedTargetPID(frontmostPID: safariPID, ownPID: foundryPID, lastExternalPID: terminalPID),
            safariPID
        )
    }

    func testPanelOpenFallsBackToLastExternalApp() {
        XCTAssertEqual(
            NativeWindowManager.resolvedTargetPID(frontmostPID: foundryPID, ownPID: foundryPID, lastExternalPID: safariPID),
            safariPID
        )
    }

    func testFallbackIgnoresAMemoryOfFoundryItself() {
        XCTAssertEqual(
            NativeWindowManager.resolvedTargetPID(frontmostPID: nil, ownPID: foundryPID, lastExternalPID: foundryPID),
            nil
        )
    }

    func testNoExternalAppToControlReturnsNil() {
        XCTAssertEqual(
            NativeWindowManager.resolvedTargetPID(frontmostPID: foundryPID, ownPID: foundryPID, lastExternalPID: nil),
            nil
        )
        XCTAssertEqual(
            NativeWindowManager.resolvedTargetPID(frontmostPID: nil, ownPID: foundryPID, lastExternalPID: nil),
            nil
        )
    }

    func testAXFrameConvertsToAppKitYUpCoordinates() {
        let axFrame = CGRect(x: 100, y: 50, width: 300, height: 200)
        let appKit = NativeWindowManager.appkitFrame(fromAX: axFrame, anchorHeight: 900)
        XCTAssertEqual(appKit, CGRect(x: 100, y: 650, width: 300, height: 200))
    }

    func testAppKitFrameConvertsToAXYDownCoordinates() {
        let appKit = CGRect(x: 100, y: 650, width: 300, height: 200)
        let ax = NativeWindowManager.axFrame(fromAppKit: appKit, anchorHeight: 900)
        XCTAssertEqual(ax, CGRect(x: 100, y: 50, width: 300, height: 200))
    }

    func testSizeConstrainedWindowIsAcceptedWhenItsAXTopLeftAnchorMatches() {
        let requested = CGRect(x: 6, y: 39, width: 858, height: 971)
        let vscodeResult = CGRect(x: 6, y: 39, width: 858, height: 964)

        XCTAssertTrue(
            NativeWindowManager.isAcceptableConstrainedFrame(
                vscodeResult,
                targetAXFrame: requested
            )
        )
    }

    func testCoordinateConversionRoundTrips() {
        let original = CGRect(x: 50, y: 120, width: 400, height: 300)
        let roundTripped = NativeWindowManager.axFrame(
            fromAppKit: NativeWindowManager.appkitFrame(fromAX: original, anchorHeight: 1117),
            anchorHeight: 1117
        )
        XCTAssertEqual(roundTripped, original)
    }

    func testEngineTopHalfLandsAtTheTopInAXCoordinates() {
        let visible = CGRect(x: 0, y: 0, width: 1000, height: 700)
        let options = WindowLayoutOptions(gap: 0, nudgeDistance: 10, resizeStep: 10, minimumSize: CGSize(width: 200, height: 140))
        let topHalf = WindowLayoutEngine.frame(for: .topHalf, currentFrame: CGRect(x: 100, y: 100, width: 400, height: 300), visibleFrame: visible, options: options)!
        let axFrame = NativeWindowManager.axFrame(fromAppKit: topHalf, anchorHeight: 700)
        XCTAssertEqual(axFrame.minY, 0, accuracy: 0.001, "top half should be at the top of the screen in AX space")
    }

    func testEngineBottomRightBecomesBottomInAXCoordinates() {
        let visible = CGRect(x: 0, y: 0, width: 1000, height: 700)
        let options = WindowLayoutOptions(gap: 0, nudgeDistance: 10, resizeStep: 10, minimumSize: CGSize(width: 200, height: 140))
        let bottomRight = WindowLayoutEngine.frame(for: .bottomRight, currentFrame: CGRect(x: 100, y: 100, width: 400, height: 300), visibleFrame: visible, options: options)!
        let axFrame = NativeWindowManager.axFrame(fromAppKit: bottomRight, anchorHeight: 700)
        XCTAssertEqual(axFrame.minY, visible.maxY - visible.height / 2, accuracy: 0.001, "bottom-right should sit in the lower half (large AX y)")
        XCTAssertEqual(axFrame.minX, 500, accuracy: 0.001)
    }

    func testAccessibilityFallbackIdentityDoesNotDependOnWindowTitle() {
        XCTAssertEqual(
            WindowIdentity.accessibilityElement(pid: safariPID, elementHash: 42),
            WindowIdentity(pid: safariPID, windowNumber: "ax:42")
        )
    }

    func testWindowElementCacheRetainsTheDiscoveredElementForFrameApplication() {
        var cache = WindowElementCache<String>()
        let identity = WindowIdentity.accessibilityElement(pid: safariPID, elementHash: 42)

        cache.store("focused-window", for: identity)

        XCTAssertEqual(cache.element(for: identity), "focused-window")
    }

    func testWindowElementCacheReplacesStaleElementsForTheSameProcess() {
        var cache = WindowElementCache<String>()
        let stale = WindowIdentity.accessibilityElement(pid: safariPID, elementHash: 41)
        let current = WindowIdentity.accessibilityElement(pid: safariPID, elementHash: 42)
        cache.store("stale", for: stale)

        cache.store("current", for: current)

        XCTAssertNil(cache.element(for: stale))
        XCTAssertEqual(cache.element(for: current), "current")
    }

    func testRestoreStoreDoesNotCreateHistoryWhenReading() {
        var store = WindowRestoreStore()
        let identity = WindowIdentity(pid: 200, windowNumber: "42")
        XCTAssertNil(store.frame(for: identity))
        XCTAssertNil(store.removeFrame(for: identity))
    }

    func testRestoreStoreKeepsWindowsInOneProcessSeparate() {
        var store = WindowRestoreStore()
        let first = WindowIdentity(pid: 200, windowNumber: "42")
        let second = WindowIdentity(pid: 200, windowNumber: "43")
        store.save(CGRect(x: 10, y: 20, width: 300, height: 200), for: first)
        store.save(CGRect(x: 50, y: 60, width: 400, height: 300), for: second)

        XCTAssertEqual(store.frame(for: first), CGRect(x: 10, y: 20, width: 300, height: 200))
        XCTAssertEqual(store.frame(for: second), CGRect(x: 50, y: 60, width: 400, height: 300))
    }

    func testRestoreStoreTracksTheMostRecentWindowChange() {
        var store = WindowRestoreStore()
        let identity = WindowIdentity(pid: 200, windowNumber: "42")
        store.save(CGRect(x: 10, y: 20, width: 300, height: 200), for: identity)
        store.save(CGRect(x: 50, y: 60, width: 400, height: 300), for: identity)

        XCTAssertEqual(store.frame(for: identity), CGRect(x: 50, y: 60, width: 400, height: 300))
    }

    func testWindowFrameRoundTripUsesOneCoordinateSpace() {
        let appKit = CGRect(x: 140, y: 260, width: 500, height: 320)
        let ax = NativeWindowManager.axFrame(fromAppKit: appKit, anchorHeight: 900)
        XCTAssertEqual(NativeWindowManager.appkitFrame(fromAX: ax, anchorHeight: 900), appKit)
    }

    @MainActor
    func testRestoreWithoutHistoryDoesNotWriteToTheWindow() async {
        let client = FakeWindowAccessibilityClient()
        let manager = NativeWindowManager(
            accessibility: client,
            trustProvider: { true },
            targetProvider: { 200 }
        )

        let result = await manager.apply(.restore)
        let setCount = await client.setCount()

        XCTAssertEqual(result, .failed("No previous frame to restore"))
        XCTAssertEqual(setCount, 0)
    }

    private actor FakeWindowAccessibilityClient: WindowAccessibilityClient {
        private var writes = 0

        func window(for pid: pid_t, anchorHeight: CGFloat) async -> AXWindowSnapshot? {
            AXWindowSnapshot(
                identity: WindowIdentity(pid: pid, windowNumber: "window"),
                frame: CGRect(x: 100, y: 100, width: 500, height: 400),
                canMove: true,
                canResize: true
            )
        }

        func setFrame(_ frame: CGRect, for identity: WindowIdentity, anchorHeight: CGFloat) async -> WindowFrameApplicationResult {
            writes += 1
            return .applied(frame)
        }

        func setCount() -> Int {
            writes
        }
    }
}
