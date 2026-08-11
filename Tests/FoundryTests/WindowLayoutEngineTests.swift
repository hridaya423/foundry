import XCTest
import FoundryDomain

final class WindowLayoutEngineTests: XCTestCase {
    private let visibleFrame = CGRect(x: 0, y: 0, width: 1000, height: 700)

    private var clearOptions: WindowLayoutOptions {
        WindowLayoutOptions(
            gap: 0,
            nudgeDistance: 10,
            resizeStep: 10,
            minimumSize: CGSize(width: 200, height: 140)
        )
    }

    func testHalvesPartitionTheScreen() {
        assertFrame(for: .leftHalf, equals: CGRect(x: 0, y: 0, width: 500, height: 700))
        assertFrame(for: .rightHalf, equals: CGRect(x: 500, y: 0, width: 500, height: 700))
        assertFrame(for: .topHalf, equals: CGRect(x: 0, y: 350, width: 1000, height: 350))
        assertFrame(for: .bottomHalf, equals: CGRect(x: 0, y: 0, width: 1000, height: 350))
    }

    func testQuartersPartitionTheScreen() {
        assertFrame(for: .topLeft, equals: CGRect(x: 0, y: 350, width: 500, height: 350))
        assertFrame(for: .topRight, equals: CGRect(x: 500, y: 350, width: 500, height: 350))
        assertFrame(for: .bottomLeft, equals: CGRect(x: 0, y: 0, width: 500, height: 350))
        assertFrame(for: .bottomRight, equals: CGRect(x: 500, y: 0, width: 500, height: 350))
    }

    func testThirdsPartitionTheScreen() {
        assertFrame(for: .leftThird, equals: CGRect(x: 0, y: 0, width: 333.333, height: 700))
        assertFrame(for: .centerThird, equals: CGRect(x: 333.333, y: 0, width: 333.333, height: 700))
        assertFrame(for: .rightThird, equals: CGRect(x: 666.667, y: 0, width: 333.333, height: 700))
    }

    func testMaximizeFillsTheVisibleFrame() {
        assertFrame(for: .maximize, equals: visibleFrame)
    }

    func testCenterKeepsSizeButCentersOrigin() {
        let current = CGRect(x: 100, y: 200, width: 400, height: 300)
        assertFrame(for: .center, currentFrame: current, equals: CGRect(x: 300, y: 200, width: 400, height: 300))
    }

    func testCenterClampsOversizedWindowsToTheScreen() {
        let current = CGRect(x: 100, y: 150, width: 2000, height: 1500)
        assertFrame(for: .center, currentFrame: current, equals: visibleFrame)
    }

    func testGrowEnlargesAroundTheCenter() {
        let current = CGRect(x: 100, y: 150, width: 600, height: 400)
        assertFrame(for: .increaseSize, currentFrame: current, equals: CGRect(x: 95, y: 145, width: 610, height: 410))
    }

    func testShrinkReducesAroundTheCenter() {
        let current = CGRect(x: 100, y: 150, width: 600, height: 400)
        assertFrame(for: .decreaseSize, currentFrame: current, equals: CGRect(x: 105, y: 155, width: 590, height: 390))
    }

    func testGrowStopsAtScreenBounds() {
        var options = clearOptions
        options.resizeStep = 200
        let current = CGRect(x: 0, y: 0, width: 900, height: 600)
        assertFrame(for: .increaseSize, currentFrame: current, options: options, equals: visibleFrame)
    }

    func testShrinkStopsAtMinimumSize() {
        var options = clearOptions
        options.resizeStep = 500
        let current = CGRect(x: 100, y: 150, width: 400, height: 300)
        assertFrame(for: .decreaseSize, currentFrame: current, options: options, equals: CGRect(x: 200, y: 230, width: 200, height: 140))
    }

    func testNudgesMoveByFixedDistance() {
        let current = CGRect(x: 100, y: 100, width: 400, height: 300)
        assertFrame(for: .nudgeLeft, currentFrame: current, equals: CGRect(x: 90, y: 100, width: 400, height: 300))
        assertFrame(for: .nudgeRight, currentFrame: current, equals: CGRect(x: 110, y: 100, width: 400, height: 300))
        assertFrame(for: .nudgeUp, currentFrame: current, equals: CGRect(x: 100, y: 110, width: 400, height: 300))
        assertFrame(for: .nudgeDown, currentFrame: current, equals: CGRect(x: 100, y: 90, width: 400, height: 300))
    }

    func testNudgeIsClampedToTheVisibleFrame() {
        let current = CGRect(x: 0, y: 0, width: 400, height: 300)
        assertFrame(for: .nudgeLeft, currentFrame: current, equals: current)
        assertFrame(for: .nudgeDown, currentFrame: current, equals: current)
    }

    func testDefaultGapInsetsAllPlacements() {
        let visible = CGRect(x: 0, y: 0, width: 1000, height: 700)
        assertFrame(for: .maximize, visibleFrame: visible, options: .default, equals: CGRect(x: 6, y: 6, width: 988, height: 688))
        assertFrame(for: .leftHalf, visibleFrame: visible, options: .default, equals: CGRect(x: 6, y: 6, width: 494, height: 688))
        assertFrame(for: .rightHalf, visibleFrame: visible, options: .default, equals: CGRect(x: 500, y: 6, width: 494, height: 688))
    }

    func testDegenerateVisibleFramesReturnNoPlacement() {
        XCTAssertNil(WindowLayoutEngine.frame(
            for: .leftHalf,
            currentFrame: CGRect(x: 0, y: 0, width: 100, height: 100),
            visibleFrame: CGRect(x: 0, y: 0, width: 10, height: 10)
        ))
        XCTAssertNil(WindowLayoutEngine.frame(
            for: .center,
            currentFrame: CGRect(x: 0, y: 0, width: 100, height: 100),
            visibleFrame: CGRect(x: 0, y: 0, width: 0.5, height: 0.5),
            options: clearOptions
        ))
    }

