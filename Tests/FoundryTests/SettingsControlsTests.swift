import AppKit
import SwiftUI
import XCTest
@testable import Foundry

@MainActor
final class SettingsControlsTests: XCTestCase {
    private func checkboxNames(in view: some View) -> [String] {
        let host = NSHostingView(rootView: view.frame(width: 300, height: 200))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 200), styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        // SwiftUI builds its accessibility tree only once an assistive client asks for the enhanced interface.
        let enhance = NSSelectorFromString("accessibilitySetValue:forAttribute:")
        NSApplication.shared.perform(enhance, with: true, with: "AXEnhancedUserInterface")
        defer { NSApplication.shared.perform(enhance, with: false, with: "AXEnhancedUserInterface") }
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        func names(_ element: Any) -> [String] {
            let object = element as AnyObject
            var own: [String] = []
            if (object.accessibilityRole?() as NSAccessibility.Role?) == .checkBox {
                let titled = (object.accessibilityTitleUIElement?() as Any?).flatMap { (($0 as AnyObject).accessibilityValue?() as Any?) as? String }
                own = [(object.accessibilityLabel?() as String?) ?? titled ?? ""]
            }
            return own + ((object.accessibilityChildren?() as [Any]?) ?? []).flatMap(names)
        }
        return names(host)
    }

    func testEverySwitchAndCheckboxIsNamedForVoiceOver() {
        let names = checkboxNames(in: VStack {
            Toggle("Trusted", isOn: .constant(true)).toggleStyle(FoundrySwitchStyle())
            Toggle("", isOn: .constant(false)).labelsHidden().toggleStyle(FoundrySwitchStyle()).accessibilityLabel(Text("Haptic feedback"))
            Toggle("Space", isOn: .constant(true)).toggleStyle(FoundryCheckboxStyle())
        })
        XCTAssertEqual(names, ["Trusted", "Haptic feedback", "Space"])
    }
}
