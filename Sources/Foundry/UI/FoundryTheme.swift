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

/// SwiftUI exposes no macOS environment key for Increase Contrast, so Foundry
/// carries its own: `FoundryIncreaseContrastRoot` feeds
/// `NSWorkspace.accessibilityDisplayShouldIncreaseContrast` into the tree and
/// keeps it live off `accessibilityDisplayOptionsDidChangeNotification`.
private enum FoundryIncreaseContrastKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var foundryIncreaseContrast: Bool {
        get { self[FoundryIncreaseContrastKey.self] }
        set { self[FoundryIncreaseContrastKey.self] = newValue }
    }
}

struct FoundryIncreaseContrastRoot<Content: View>: View {
    @State private var increaseContrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
    @ViewBuilder var content: Content

    var body: some View {
        content
            .environment(\.foundryIncreaseContrast, increaseContrast)
            .onReceive(NotificationCenter.default.publisher(for: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification)) { _ in
                increaseContrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
            }
    }
}

/// The whole visual vocabulary: a six-style text ramp, a glyph scale for
/// SF Symbols and emoji, semantic colours over dynamic system colours, and
/// the 4/8/12/16/24 spacing scale. `lint-design.sh` keeps raw `.system(size:`,
/// `Color(red:` and `opacity(0.` literals out of every other file.
enum FoundryTheme {
    // MARK: Type ramp — exactly six text styles, 11 pt minimum

    /// 20/regular — panel title, search field, display readouts.
    static let title = Font.system(size: 20, weight: .regular)
    /// 13/medium — row titles and primary controls.
    static let body = Font.system(size: 13, weight: .medium)
    /// 13/regular — subtitles and secondary controls.
    static let bodySecondary = Font.system(size: 13, weight: .regular)
    /// 11/medium — metadata, badges, section headers.
    static let caption = Font.system(size: 11, weight: .medium)
    /// 11/semibold — the smallest emphasis (kicker labels).
    static let micro = Font.system(size: 11, weight: .semibold)
    /// 12/regular monospaced — code, paths, hotkey hints.
    static let mono = Font.system(size: 12, weight: .regular, design: .monospaced)

    /// Glyph sizing for SF Symbols and emoji — not text, so it lives outside
    /// the ramp. Everything else uses one of the six text styles above.
    enum Glyph {
        static let xs = Font.system(size: 10)
        static let sm = Font.system(size: 14)
        static let md = Font.system(size: 18)
        static let lg = Font.system(size: 24)
        static let xl = Font.system(size: 30)
        static let hero = Font.system(size: 44)
    }

