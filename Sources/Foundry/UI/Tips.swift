import Foundation

struct Tip: Equatable, Identifiable {
    let id: String
    let text: String

    static let all: [Tip] = [
        Tip(id: "actions", text: String(localized: "⌘K shows every action for the selected result.")),
        Tip(id: "ask-ai", text: String(localized: "Press Tab to ask AI about what you typed.")),
        Tip(id: "favorites", text: String(localized: "Hold ⌘ on Home to see which number opens each favorite.")),
        Tip(id: "calculate", text: String(localized: "Type a sum like 12*7 to calculate it, then press Return to copy.")),
        Tip(id: "clipboard", text: String(localized: "Type clip to see everything you copied.")),
    ]

    static let minimumLaunches = 5

    /// The tip for today: the one already shown today, else the next one never dismissed.
    static func today(launchCount: Int, day: String, shownDay: String?, shownID: String?, dismissed: Set<String>) -> Tip? {
        guard launchCount >= minimumLaunches else { return nil }
        if shownDay == day {
            return all.first { $0.id == shownID && dismissed.contains($0.id) == false }
        }
        return all.first { dismissed.contains($0.id) == false && $0.id != shownID }
    }
}
