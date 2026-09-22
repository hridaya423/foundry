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
    static let selection = Color.primary.opacity(0.10)
    static let selectionBorder = Color.primary.opacity(0.16)
    static let hover = Color.primary.opacity(0.05)
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

    enum Spacing {
        static let xs: CGFloat = 8
        static let sm: CGFloat = 12
        static let md: CGFloat = 16
    }

    enum Radius {
        static let control: CGFloat = 8
        static let row: CGFloat = 10
        static let panel: CGFloat = 26
    }

    enum Control {
        static let compact: CGFloat = 30
    }

    static let searchFont = Font.system(size: 20, weight: .regular)
    static let rowTitleFont = Font.system(size: 13.5, weight: .medium)
    static let secondaryFont = Font.system(size: 12, weight: .regular)
    static let metaFont = Font.system(size: 11, weight: .medium)
    static let sectionHeaderFont = Font.system(size: 11, weight: .semibold)

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
