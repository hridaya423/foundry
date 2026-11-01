import AppKit
import SwiftUI


struct FeatureHeader<Content: View, Trailing: View>: View {
    let showBack: Bool
    let onBack: () -> Void
    var showsHairline = true
    @ViewBuilder var content: Content
    @ViewBuilder var trailing: Trailing

    init(showBack: Bool, onBack: @escaping () -> Void, showsHairline: Bool = true,
         @ViewBuilder content: () -> Content, @ViewBuilder trailing: () -> Trailing) {
        self.showBack = showBack
        self.onBack = onBack
        self.showsHairline = showsHairline
        self.content = content()
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 12) {
            if showBack {
                FoundryIconButton(
                    systemName: "chevron.left",
                    accessibilityLabel: "Back to Home",
                    action: onBack
                )
            }
            content
            trailing
        }
        .padding(.horizontal, 22)
        .frame(height: 60)
        .background(Color.clear)
        .overlay(alignment: .bottom) {
            if showsHairline {
                LinearGradient(
                    colors: [FoundryTheme.fillTint, FoundryTheme.fillSubtle, Color.clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 4)
            }
        }
    }
}

struct FeatureTitle: View {
    let symbol: String
    let title: LocalizedStringResource

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(FoundryTheme.Glyph.sm)
                .foregroundStyle(FoundryTheme.textTertiary)
            Text(title)
                .font(FoundryTheme.title)
                .foregroundStyle(FoundryTheme.textPrimary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct FooterActionSpec {
    let label: LocalizedStringResource
    let keys: String
    var emphasized = false

    static let home = FooterActionSpec(label: "Home", keys: "esc")
    static let actions = FooterActionSpec(label: "Actions", keys: "⌘K")
}

struct PanelFooter<Status: View>: View {
    var status: Status
    var actions: [FooterActionSpec]
    var leadingAccessory: AnyView?
    var openSettings: () -> Void = {}
    var openWelcomeGuide: (() -> Void)?

    init(actions: [FooterActionSpec], leadingAccessory: AnyView? = nil,
         openSettings: @escaping () -> Void = {}, openWelcomeGuide: (() -> Void)? = nil,
         @ViewBuilder status: () -> Status) {
        self.status = status()
        self.actions = actions
        self.leadingAccessory = leadingAccessory
        self.openSettings = openSettings
        self.openWelcomeGuide = openWelcomeGuide
    }

    var body: some View {
        HStack(spacing: 0) {
            if let leadingAccessory {
                leadingAccessory
                    .padding(.horizontal, 8)
            } else {
                FoundryMenuButton(openSettings: openSettings, openWelcomeGuide: openWelcomeGuide)
            }

            status
                .padding(.horizontal, 12)

            Spacer(minLength: 8)

            HStack(spacing: 12) {
                ForEach(Array(actions.enumerated()), id: \.offset) { _, spec in
                    FooterAction(spec: spec)
                }
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 38)
    }
}

extension PanelFooter where Status == EmptyView {
    init(actions: [FooterActionSpec], leadingAccessory: AnyView? = nil,
         openSettings: @escaping () -> Void = {}, openWelcomeGuide: (() -> Void)? = nil) {
        self.init(actions: actions, leadingAccessory: leadingAccessory,
                  openSettings: openSettings, openWelcomeGuide: openWelcomeGuide,
                  status: { EmptyView() })
    }
}

struct FoundryMenuButton: View {
    var openSettings: () -> Void = {}
    var openWelcomeGuide: (() -> Void)? = nil

    var body: some View {
        Menu {
            Button("Settings…") { openSettings() }
                .keyboardShortcut(",", modifiers: .command)
            if let openWelcomeGuide {
                Button("Welcome Guide") { openWelcomeGuide() }
            }
            Divider()
            Button("Quit Foundry") { NSApp.terminate(nil) }
                .keyboardShortcut("q", modifiers: .command)
        } label: {
            Image(systemName: "command")
                .font(FoundryTheme.Glyph.xs)
                .foregroundStyle(FoundryTheme.textSecondary)
                .frame(width: 30, height: 30)
        }
        .menuStyle(.button)
        .buttonStyle(FoundryQuietButtonStyle())
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel("Foundry menu")
        .help("Settings and Quit")
    }
}

struct KeycapHint: View {
    let text: String

    var body: some View {
        Text(text)
            .font(FoundryTheme.caption)
            .foregroundStyle(FoundryTheme.textSecondary)
            .multilineTextAlignment(.center)
            .baselineOffset(-0.5)
            .padding(.horizontal, 5)
            .frame(minWidth: 19, minHeight: 19)
            .background(FoundryTheme.fillTint, in: RoundedRectangle(cornerRadius: FoundryTheme.Radius.badge, style: .continuous))
            .fixedSize()
    }
}

struct FooterAction: View {
    let spec: FooterActionSpec

    var body: some View {
        HStack(spacing: 6) {
            KeycapHint(text: spec.keys)

            Text(spec.label)
                .font(spec.emphasized ? FoundryTheme.micro : FoundryTheme.caption)
                .foregroundStyle(spec.emphasized ? FoundryTheme.textSecondary : FoundryTheme.textTertiary)
        }
    }
}

struct InlineNotice: View {
    enum Level {
        case info, warning, error

        var tint: Color {
            switch self {
            case .info: FoundryTheme.textSecondary
            case .warning: FoundryTheme.warning
            case .error: FoundryTheme.destructive
            }
        }

        var defaultSymbol: String {
            switch self {
            case .info: "info.circle"
            case .warning, .error: "exclamationmark.triangle"
            }
        }
    }

    let level: Level
    let text: LocalizedStringResource
    var symbol: String? = nil
    var actionTitle: LocalizedStringResource? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 9) {
            Label(String(localized: text), systemImage: symbol ?? level.defaultSymbol)
                .font(FoundryTheme.bodySecondary)
                .foregroundStyle(level.tint)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let actionTitle, let action {
                Button(String(localized: actionTitle), action: action)
                    .buttonStyle(.plain)
                    .font(FoundryTheme.micro)
                    .foregroundStyle(FoundryTheme.textPrimary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(FoundryTheme.fillTint)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(level.tint.opacity(FoundryTheme.Alpha.subtle))
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}
