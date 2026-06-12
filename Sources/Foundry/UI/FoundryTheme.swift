import SwiftUI

enum FoundryTheme {
    static let background = Color(red: 0.062, green: 0.064, blue: 0.071)
    static let surface = Color(red: 0.095, green: 0.098, blue: 0.108)
    static let surfaceElevated = Color(red: 0.128, green: 0.132, blue: 0.146)
    static let panel = Color(red: 0.112, green: 0.116, blue: 0.128)
    static let selection = Color.white.opacity(0.075)
    static let selectionBorder = Color.white.opacity(0.095)
    static let keycap = Color.white.opacity(0.070)
    static let border = Color.white.opacity(0.085)
    static let accent = Color(red: 0.94, green: 0.43, blue: 0.20)
    static let primaryText = Color.white.opacity(0.91)
    static let secondaryText = Color.white.opacity(0.54)
    static let mutedText = Color.white.opacity(0.34)

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
