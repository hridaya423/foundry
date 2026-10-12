import SwiftUI

enum SettingsCategory: String, CaseIterable, Identifiable {
    case general
    case appearance
    case commands
    case quicklinks
    case scripts
    case clipboard
    case ai
    case agents
    case widgets
    case advanced
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .appearance: "Appearance"
        case .commands: "Commands"
        case .quicklinks: "Quicklinks"
        case .scripts: "Scripts"
        case .clipboard: "Clipboard"
        case .ai: "AI"
        case .agents: "Agents"
        case .widgets: "Home"
        case .advanced: "Advanced"
        case .about: "About"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .appearance: "circle.lefthalf.filled"
        case .commands: "command"
        case .quicklinks: "link"
        case .scripts: "terminal"
        case .clipboard: "doc.on.clipboard"
        case .ai: "sparkles"
        case .agents: "sparkles.rectangle.stack"
        case .widgets: "house"
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
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(FoundryTheme.stroke, lineWidth: highlighted ? 2 : 0)
                    .allowsHitTesting(false)
            )
    }
}
