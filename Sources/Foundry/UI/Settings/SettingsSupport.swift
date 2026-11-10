import SwiftUI

enum SettingsCategory: String, CaseIterable, Identifiable {
    case general
    case commands
    case quicklinks
    case snippets
    case scripts
    case fileSearch
    case clipboard
    case browser
    case ai
    case agents
    case widgets
    case permissions
    case advanced
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .commands: "Commands"
        case .quicklinks: "Quicklinks"
        case .snippets: "Snippets"
        case .scripts: "Scripts"
        case .fileSearch: "File Search"
        case .clipboard: "Clipboard"
        case .browser: "Browser"
        case .ai: "AI"
        case .agents: "Agents"
        case .widgets: "Home"
        case .permissions: "Permissions"
        case .advanced: "Advanced"
        case .about: "About"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .commands: "command"
        case .quicklinks: "link"
        case .snippets: "curlybraces"
        case .scripts: "terminal"
        case .fileSearch: "doc.text.magnifyingglass"
        case .clipboard: "doc.on.clipboard"
        case .browser: "safari"
        case .ai: "sparkles"
        case .agents: "sparkles.rectangle.stack"
        case .widgets: "house"
        case .permissions: "hand.raised"
        case .advanced: "wrench.and.screwdriver"
        case .about: "info.circle"
        }
    }
}

struct SettingsAnchor: ViewModifier {
    let id: String
    let highlighted: Bool

    func body(content: Content) -> some View {
        content
            .id(id)
            .overlay(
                RoundedRectangle(cornerRadius: FoundryTheme.Radius.overlay, style: .continuous)
                    .stroke(FoundryTheme.stroke, lineWidth: highlighted ? 2 : 0)
                    .allowsHitTesting(false)
            )
    }
}