    /// Computed glyph size (e.g. an initial scaled to its icon box) — the
    /// only sanctioned non-fixed `.system(size:)` outside the six-style ramp.
    static func glyph(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight)
    }

    // MARK: Semantic colours — dynamic system colours at tuned opacities

    static let textPrimary = Color.primary.opacity(0.97)
    static let textSecondary = Color.primary.opacity(0.74)
    static let textTertiary = Color.primary.opacity(0.56)
    static let textQuaternary = Color.primary.opacity(0.44)

    /// Barely-there wash for resting surfaces.
    static let fillSubtle = Color.primary.opacity(0.04)
    /// Pointer hover feedback.
    static let fillHover = Color.primary.opacity(0.06)
    /// Active-but-unselected tint (tags, chips).
    static let fillTint = Color.primary.opacity(0.08)
    /// The selected row — fill only, no border.
    static let fillSelected = Color.primary.opacity(0.10)
    /// Hairlines between rows and surfaces.
    static let separator = Color.primary.opacity(0.12)
    /// The strongest neutral fill (pressed controls, drop zones).
    static let fillEmphasis = Color.primary.opacity(0.14)
    /// Visible borders around floating surfaces.
    static let stroke = Color.primary.opacity(0.18)

    static let destructive = Color(red: 1.0, green: 0.42, blue: 0.45)
    static let success = Color(red: 0.42, green: 0.86, blue: 0.66)
    static let warning = Color(red: 1.0, green: 0.72, blue: 0.34)
    static let accent = Color(red: 0.42, green: 0.66, blue: 1.0)

    /// Accent at supporting strength — tint chips, selected states.
    static let accentSubtle = accent.opacity(0.10)
    static let accentTintFill = accent.opacity(0.13)
    static let accentStrong = accent.opacity(0.75)

    /// Dim wash behind floating UI (alerts-on-panel).
    static let scrim = Color.black.opacity(0.20)
    /// Heavier dim for modal-on-modal moments.
    static let scrimStrong = Color.black.opacity(0.50)
    /// Drop shadows.
    static let shadow = Color.black.opacity(0.28)
    /// Hairline/secondary marks on dark surfaces.
    static let onDarkFaint = Color.white.opacity(0.12)
    static let onDarkSubtle = Color.white.opacity(0.26)

    /// Computed dark/light alpha — e.g. `dark(0.46 * intensity)` — for the
    /// rare site whose alpha is derived rather than constant.
    static func dark(_ alpha: Double) -> Color { Color.black.opacity(alpha) }
    static func light(_ alpha: Double) -> Color { Color.white.opacity(alpha) }
    static func primary(_ alpha: Double) -> Color { Color.primary.opacity(alpha) }

    /// Named opacity constants for `Color`/view `.opacity(_:)` calls whose
    /// receiver is a variable — `level.tint.opacity(FoundryTheme.Alpha.tint)` and friends.
    enum Alpha {
        static let subtle: Double = 0.10
        static let tint: Double = 0.13
        static let half: Double = 0.5
        static let strong: Double = 0.75
        static let faint: Double = 0.95
    }

    /// Foundry's brand orange — wordmark glow, celebration accents.
    static let brand = Color(red: 0.98, green: 0.39, blue: 0.16)
    /// The confetti palette, tuned to read on both dark and light glass.
    static let confettiColors: [Color] = [
        brand,
        Color(red: 1.00, green: 0.62, blue: 0.23),
        Color(red: 1.00, green: 0.84, blue: 0.35),
        Color(red: 0.42, green: 0.76, blue: 0.53),
        Color(red: 0.45, green: 0.62, blue: 0.97),
        Color(red: 0.80, green: 0.55, blue: 0.97),
        Color(red: 1.00, green: 0.56, blue: 0.66),
    ]

    /// Near-solid primary for the one prominent control per surface.
    static let prominentControlFill = Color.primary.opacity(0.92)
    static let prominentControlText = Color(nsColor: .controlBackgroundColor)
    static let textOnDarkSurface = Color.white.opacity(0.97)

    // MARK: Spacing — 4/8/12/16/24

    enum Spacing {
        static let xxs: CGFloat = 4
        static let xs: CGFloat = 8
        static let sm: CGFloat = 12
        static let md: CGFloat = 16
        static let lg: CGFloat = 24
    }

    // MARK: Radii — 6 badge, 8 control, 10 row, 14 overlay, 26 panel

    enum Radius {
        static let badge: CGFloat = 6
        static let control: CGFloat = 8
        static let row: CGFloat = 10
        static let overlay: CGFloat = 14
        static let panel: CGFloat = 26
    }

    enum Control {
        static let compact: CGFloat = 30
    }
}

extension AgentSessionStatus {
    /// The one agent-status palette — previously duplicated in the shelf and
    /// the home accessory strip.
    var color: Color {
        switch self {
        case .working, .running: Color(red: 0.42, green: 0.90, blue: 0.67)
        case .needsInput: FoundryTheme.warning
        case .reviewReady: Color(red: 0.52, green: 0.72, blue: 1.0)
        case .planning: Color(red: 0.70, green: 0.62, blue: 1.0)
        case .completed: Color(red: 0.44, green: 0.72, blue: 1.0)
        case .failed: FoundryTheme.destructive
        case .idle, .recent: FoundryTheme.textQuaternary
        }
    }
}
