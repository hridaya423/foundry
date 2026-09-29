import AppKit
import SwiftUI

struct FeatureSurface {
    let id: String
    let header: AnyView
    let headerTrailing: AnyView
    let content: AnyView
    let footerActions: [FooterActionSpec]

    init<Header: View, Trailing: View, Content: View>(
        id: String,
        @ViewBuilder header: () -> Header,
        @ViewBuilder headerTrailing: () -> Trailing,
        @ViewBuilder content: () -> Content,
        footerActions: [FooterActionSpec]
    ) {
        self.id = id
        self.header = AnyView(header())
        self.headerTrailing = AnyView(headerTrailing())
        self.content = AnyView(content())
        self.footerActions = footerActions
    }

    init<Header: View, Content: View>(
        id: String,
        @ViewBuilder header: () -> Header,
        @ViewBuilder content: () -> Content,
        footerActions: [FooterActionSpec]
    ) {
        self.init(id: id, header: header, headerTrailing: { EmptyView() }, content: content, footerActions: footerActions)
    }
}

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
                    colors: [Color.primary.opacity(0.09), Color.primary.opacity(0.02), Color.clear],
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
    let title: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(FoundryTheme.mutedText)
            Text(title)
                .font(FoundryTheme.searchFont)
                .foregroundStyle(FoundryTheme.primaryText)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct FooterActionSpec {
    let label: String
    let keys: String
    var emphasized = false

    static let home = FooterActionSpec(label: "Home", keys: "esc")
    static let actions = FooterActionSpec(label: "Actions", keys: "⌘K")
}

struct PanelFooter<Status: View>: View {
    var status: Status
    var actions: [FooterActionSpec]
    var showsQuickAIChip = false
    var openSettings: () -> Void = {}
    var openWelcomeGuide: (() -> Void)?

    init(actions: [FooterActionSpec], showsQuickAIChip: Bool = false,
         openSettings: @escaping () -> Void = {}, openWelcomeGuide: (() -> Void)? = nil,
         @ViewBuilder status: () -> Status) {
        self.status = status()
        self.actions = actions
        self.showsQuickAIChip = showsQuickAIChip
        self.openSettings = openSettings
        self.openWelcomeGuide = openWelcomeGuide
    }

    var body: some View {
        HStack(spacing: 0) {
            if showsQuickAIChip {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 11, weight: .semibold))
                    Text("Quick AI")
                        .font(FoundryTheme.body(size: 12, weight: .semibold))
                }
                .foregroundStyle(FoundryTheme.secondaryText)
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
    init(actions: [FooterActionSpec], showsQuickAIChip: Bool = false,
         openSettings: @escaping () -> Void = {}, openWelcomeGuide: (() -> Void)? = nil) {
        self.init(actions: actions, showsQuickAIChip: showsQuickAIChip,
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
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(FoundryTheme.secondaryText)
                .frame(width: 30, height: 30)
        }
        .menuStyle(.button)
        .buttonStyle(FoundryQuietButtonStyle())
        .menuIndicator(.hidden)
        .fixedSize()
        .pointerCursor()
        .accessibilityLabel("Foundry menu")
        .help("Settings and Quit")
    }
}

struct KeycapHint: View {
    let text: String

    var body: some View {
        FoundryGlassSurface(role: .control, shape: RoundedRectangle(cornerRadius: 5, style: .continuous)) {
            Text(text)
                .font(.system(size: 10.5, weight: .medium, design: .rounded))
                .foregroundStyle(FoundryTheme.secondaryText)
                .multilineTextAlignment(.center)
                .baselineOffset(-0.5)
                .padding(.horizontal, 5)
                .frame(minWidth: 19, minHeight: 19)
        }
        .fixedSize()
    }
}

struct FooterAction: View {
    let spec: FooterActionSpec

    var body: some View {
        HStack(spacing: 6) {
            KeycapHint(text: spec.keys)

            Text(spec.label)
                .font(FoundryTheme.body(size: 11.5, weight: spec.emphasized ? .semibold : .medium))
                .foregroundStyle(spec.emphasized ? FoundryTheme.secondaryText : FoundryTheme.mutedText)
        }
    }
}

struct EmptyState: View {
    let title: String
    var message: String? = nil
    var symbol: String? = nil
    var isLoading = false

    var body: some View {
        VStack(spacing: 14) {
            Spacer()

            if isLoading {
                ProgressView()
                    .controlSize(.small)
                    .tint(FoundryTheme.secondaryText)
            } else if let symbol {
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.primary.opacity(0.075))
                        .frame(width: 68, height: 68)

                    Image(systemName: symbol)
                        .font(.system(size: 28, weight: .regular))
                        .foregroundStyle(FoundryTheme.secondaryText)
                }
            }

            Text(title)
                .font(FoundryTheme.body(size: isLoading ? 15 : 17, weight: .medium))
                .foregroundStyle(FoundryTheme.primaryText)

            if let message {
                Text(message)
                    .font(FoundryTheme.body(size: 13, weight: .regular))
                    .foregroundStyle(FoundryTheme.secondaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.horizontal, 40)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.clear)
    }
}

struct InlineNotice: View {
    enum Level {
        case info, warning, error

        var tint: Color {
            switch self {
            case .info: FoundryTheme.secondaryText
            case .warning: FoundryTheme.warning
            case .error: FoundryTheme.error
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
    let text: String
    var symbol: String? = nil
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 9) {
            Label(text, systemImage: symbol ?? level.defaultSymbol)
                .font(FoundryTheme.body(size: 12, weight: .medium))
                .foregroundStyle(level.tint)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.plain)
                    .font(FoundryTheme.body(size: 11, weight: .semibold))
                    .foregroundStyle(FoundryTheme.primaryText)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color.primary.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .pointerCursor()
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(level.tint.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}
