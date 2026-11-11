import AppKit
import SwiftUI
import XCTest
import FoundryServices
@testable import Foundry

@MainActor
final class OnboardingSnapshotTests: XCTestCase {
    func testRenderEveryStep() throws {
        // Renders always run the layout checks; set the dir to also keep the images.
        let dir = ProcessInfo.processInfo.environment["FOUNDRY_QA_SNAPSHOT_DIR"]
        let diagnostics = DiagnosticsService()
        let config = ConfigService(diagnostics: diagnostics, url: FileManager.default.temporaryDirectory.appendingPathComponent("foundry-snap-\(UUID().uuidString).json"))
        let registry = CommandRegistry(providers: [], usageRanking: UsageRankingStore.scratch(diagnostics), diagnostics: diagnostics, configService: config)
        let panel = CommandPanelState.isolated(registry: registry, actionRunner: ActionRunner.isolated(diagnostics: diagnostics), diagnostics: diagnostics, config: config)
        let state = OnboardingState(panel: panel, permissions: PermissionHealthState(accessibilityTrusted: { false }), localState: LocalStateStore(),
            importSources: { [ImportSource(kind: .alfred, available: 12), ImportSource(kind: .raycast)] }, appleIntelligence: { true },
            registerLoginItem: { _ in })
        FoundryTheme.Brand.registerFonts
        var progressTileRows: [OnboardingStep: CGFloat] = [:]
        for step in OnboardingStep.allCases {
            state.go(to: step)
            let window = NSWindow(contentRect: NSRect(origin: .zero, size: OnboardingView.size),
                                  styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
            window.appearance = NSAppearance(named: .darkAqua)
            window.titlebarAppearsTransparent = true
            // Hosted the way OnboardingWindowController does it.
            let controller = NSHostingController(rootView: OnboardingView(state: state, keyboard: KeyboardMirror(), opensImmediately: true))
            controller.sizingOptions = []
            window.contentViewController = controller
            window.contentMinSize = OnboardingView.size
            window.contentMaxSize = OnboardingView.size
            window.setContentSize(OnboardingView.size)
            let host = controller.view
            func capture() throws -> (rep: NSBitmapImageRep, tileRow: CGFloat?) {
                let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                host.cacheDisplay(in: host.bounds, to: rep)
                let scale = CGFloat(rep.pixelsWide) / host.bounds.width
                let row = (rep.pixelsHigh - Int(100 * scale)..<rep.pixelsHigh - Int(30 * scale)).first { y in
                    stride(from: Int(60 * scale), to: Int(126 * scale), by: Int(3 * scale)).contains { x in
                        guard let pixel = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { return false }
                        return pixel.redComponent > 0.8 && pixel.greenComponent < 0.55 && pixel.blueComponent < 0.35
                    }
                }
                return (rep, row.map { CGFloat($0) / scale })
            }
            RunLoop.main.run(until: Date().addingTimeInterval(dir == nil ? 0.2 : 2.5))
            for _ in 0..<40 where try capture().tileRow == nil {
                RunLoop.main.run(until: Date().addingTimeInterval(0.25))
            }
            RunLoop.main.run(until: Date().addingTimeInterval(0.8))
            let frame = try capture()
            let rep = frame.rep
            // The ground fills the whole window, titlebar included.
            for y in [4, rep.pixelsHigh - 4] {
                let edge = try XCTUnwrap(rep.colorAt(x: rep.pixelsWide / 2, y: y)?.usingColorSpace(.sRGB))
                XCTAssertGreaterThan(edge.brightnessComponent, 0.03, "\(step): bare window at y=\(y)")
            }
            progressTileRows[step] = frame.tileRow
            guard let dir else { continue }
            let name = "\(step.rawValue)-\(step).png"
            try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: dir).appendingPathComponent(name))
        }
        XCTAssertEqual(progressTileRows.count, OnboardingStep.allCases.count, "a step drew no progress tile")
        XCTAssertEqual(Set(progressTileRows.values).count, 1, "the progress tiles move between steps: \(progressTileRows)")
    }
}
