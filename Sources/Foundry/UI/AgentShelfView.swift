import SwiftUI

struct AgentShelfView: View {
    var agents: AgentMonitorState
    var openSettings: () -> Void = {}
    var open: (AgentSessionCard) -> Void = { _ in }

    private var providerTabs: [AgentProviderKind] { Self.tabs(for: agents.sessions) }

    nonisolated static func tabs(for sessions: [AgentSessionCard]) -> [AgentProviderKind] {
        let preferred: [AgentProviderKind] = [.claude, .codex, .cursor, .opencode]
        let present = Set(sessions.map(\.provider))
        let others = present.subtracting(preferred).sorted { $0.rawValue < $1.rawValue }
        return preferred.filter(present.contains) + others
    }

    private var active: [AgentSessionCard] {
        filteredSessions.filter { $0.status.isActive }
    }

    private var recent: [AgentSessionCard] {
        filteredSessions.filter { $0.status.isActive == false }
    }

    private var filteredSessions: [AgentSessionCard] {
        Self.sessions(for: agents.selectedProvider, in: agents.sessions)
    }

    static func canOpen(_ session: AgentSessionCard) -> Bool {
        session.capabilities.intersection([.jumpApplication, .jumpTerminal, .jumpTask]).isEmpty == false
    }

    nonisolated static func sessions(for provider: AgentProviderKind?, in sessions: [AgentSessionCard]) -> [AgentSessionCard] {
        guard let provider else { return sessions }
        return sessions.filter { $0.provider == provider }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if agents.socketListening == false {
                InlineNotice(level: .warning, text: "Live updates are off. Open Settings › Agents.", actionTitle: "Open Settings", action: openSettings)
                    .padding(.horizontal, 18)
                    .padding(.top, 10)
            }
            providerTabsView

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        Color.clear
                            .frame(height: 0)
                            .id("agent-shelf-top")
                        if active.isEmpty == false {
                            section(title: "Active", sessions: active)
                        }
                        if recent.isEmpty == false {
                            section(title: "Recent", sessions: recent)
                        }
                        if filteredSessions.isEmpty && agents.hasLoaded == false {
                            HStack(spacing: 8) {
                                ProgressView().controlSize(.small)
                                Text("Looking for agent sessions…")
                                    .font(FoundryTheme.bodySecondary)
                                    .foregroundStyle(FoundryTheme.textTertiary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 38)
                        } else if filteredSessions.isEmpty {
                            FoundryEmptyState(
                                symbol: "sparkles.rectangle.stack",
                                title: "No agent sessions yet",
                                message: "Install a bridge in Settings › Agents to see Claude Code, Codex, Cursor and OpenCode here.",
                                actionTitle: "Open Agent Settings",
                                action: openSettings
                            )
                            .padding(.vertical, 38)
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)
                }
                .scrollIndicators(.never)
                .id(agents.selectedProvider?.rawValue ?? "all")
                .onChange(of: agents.selectedProvider) { _, _ in
                    proxy.scrollTo("agent-shelf-top", anchor: .top)
                }
                .onChange(of: agents.selectedSessionID) { _, id in
                    guard let id else { return }
                    proxy.scrollTo(id, anchor: .center)
                }
            }
        }
    }

    private var providerTabsView: some View {
        HStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    providerTab(title: "All", provider: nil, count: agents.sessions.count)
                    ForEach(providerTabs, id: \.self) { provider in
                        providerTab(
                            title: provider.rawValue,
                            provider: provider,
                            count: agents.sessions.count(where: { $0.provider == provider })
                        )
                    }
                }
            }
            .scrollClipDisabled()
            .scrollIndicators(.never)
            Button(action: agents.refresh) {
                Image(systemName: "arrow.clockwise")
                    .font(FoundryTheme.Glyph.xs)
                    .foregroundStyle(FoundryTheme.textSecondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Refresh sessions")
            .accessibilityLabel("Refresh sessions")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
    }

    private func providerTab(title: String, provider: AgentProviderKind?, count: Int) -> some View {
        Button {
            agents.selectedProvider = provider
        } label: {
            HStack(spacing: 6) {
                if let provider {
                    AgentProviderIcon(provider: provider, size: 16)
                }
                Text(title)
                    .font(FoundryTheme.micro)
                Text("\(count)")
                    .font(FoundryTheme.micro)
                    .foregroundStyle(FoundryTheme.textQuaternary)
            }
            .foregroundStyle(agents.selectedProvider == provider ? FoundryTheme.textPrimary : FoundryTheme.textTertiary)
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(agents.selectedProvider == provider ? FoundryTheme.fillSelected : FoundryTheme.fillSubtle)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(agents.selectedProvider == provider ? FoundryTheme.separator : FoundryTheme.fillHover, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func section(title: String, sessions: [AgentSessionCard]) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("\(title.uppercased()) · \(sessions.count)")
                .font(FoundryTheme.micro)
                .foregroundStyle(FoundryTheme.textQuaternary)
                .tracking(0.8)
            VStack(spacing: 0) {
                ForEach(Array(sessions.enumerated()), id: \.element.id) { index, session in
                    AgentShelfRow(session: session, isSelected: agents.selectedSessionID == session.id) { open(session) }
                        .id(session.id)
                    if index < sessions.count - 1 {
                        Rectangle()
                            .fill(FoundryTheme.fillHover)
                            .frame(height: 1)
                            .padding(.leading, 48)
                    }
                }
            }
            .background(FoundryTheme.fillSubtle)
            .clipShape(RoundedRectangle(cornerRadius: FoundryTheme.Radius.row, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: FoundryTheme.Radius.row, style: .continuous)
                    .stroke(FoundryTheme.fillHover, lineWidth: 1)
            )
        }
    }
}

private struct AgentShelfRow: View {
    let session: AgentSessionCard
    let isSelected: Bool
    let open: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: open) {
            HStack(spacing: 11) {
                AgentProviderIcon(provider: session.provider, size: 30)
                    .frame(width: 30, height: 30)
                    .background(statusColor.opacity(FoundryTheme.Alpha.subtle))
                    .clipShape(RoundedRectangle(cornerRadius: FoundryTheme.Radius.control, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(session.title)
                        .font(FoundryTheme.body)
                        .foregroundStyle(FoundryTheme.textPrimary)
                        .lineLimit(1)
                    Text(detail)
                        .font(FoundryTheme.caption)
                        .foregroundStyle(FoundryTheme.textTertiary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 3) {
                    if let label = session.status.label {
                        Text(label)
                            .font(FoundryTheme.micro)
                            .foregroundStyle(statusColor)
                    }
                    if let updatedAt = session.updatedAt {
                        Text(Self.relative.localizedString(for: updatedAt, relativeTo: Date()))
                            .font(FoundryTheme.caption)
                            .foregroundStyle(FoundryTheme.textQuaternary)
                    }
                }
                Image(systemName: "arrow.up.right")
                    .font(FoundryTheme.Glyph.xs)
                    .foregroundStyle(FoundryTheme.textTertiary)
                    .opacity(hovering || isSelected ? 1 : 0.25)
            }
            .padding(.horizontal, 10)
            .frame(height: 52)
            .background(RowBackground(isSelected: isSelected, isHovering: hovering))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }

    private var detail: String {
        [session.provider.rawValue, session.project, session.subtitle].compactMap { value in
            guard let value, value.isEmpty == false else { return nil }
            return value
        }.joined(separator: " · ")
    }

    private var statusColor: Color { session.status.color }

    private static let relative: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()
}