    func testManagerHandledPlacementsAreNotComputedByTheEngine() {
        for placement in [WindowPlacement.nextDisplay, .previousDisplay, .restore] {
            XCTAssertNil(WindowLayoutEngine.frame(
                for: placement,
                currentFrame: CGRect(x: 100, y: 100, width: 400, height: 300),
                visibleFrame: visibleFrame
            ))
        }
    }

    func testEveryPlacementResolvesToAnEngineFrameExactlyWhenNotManagerHandled() {
        for placement in WindowPlacement.allCases {
            let frame = WindowLayoutEngine.frame(
                for: placement,
                currentFrame: CGRect(x: 100, y: 100, width: 400, height: 300),
                visibleFrame: visibleFrame
            )
            if placement.isManagerHandled {
                XCTAssertNil(frame, "\(placement) should be resolved by the window manager, not the engine")
            } else {
                XCTAssertNotNil(frame, "\(placement) should resolve to a frame")
                if let frame {
                    XCTAssertTrue(visibleFrame.contains(frame), "\(placement) frame \(frame) escapes \(visibleFrame)")
                }
            }
        }
    }

    func testHomeDefaultsPrioritizeCommonPlacements() {
        XCTAssertEqual(WindowPlacement.homeDefaults, [.leftHalf, .rightHalf, .topHalf, .maximize, .center, .restore])
    }

    func testLayoutGroupsCoverEveryPlacementOnceInUserFacingOrder() {
        let grouped = WindowLayoutGroup.allCases.flatMap(\.placements)

        XCTAssertEqual(grouped.count, WindowPlacement.allCases.count)
        XCTAssertEqual(Set(grouped), Set(WindowPlacement.allCases))
        XCTAssertEqual(WindowLayoutGroup.common.placements, [.leftHalf, .rightHalf, .maximize, .restore])
        XCTAssertEqual(WindowLayoutGroup.quarters.placements, [.topLeft, .topRight, .bottomLeft, .bottomRight])
        XCTAssertEqual(WindowLayoutGroup.displays.placements, [.nextDisplay, .previousDisplay])
    }

    func testEachPlacementBelongsToOneLayoutGroup() {
        for placement in WindowPlacement.allCases {
            XCTAssertEqual(WindowLayoutGroup.allCases.filter { $0.placements.contains(placement) }.count, 1, "Unexpected group count for \(placement)")
        }
    }

    func testWindowLayoutOverviewKeywordsAreExactAndComplete() {
        for keyword in ["tile", "window", "windows", "layout", "layouts", "snap"] {
            XCTAssertTrue(WindowLayoutQuery.isOverview(keyword))
        }
        XCTAssertFalse(WindowLayoutQuery.isOverview("tile right"))
        XCTAssertFalse(WindowLayoutQuery.isOverview("window manager"))
    }

    func testDisplayMoveFitsTheWindowInsideTheDestinationVisibleFrame() {
        let source = CGRect(x: 100, y: 100, width: 1400, height: 900)
        let destination = CGRect(x: 1200, y: 0, width: 1000, height: 700)

        XCTAssertEqual(
            WindowDisplayLayout.moveFrame(source, to: destination),
            CGRect(x: 1200, y: 0, width: 1000, height: 700)
        )
    }

    func testDisplayMovePreservesRelativeOriginWhenWindowFits() {
        let source = CGRect(x: 100, y: 100, width: 500, height: 400)
        let destination = CGRect(x: 1200, y: 50, width: 1400, height: 900)

        XCTAssertEqual(
            WindowDisplayLayout.moveFrame(source, to: destination),
            CGRect(x: 1200, y: 100, width: 500, height: 400)
        )
    }

    func testNextDisplayPrefersTheNearestDisplayToTheRight() {
        let screens = [
            CGRect(x: 0, y: 0, width: 1200, height: 800),
            CGRect(x: 1200, y: 200, width: 1000, height: 700),
            CGRect(x: 0, y: 800, width: 1200, height: 800)
        ]

        XCTAssertEqual(WindowDisplayLayout.nextDisplayIndex(from: 0, screens: screens, direction: .next), 1)
    }

    func testPreviousDisplayPrefersTheNearestDisplayToTheLeft() {
        let screens = [
            CGRect(x: 0, y: 0, width: 1200, height: 800),
            CGRect(x: 1200, y: 200, width: 1000, height: 700),
            CGRect(x: 0, y: 800, width: 1200, height: 800)
        ]

        XCTAssertEqual(WindowDisplayLayout.nextDisplayIndex(from: 1, screens: screens, direction: .previous), 0)
    }

    private func assertFrame(
        for placement: WindowPlacement,
        currentFrame: CGRect = CGRect(x: 100, y: 100, width: 400, height: 300),
        visibleFrame: CGRect? = nil,
        options: WindowLayoutOptions? = nil,
        equals expected: CGRect,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let actual = WindowLayoutEngine.frame(
            for: placement,
            currentFrame: currentFrame,
            visibleFrame: visibleFrame ?? self.visibleFrame,
            options: options ?? clearOptions
        )
        guard let actual else {
            XCTFail("\(placement) returned no frame", file: file, line: line)
            return
        }
        XCTAssertEqual(actual.origin.x, expected.origin.x, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(actual.origin.y, expected.origin.y, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(actual.size.width, expected.size.width, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(actual.size.height, expected.size.height, accuracy: 0.001, file: file, line: line)
    }
}
