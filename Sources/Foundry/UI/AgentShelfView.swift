import SwiftUI

struct AgentShelfView: View {
    @ObservedObject var agents: AgentMonitorState
    let dismiss: () -> Void
    @State private var selectedProvider: AgentProviderKind?

    private let providerTabs: [AgentProviderKind] = [.cursor, .codex, .opencode, .claude]

    private var active: [AgentSessionCard] {
        filteredSessions.filter { $0.status.isActive }
    }

    private var recent: [AgentSessionCard] {
        filteredSessions.filter { $0.status.isActive == false }
    }

    private var filteredSessions: [AgentSessionCard] {
        Self.sessions(for: selectedProvider, in: agents.sessions)
    }

    nonisolated static func sessions(for provider: AgentProviderKind?, in sessions: [AgentSessionCard]) -> [AgentSessionCard] {
        guard let provider else { return sessions }
        return sessions.filter { $0.provider == provider }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                shelfIcon
                VStack(alignment: .leading, spacing: 1) {
                    Text("Agent Shelf")
                        .font(FoundryTheme.body(size: 14, weight: .semibold))
                        .foregroundStyle(FoundryTheme.primaryText)
                    Text("\(active.count) active · \(filteredSessions.count) tracked")
                        .font(FoundryTheme.body(size: 11, weight: .medium))
                        .foregroundStyle(FoundryTheme.mutedText)
                }
                Spacer()
                Button(action: agents.refresh) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(FoundryTheme.secondaryText)
                        .frame(width: 28, height: 28)
                        .background(Color.primary.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .pointerCursor()
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)

            Rectangle()
                .fill(Color.primary.opacity(0.07))
                .frame(height: 1)

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
                        if filteredSessions.isEmpty {
                            FoundryEmptyState(
                                symbol: "sparkles.rectangle.stack",
                                title: selectedProvider.map { "No \($0.rawValue) sessions found" } ?? "No agent sessions found",
                                message: "Provider hooks, plugins, and desktop catalogs appear here.",
                                actionTitle: "Refresh",
                                action: agents.refresh
                            )
                            .padding(.vertical, 38)
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)
                }
                .scrollIndicators(.never)
                .id(selectedProvider?.rawValue ?? "all")
                .onChange(of: selectedProvider) { _, _ in
                    proxy.scrollTo("agent-shelf-top", anchor: .top)
                }
            }
        }
    }

    private var providerTabsView: some View {
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
            .padding(.horizontal, 18)
            .padding(.vertical, 8)
        }
        .scrollClipDisabled()
        .scrollIndicators(.never)
    }

    private func providerTab(title: String, provider: AgentProviderKind?, count: Int) -> some View {
        Button {
            selectedProvider = provider
        } label: {
            HStack(spacing: 6) {
                if let provider {
                    AgentProviderIcon(provider: provider, size: 16)
                }
                Text(title)
                    .font(FoundryTheme.body(size: 11, weight: .semibold))
                Text("\(count)")
                    .font(FoundryTheme.body(size: 10, weight: .bold))
                    .foregroundStyle(FoundryTheme.faintText)
            }
            .foregroundStyle(selectedProvider == provider ? FoundryTheme.primaryText : FoundryTheme.mutedText)
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(selectedProvider == provider ? Color.primary.opacity(0.11) : Color.primary.opacity(0.045))
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(selectedProvider == provider ? Color.primary.opacity(0.12) : Color.primary.opacity(0.05), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .pointerCursor()
    }

    private func section(title: String, sessions: [AgentSessionCard]) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("\(title.uppercased()) · \(sessions.count)")
                .font(FoundryTheme.body(size: 10, weight: .bold))
                .foregroundStyle(FoundryTheme.faintText)
                .tracking(0.8)
            VStack(spacing: 0) {
                ForEach(Array(sessions.enumerated()), id: \.element.id) { index, session in
                    AgentShelfRow(session: session) {
                        agents.open(session)
                        dismiss()
                    }
                    if index < sessions.count - 1 {
                        Rectangle()
                            .fill(Color.primary.opacity(0.055))
                            .frame(height: 1)
                            .padding(.leading, 48)
                    }
                }
            }
            .background(Color.primary.opacity(0.035))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.primary.opacity(0.05), lineWidth: 1)
            )
        }
    }

    @ViewBuilder
    private var shelfIcon: some View {
        let providers = Set(filteredSessions.map(\.provider))
        if let selectedProvider {
            AgentProviderIcon(provider: selectedProvider, size: 24)
        } else if providers.count == 1, let provider = providers.first {
            AgentProviderIcon(provider: provider, size: 24)
        } else {
            Image(systemName: "sparkles.rectangle.stack")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(FoundryTheme.secondaryText)
        }
    }
}

private struct AgentShelfRow: View {
    let session: AgentSessionCard
    let open: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: open) {
            HStack(spacing: 11) {
                AgentProviderIcon(provider: session.provider, size: 30)
                    .frame(width: 30, height: 30)
                    .background(statusColor.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(session.title)
                        .font(FoundryTheme.body(size: 13, weight: .semibold))
                        .foregroundStyle(FoundryTheme.primaryText)
                        .lineLimit(1)
                    Text(detail)
                        .font(FoundryTheme.body(size: 10.5, weight: .regular))
                        .foregroundStyle(FoundryTheme.mutedText)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 3) {
                    Text(session.status.rawValue)
                        .font(FoundryTheme.body(size: 10, weight: .semibold))
                        .foregroundStyle(statusColor)
                    if let updatedAt = session.updatedAt {
                        Text(Self.relative.localizedString(for: updatedAt, relativeTo: Date()))
                            .font(FoundryTheme.body(size: 9.5, weight: .medium))
                            .foregroundStyle(FoundryTheme.faintText)
                    }
                }
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(FoundryTheme.mutedText)
                    .opacity(hovering ? 1 : 0.25)
            }
            .padding(.horizontal, 10)
            .frame(height: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(canOpen == false)
        .onHover { hovering = $0 }
        .pointerCursor()
    }

    private var detail: String {
        [session.provider.rawValue, session.project, session.subtitle].compactMap { value in
            guard let value, value.isEmpty == false else { return nil }
            return value
        }.joined(separator: " · ")
    }

    private var canOpen: Bool {
        session.capabilities.intersection([.jumpApplication, .jumpTerminal, .jumpTask]).isEmpty == false
    }

    private var statusColor: Color {
        switch session.status {
        case .working, .running: Color(red: 0.42, green: 0.90, blue: 0.67)
        case .needsInput: Color(red: 1.0, green: 0.76, blue: 0.35)
        case .reviewReady: Color(red: 0.52, green: 0.72, blue: 1.0)
        case .planning: Color(red: 0.70, green: 0.62, blue: 1.0)
        case .completed: Color(red: 0.44, green: 0.72, blue: 1.0)
        case .failed: Color(red: 1.0, green: 0.38, blue: 0.38)
        case .idle, .recent: FoundryTheme.faintText
        }
    }

    private static let relative: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()
}
