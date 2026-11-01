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
            FoundryTheme.scrim
        case .control:
            FoundryTheme.fillTint
        case .prominentControl:
            FoundryTheme.accent
        case .floatingOverlay:
            FoundryTheme.overlaySurface
        case .contentSurface:
            FoundryTheme.fillSubtle
        }
    }

    var fallbackStroke: Color {
        switch self {
        case .shell:
            FoundryTheme.stroke
        case .control:
            FoundryTheme.fillTint
        case .prominentControl:
            Color.clear
        case .floatingOverlay:
            FoundryTheme.overlayStroke
        case .contentSurface:
            FoundryTheme.fillTint
        }
    }
}

struct FoundryGlassSurface<Content: View, SurfaceShape: Shape>: View {
    let content: Content
    let role: FoundryMaterialRole
    let shape: SurfaceShape

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.foundryIncreaseContrast) private var increaseContrast

    init(role: FoundryMaterialRole, shape: SurfaceShape, @ViewBuilder content: () -> Content) {
        self.content = content()
        self.role = role
        self.shape = shape
    }

    var body: some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *), reduceTransparency == false {
            nativeSurface
        } else {
            fallbackSurface
        }
        #else
        fallbackSurface
        #endif
    }

    private var fallbackSurface: some View {
        content
            .background(role.fallbackFill, in: shape)
            .overlay {
                shape.stroke(increaseContrast ? AnyShapeStyle(Color(nsColor: .separatorColor)) : AnyShapeStyle(role.fallbackStroke), lineWidth: 1)
            }
    }

    #if compiler(>=6.2)
    @available(macOS 26.0, *)
    @ViewBuilder
    private var nativeSurface: some View {
        switch role {
        case .shell, .control, .floatingOverlay, .contentSurface:
            content.glassEffect(.regular, in: shape)
        case .prominentControl:
            content.glassEffect(.regular.tint(FoundryTheme.accent), in: shape)
        }
    }
    #endif
}

struct FoundryIconButton: View {
    let systemName: String
    let accessibilityLabel: String
    var isSelected = false
    var tint: Color = FoundryTheme.textSecondary
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(FoundryTheme.Glyph.sm)
                .foregroundStyle(isSelected ? FoundryTheme.textPrimary : tint)
                .frame(width: FoundryTheme.Control.compact, height: FoundryTheme.Control.compact)
                .background(isSelected ? FoundryTheme.fillSelected : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: FoundryTheme.Radius.control, style: .continuous))
        }
        .buttonStyle(FoundryQuietButtonStyle())
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
                        .font(FoundryTheme.Glyph.xs)
                }
                Text(title)
                    .font(FoundryTheme.body)
            }
            .foregroundStyle(isProminent ? FoundryTheme.accent : FoundryTheme.textSecondary)
            .padding(.horizontal, FoundryTheme.Spacing.md)
            .frame(height: FoundryTheme.Control.compact)
        }
        .buttonStyle(FoundryQuietButtonStyle())
    }
}

struct FoundryQuietButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.55 : 1)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
            .pointerCursor()
    }
}

struct PressableButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.975 : 1)
            .opacity(configuration.isPressed ? 0.82 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.10), value: configuration.isPressed)
            .pointerCursor()
    }
}

extension View {
    /// The pointing hand over anything clickable in the panel.
    func pointerCursor() -> some View {
        onHover { hovering in
            if hovering { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
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
            Text(title)
                .font(FoundryTheme.micro)
                .foregroundStyle(FoundryTheme.textTertiary)

            if let count {
                Text(count)
                    .font(FoundryTheme.mono)
                    .foregroundStyle(FoundryTheme.textQuaternary)
            }

            Spacer(minLength: 0)

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(FoundryTheme.micro)
                    .foregroundStyle(FoundryTheme.textSecondary)
                    .buttonStyle(FoundryQuietButtonStyle())
            }
        }
        .accessibilityElement(children: .contain)
    }
}

struct FoundryStatusBanner: View {
    let text: String
    let symbol: String
    var tint: Color = FoundryTheme.textSecondary
    var isLoading = false

    var body: some View {
        HStack(spacing: 8) {
            if isLoading {
                ProgressView()
                    .controlSize(.small)
                    .tint(tint)
            } else {
                Image(systemName: symbol)
                    .font(FoundryTheme.Glyph.xs)
            }

            Text(text)
                .font(FoundryTheme.caption)
                .foregroundStyle(tint)
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(FoundryTheme.fillSubtle, in: RoundedRectangle(cornerRadius: FoundryTheme.Radius.control, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: FoundryTheme.Radius.control, style: .continuous)
                .stroke(tint.opacity(FoundryTheme.Alpha.tint), lineWidth: 1)
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
                .font(FoundryTheme.Glyph.xl)
                .foregroundStyle(FoundryTheme.textSecondary)
                .frame(width: 58, height: 58)
                .background(FoundryTheme.fillHover)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            Text(title)
                .font(FoundryTheme.body)
                .foregroundStyle(FoundryTheme.textPrimary)

            Text(message)
                .font(FoundryTheme.bodySecondary)
                .foregroundStyle(FoundryTheme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 24)

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(FoundryTheme.body)
                    .foregroundStyle(FoundryTheme.textPrimary)
                    .padding(.horizontal, 13)
                    .frame(height: FoundryTheme.Control.compact)
                    .background(FoundryTheme.fillTint)
                    .clipShape(RoundedRectangle(cornerRadius: FoundryTheme.Radius.control, style: .continuous))
                    .buttonStyle(PressableButtonStyle())
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}

extension View {
    func rowActivation(isSelected: Bool, perform action: @escaping () -> Void) -> some View {
        contentShape(Rectangle())
            .onTapGesture(perform: action)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            .accessibilityAction { action() }
    }
}
