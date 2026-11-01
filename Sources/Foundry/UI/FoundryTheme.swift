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

/// The whole visual vocabulary: an eight-style text ramp, a glyph scale for
/// SF Symbols and emoji, semantic colours over dynamic system colours, and
/// the 4/8/12/16/24 spacing scale. `lint-design.sh` keeps raw `.system(size:`,
/// `Color(red:` and `opacity(0.` literals out of every other file.
enum FoundryTheme {
    // MARK: Type ramp — eight text styles, 11 pt minimum

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
    /// 13.5/medium — launcher result titles, as 1.1 shipped them.
    static let rowTitle = Font.system(size: 13.5, weight: .medium)
    /// 12/regular — the detail line and kind label under/beside a result.
    static let rowDetail = Font.system(size: 12, weight: .regular)

    /// Glyph sizing for SF Symbols and emoji — not text, so it lives outside
    /// the ramp. Everything else uses one of the text styles above.
    enum Glyph {
        static let xs = Font.system(size: 10)
        static let sm = Font.system(size: 14)
        static let md = Font.system(size: 18)
        static let lg = Font.system(size: 24)
        static let xl = Font.system(size: 30)
        static let hero = Font.system(size: 44)
    }

    /// The home widget strip keeps the 1.1 sizes (9–18 pt), denser than the
    /// ramp, because the user prefers how 1.1 looked.
    enum Strip {
        static func text(_ size: CGFloat, weight: Font.Weight) -> Font { .system(size: size, weight: weight) }
        static func mono(_ size: CGFloat, weight: Font.Weight) -> Font { .system(size: size, weight: weight, design: .monospaced) }
    }

    /// Computed glyph size (e.g. an initial scaled to its icon box) — the
    /// only sanctioned non-fixed `.system(size:)` outside the ramp.
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
    /// The selected row's fill; `selectionBorder` outlines it.
    static let fillSelected = Color.primary.opacity(0.10)
    static let selectionBorder = Color.primary.opacity(0.16)
    static let highContrastSelection = Color.primary.opacity(0.18)
    static let highContrastSelectionBorder = Color.accentColor
    /// Tracked-caps section headers on the panel.
    static let sectionHeader = Color.primary.opacity(0.70)
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

    /// The website's language (anvil/app/foundry/foundry.css) for brand
    /// surfaces: onboarding. Always dark, set in Geist, closed by an orange
    /// full stop.
    enum Brand {
        static let ink = Color(red: 0.059, green: 0.051, blue: 0.047)
        static let inkGlow = Color(red: 0.090, green: 0.075, blue: 0.059)
        static let text = Color(red: 0.933, green: 0.906, blue: 0.867)
        static let muted = Color(red: 0.741, green: 0.706, blue: 0.667)
        static let faint = Color(red: 0.522, green: 0.490, blue: 0.455)
        static let line = Color(red: 0.282, green: 0.251, blue: 0.224)
        static let rowTop = Color(red: 0.141, green: 0.125, blue: 0.110)
        static let rowHover = Color.white.opacity(0.035)
        static let rowSelected = Color.white.opacity(0.06)
        static let accent = Color(red: 0.980, green: 0.392, blue: 0.157)
        static let accentDeep = Color(red: 0.941, green: 0.294, blue: 0.063)
        static let accentChip = ink.opacity(0.14)
        static let accentGlow = accent.opacity(0.22)
        static let accentSide = Color(red: 0.600, green: 0.184, blue: 0.039)
        static let tileIdle = Color(red: 0.227, green: 0.200, blue: 0.176)
        static let tileDone = Color(red: 0.420, green: 0.373, blue: 0.329)
        static let wordmarkTop = Color(red: 0.831, green: 0.788, blue: 0.718)
        static let wordmarkBottom = Color(red: 0.761, green: 0.714, blue: 0.639)
        static let chalkTop = Color(red: 0.949, green: 0.925, blue: 0.875)
        static let chalkMid = Color(red: 0.890, green: 0.859, blue: 0.800)
        static let chalkBottom = Color(red: 0.824, green: 0.780, blue: 0.702)
        static let chalkSideTop = Color(red: 0.663, green: 0.616, blue: 0.541)
        static let chalkSideBottom = Color(red: 0.522, green: 0.478, blue: 0.412)
        static let chalkHighlight = Color.white.opacity(0.75)
        static let chalkEdge = Color(red: 0.471, green: 0.412, blue: 0.333).opacity(0.25)
        static let legend = Color(red: 0.165, green: 0.141, blue: 0.122)
        static let legendName = Color(red: 0.427, green: 0.392, blue: 0.341)
        static let keyShadow = Color.black.opacity(0.6)
        static let keyIdleTop = Color(red: 0.106, green: 0.092, blue: 0.082)
        static let keyIdleBottom = Color(red: 0.086, green: 0.075, blue: 0.067)
        static let keyIdleEdge = Color(red: 0.149, green: 0.129, blue: 0.114)
        static let keyIdleLegend = Color(red: 0.275, green: 0.247, blue: 0.220)
        static let keyIdleBase = Color(red: 0.039, green: 0.035, blue: 0.031)
        static let tileShadow = Color.black.opacity(0.4)

        static let display = Font.custom("Geist-Regular", size: 40)
        static let displayLarge = Font.custom("Geist-Regular", size: 50)
        static let lead = Font.custom("Geist-Regular", size: 16)
        static let rowTitle = Font.custom("Geist-Medium", size: 16)
        static let rowDetail = Font.custom("Geist-Regular", size: 14)
        static let button = Font.custom("Geist-Medium", size: 16)
        static let quiet = Font.custom("Geist-Regular", size: 15)
        static let kbd = Font.custom("Geist-Medium", size: 13)
        static let keyGlyph = Font.custom("Geist-Regular", size: 14)
        static let keyName = Font.custom("Geist-Medium", size: 8.5)

        /// Onboarding motion. One strong ease-out curve, no overshoot:
        /// press answers at once, state changes settle, entrances stay short.
        enum Motion {
            static let press = Animation.timingCurve(0.23, 1, 0.32, 1, duration: 0.12)
            static let release = Animation.timingCurve(0.23, 1, 0.32, 1, duration: 0.22)
            static let state = Animation.timingCurve(0.23, 1, 0.32, 1, duration: 0.22)
            static let enter = Animation.timingCurve(0.23, 1, 0.32, 1, duration: 0.45)
            static let step = Animation.timingCurve(0.23, 1, 0.32, 1, duration: 0.3)
            static let stagger = 0.05
            static let rise: CGFloat = 6
        }

        static let displayTracking: CGFloat = -1.8
        static let displayLargeTracking: CGFloat = -2.3
        static let bodyTracking: CGFloat = -0.16

        /// Geist ships inside the app's resource bundle; registering it once
        /// makes the `Font.custom` names above resolve.
        static let registerFonts: Void = {
            let urls = ["Geist-Light", "Geist-Regular", "Geist-Medium"]
                .compactMap { Bundle.packagedResources?.url(forResource: $0, withExtension: "ttf") }
            CTFontManagerRegisterFontURLs(urls as CFArray, .process, true, nil)
        }()
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
