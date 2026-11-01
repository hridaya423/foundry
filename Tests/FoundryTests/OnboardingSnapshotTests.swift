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
        let registry = CommandRegistry(providers: [], usageRanking: UsageRankingStore(diagnostics: diagnostics), diagnostics: diagnostics, configService: config)
        let panel = CommandPanelState(registry: registry, actionRunner: ActionRunner(diagnostics: diagnostics), diagnostics: diagnostics, config: config)
        let state = OnboardingState(panel: panel, permissions: PermissionHealthState(accessibilityTrusted: { false }), localState: LocalStateStore())
        FoundryTheme.Brand.registerFonts
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
            RunLoop.main.run(until: Date().addingTimeInterval(dir == nil ? 0.2 : 2.5))
            let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: rep)
            // The ground fills the whole window, titlebar included.
            for y in [4, rep.pixelsHigh - 4] {
                let edge = try XCTUnwrap(rep.colorAt(x: rep.pixelsWide / 2, y: y)?.usingColorSpace(.sRGB))
                XCTAssertGreaterThan(edge.brightnessComponent, 0.03, "\(step): bare window at y=\(y)")
            }
            guard let dir else { continue }
            let name = "\(step.rawValue)-\(step).png"
            try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: dir).appendingPathComponent(name))
        }
    }
}
