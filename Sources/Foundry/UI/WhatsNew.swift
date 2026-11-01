import Foundation

enum WhatsNew {
    static let version = "1.2"
    static var summary: String {
        String(localized: """
            New in 1.2: drop files on the panel to convert them, Extract Text, Pick Color, QR codes, Paste as Plain Text, \
            and redesigned Clipboard, Snippets and Downloads.
            """)
    }

    static func shouldShow(configExistedAtLaunch: Bool, seenVersion: String?) -> Bool {
        configExistedAtLaunch && seenVersion != version
    }
}
