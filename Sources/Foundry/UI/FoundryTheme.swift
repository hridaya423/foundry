import SwiftUI

enum FoundryTheme {
    static let background = Color.clear
    static let surface = Color.clear
    static let surfaceElevated = Color.white.opacity(0.075)
    static let panel = Color.black.opacity(0.10)
    static let selection = Color.white.opacity(0.095)
    static let selectionBorder = Color.white.opacity(0.16)
    static let keycap = Color.white.opacity(0.095)
    static let border = Color.white.opacity(0.20)
    static let accent = Color.white.opacity(0.92)
    static let primaryText = Color.white.opacity(0.94)
    static let secondaryText = Color.white.opacity(0.68)
    static let mutedText = Color.white.opacity(0.48)
    static let glassHighlight = Color.white.opacity(0.36)
    static let glassShadow = Color.black.opacity(0.36)

    static func display(size: CGFloat, weight: Font.Weight) -> Font {
        .system(size: size, weight: weight, design: .default)
    }

    static func body(size: CGFloat, weight: Font.Weight) -> Font {
        .system(size: size, weight: weight, design: .default)
    }

    static func mono(size: CGFloat, weight: Font.Weight) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}
