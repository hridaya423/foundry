import AppKit
import SwiftUI

enum FoundryTheme {
    static let background = Color.clear
    static let surface = Color.clear
    static let surfaceElevated = Color.white.opacity(0.075)
    static let panel = Color.black.opacity(0.10)
    static let selection = Color.white.opacity(0.10)
    static let selectionBorder = Color.white.opacity(0.16)
    static let hover = Color.white.opacity(0.055)
    static let keycap = Color.white.opacity(0.10)
    static let keycapBorder = Color.white.opacity(0.10)
    static let border = Color.white.opacity(0.20)
    static let accent = Color.white.opacity(0.92)
    static let primaryText = Color.white.opacity(0.95)
    static let secondaryText = Color.white.opacity(0.66)
    static let mutedText = Color.white.opacity(0.46)
    static let faintText = Color.white.opacity(0.36)
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

extension View {
    func pointerCursor() -> some View {
        onHover { hovering in
            if hovering {
                NSCursor.pointingHand.set()
            } else {
                NSCursor.arrow.set()
            }
        }
    }
}
