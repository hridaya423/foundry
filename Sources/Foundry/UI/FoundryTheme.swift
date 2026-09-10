import AppKit
import SwiftUI

enum FoundryMaterialRendering: Equatable {
    case nativeGlass
    case legacyVisualEffect
    case opaque
}

enum FoundryMaterialPolicy {
    static func rendering(osMajorVersion: Int, reduceTransparency: Bool) -> FoundryMaterialRendering {
        if reduceTransparency { return .opaque }
        return osMajorVersion >= 26 ? .nativeGlass : .legacyVisualEffect
    }

    static func currentRendering(reduceTransparency: Bool) -> FoundryMaterialRendering {
        rendering(
            osMajorVersion: ProcessInfo.processInfo.operatingSystemVersion.majorVersion,
            reduceTransparency: reduceTransparency
        )
    }
}

enum FoundryTheme {
    static let background = Color.clear
    static let surface = Color.clear
    static let surfaceElevated = Color.primary.opacity(0.075)
    static let panel = Color.black.opacity(0.10)
    static let selection = Color.primary.opacity(0.10)
    static let selectionBorder = Color.primary.opacity(0.16)
    static let hover = Color.primary.opacity(0.055)
    static let keycap = Color.primary.opacity(0.10)
    static let keycapBorder = Color.primary.opacity(0.10)
    static let border = Color.primary.opacity(0.20)
    static let accent = Color.primary.opacity(0.92)
    static let prominentControlFill = Color.primary.opacity(0.92)
    static let prominentControlText = Color(nsColor: .controlBackgroundColor)
    static let textOnDarkSurface = Color.white.opacity(0.97)
    static let accentTint = Color(red: 0.42, green: 0.66, blue: 1.0)
    static let success = Color(red: 0.42, green: 0.86, blue: 0.66)
    static let warning = Color(red: 1.0, green: 0.72, blue: 0.34)
    static let error = Color(red: 1.0, green: 0.42, blue: 0.45)
    static let primaryText = Color.primary.opacity(0.97)
    static let secondaryText = Color.primary.opacity(0.74)
    static let mutedText = Color.primary.opacity(0.56)
    static let faintText = Color.primary.opacity(0.44)
    static let glassHighlight = Color.primary.opacity(0.42)
    static let glassShadow = Color.black.opacity(0.36)

    enum Spacing {
        static let xxs: CGFloat = 4
        static let xs: CGFloat = 8
        static let sm: CGFloat = 12
        static let md: CGFloat = 16
        static let lg: CGFloat = 20
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
    }

    enum Radius {
        static let control: CGFloat = 10
        static let card: CGFloat = 16
        static let panel: CGFloat = 28
    }

    enum Control {
        static let compact: CGFloat = 30
        static let regular: CGFloat = 36
        static let large: CGFloat = 42
    }

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
