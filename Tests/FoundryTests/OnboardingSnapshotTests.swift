import AppKit
import SwiftUI
import XCTest
import FoundryServices
@testable import Foundry

@MainActor
final class OnboardingSnapshotTests: XCTestCase {
    func testRenderEveryStep() throws {
        guard let dir = ProcessInfo.processInfo.environment["FOUNDRY_QA_SNAPSHOT_DIR"] else { throw XCTSkip("snapshot dir not set") }
        let diagnostics = DiagnosticsService()
        let config = ConfigService(diagnostics: diagnostics, url: FileManager.default.temporaryDirectory.appendingPathComponent("foundry-snap-\(UUID().uuidString).json"))
        let registry = CommandRegistry(providers: [], usageRanking: UsageRankingStore(diagnostics: diagnostics), diagnostics: diagnostics, configService: config)
        let panel = CommandPanelState(registry: registry, actionRunner: ActionRunner(diagnostics: diagnostics), diagnostics: diagnostics, config: config)
        let state = OnboardingState(panel: panel, permissions: PermissionHealthState(accessibilityTrusted: { false }), defaults: UserDefaults(suiteName: UUID().uuidString)!)
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            for step in OnboardingStep.allCases {
                state.go(to: step)
                let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 460), styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
                window.appearance = NSAppearance(named: appearance)
                window.titlebarAppearsTransparent = true
                let host = NSHostingView(rootView: OnboardingView(state: state))
                host.frame = window.contentLayoutRect
                window.contentView = host
                RunLoop.main.run(until: Date().addingTimeInterval(0.15))
                let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                host.cacheDisplay(in: host.bounds, to: rep)
                let name = "\(step.rawValue)-\(step)-\(appearance == .aqua ? "light" : "dark").png"
                try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: dir).appendingPathComponent(name))
            }
        }
    }
}
