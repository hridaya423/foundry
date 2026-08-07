import SwiftUI

enum FoundryMaterialRole {
    case shell
    case control
    case prominentControl
    case floatingOverlay
    case contentSurface

    var fallbackFill: Color {
        switch self {
        case .shell:
            Color.black.opacity(0.18)
        case .control:
            Color.white.opacity(0.07)
        case .prominentControl:
            FoundryTheme.accent
        case .floatingOverlay:
            Color.black.opacity(0.42)
        case .contentSurface:
            Color.white.opacity(0.045)
        }
    }

    var fallbackStroke: Color {
        switch self {
        case .shell:
            Color.white.opacity(0.16)
        case .control:
            Color.white.opacity(0.08)
        case .prominentControl:
            Color.clear
        case .floatingOverlay:
            Color.white.opacity(0.10)
        case .contentSurface:
            Color.white.opacity(0.07)
        }
    }
}

struct FoundryGlassSurface<Content: View, SurfaceShape: Shape>: View {
    let content: Content
    let role: FoundryMaterialRole
    let shape: SurfaceShape

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    init(role: FoundryMaterialRole, shape: SurfaceShape, @ViewBuilder content: () -> Content) {
        self.content = content()
        self.role = role
        self.shape = shape
    }

    var body: some View {
        if #available(macOS 26.0, *), reduceTransparency == false {
            nativeSurface
        } else {
            content
                .background(role.fallbackFill, in: shape)
                .overlay {
                    shape.stroke(role.fallbackStroke, lineWidth: 1)
                }
        }
    }

    @available(macOS 26.0, *)
    @ViewBuilder
    private var nativeSurface: some View {
        switch role {
        case .shell, .control, .floatingOverlay, .contentSurface:
            content.glassEffect(.regular, in: shape)
        case .prominentControl:
            content.glassEffect(.regular.tint(FoundryTheme.accentTint), in: shape)
        }
    }
}

struct FoundryIconButton: View {
    let systemName: String
    let accessibilityLabel: String
    var isSelected = false
    var tint: Color = FoundryTheme.secondaryText
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isSelected ? FoundryTheme.primaryText : tint)
                .frame(width: FoundryTheme.Control.compact, height: FoundryTheme.Control.compact)
                .background(isSelected ? FoundryTheme.selection : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: FoundryTheme.Radius.control, style: .continuous))
        }
        .buttonStyle(FoundryQuietButtonStyle())
        .pointerCursor()
        .accessibilityLabel(accessibilityLabel)
        .help(accessibilityLabel)
    }
}

struct FoundryActionButton: View {
    let title: String
    var systemName: String?
    var isProminent = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: FoundryTheme.Spacing.xs) {
                if let systemName {
                    Image(systemName: systemName)
                        .font(.system(size: 12, weight: .semibold))
                }
                Text(title)
                    .font(FoundryTheme.body(size: 12, weight: .semibold))
            }
            .foregroundStyle(isProminent ? FoundryTheme.accentTint : FoundryTheme.secondaryText)
            .padding(.horizontal, FoundryTheme.Spacing.md)
            .frame(height: FoundryTheme.Control.compact)
        }
        .buttonStyle(FoundryQuietButtonStyle())
        .pointerCursor()
    }
}

struct FoundryQuietButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.55 : 1)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct PressableButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.975 : 1)
            .opacity(configuration.isPressed ? 0.82 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.10), value: configuration.isPressed)
    }
}

struct FoundrySurface<Content: View>: View {
    let content: Content
    var padding: CGFloat = FoundryTheme.Spacing.lg
    var cornerRadius: CGFloat = FoundryTheme.Radius.card
    var emphasized = false

    init(padding: CGFloat = FoundryTheme.Spacing.lg, cornerRadius: CGFloat = FoundryTheme.Radius.card, emphasized: Bool = false, @ViewBuilder content: () -> Content) {
        self.content = content()
        self.padding = padding
        self.cornerRadius = cornerRadius
        self.emphasized = emphasized
    }

    var body: some View {
        content
            .padding(padding)
            .background(emphasized ? Color.white.opacity(0.075) : Color.white.opacity(0.045))
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(emphasized ? Color.white.opacity(0.13) : Color.white.opacity(0.07), lineWidth: 1)
            }
    }
}

struct FoundrySectionHeader: View {
    let title: String
    var count: String?
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(spacing: 7) {
            Text(title.uppercased())
                .font(FoundryTheme.body(size: 10, weight: .bold))
                .foregroundStyle(FoundryTheme.faintText)
                .tracking(0.7)

            if let count {
                Text(count)
                    .font(FoundryTheme.mono(size: 10, weight: .medium))
                    .foregroundStyle(FoundryTheme.faintText)
            }

            Spacer(minLength: 0)

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(FoundryTheme.body(size: 11, weight: .semibold))
                    .foregroundStyle(FoundryTheme.secondaryText)
                    .buttonStyle(FoundryQuietButtonStyle())
                    .pointerCursor()
            }
        }
        .accessibilityElement(children: .contain)
    }
}

struct FoundryStatusBanner: View {
    let text: String
    let symbol: String
    var tint: Color = FoundryTheme.secondaryText
    var isLoading = false

    var body: some View {
        HStack(spacing: 8) {
            if isLoading {
                ProgressView()
                    .controlSize(.small)
                    .tint(tint)
            } else {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .semibold))
            }

            Text(text)
                .font(FoundryTheme.body(size: 11.5, weight: .medium))
                .foregroundStyle(tint)
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: FoundryTheme.Radius.control, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: FoundryTheme.Radius.control, style: .continuous)
                .stroke(tint.opacity(0.16), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
    }
}

struct FoundryEmptyState: View {
    let symbol: String
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 28, weight: .regular))
                .foregroundStyle(FoundryTheme.secondaryText)
                .frame(width: 58, height: 58)
                .background(Color.white.opacity(0.065))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            Text(title)
                .font(FoundryTheme.body(size: 15, weight: .semibold))
                .foregroundStyle(FoundryTheme.primaryText)

            Text(message)
                .font(FoundryTheme.body(size: 12, weight: .regular))
                .foregroundStyle(FoundryTheme.secondaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 24)

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(FoundryTheme.body(size: 12, weight: .semibold))
                    .foregroundStyle(FoundryTheme.primaryText)
                    .padding(.horizontal, 13)
                    .frame(height: FoundryTheme.Control.compact)
                    .background(Color.white.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: FoundryTheme.Radius.control, style: .continuous))
                    .buttonStyle(PressableButtonStyle())
                    .pointerCursor()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}
