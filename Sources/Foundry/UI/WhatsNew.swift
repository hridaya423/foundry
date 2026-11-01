import Foundation

enum WhatsNew {
    static let version = "1.3"
    static var summary: String {
        String(localized: "New: ⌘1 to ⌘8 open your favorites. Hold ⌘ on Home to see which is which.")
    }

    static func shouldShow(configExistedAtLaunch: Bool, seenVersion: String?) -> Bool {
        configExistedAtLaunch && seenVersion != version
    }
}
