import AppKit
import SwiftUI

struct HomeAccessoryStrip: View {
    var board: WidgetBoardState
    var agents: AgentMonitorState
    var fileShelf: FileShelfState
    var onAgentOpen: (() -> Void)? = nil
    var onShelfOpen: (() -> Void)? = nil
    var compactMaximum = 4
    var compactBackground = true
    var compactHeight: CGFloat = 58

    var body: some View {
        HStack(spacing: 0) {
            if fileShelf.files.isEmpty == false {
                CompactFileShelfWidget(shelf: fileShelf, open: onShelfOpen)
                    .padding(.horizontal, 12)
                    .frame(maxWidth: .infinity)

                if displayedWidgets.isEmpty == false {
                    compactDivider
                }
            }

            ForEach(Array(displayedWidgets.enumerated()), id: \.element.id) { index, kind in
                compactWidget(for: kind)
                    .padding(.horizontal, 12)
                    .frame(maxWidth: .infinity)

                if index < displayedWidgets.count - 1 {
                    compactDivider
                }
            }
        }
        .padding(.vertical, 3)
        .frame(height: compactHeight + 6)
        .background {
            if compactBackground {
                RoundedRectangle(cornerRadius: FoundryTheme.Radius.overlay, style: .continuous)
                    .fill(FoundryTheme.fillSubtle)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: FoundryTheme.Radius.overlay, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Home accessories")
    }

    private var displayedWidgets: [WidgetKind] {
        let availableSlots = max(compactMaximum - (fileShelf.files.isEmpty ? 0 : 1), 0)
        return board.homeWidgets
            .filter { $0 != .agents || agents.sessions.isEmpty == false }
            .prefix(availableSlots)
            .map { $0 }
    }

    private var compactDivider: some View {
        Rectangle()
            .fill(FoundryTheme.fillTint)
            .frame(width: 1, height: 28)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private func compactWidget(for kind: WidgetKind) -> some View {
        switch kind {
        case .agents:
            AgentWidget(agents: agents, onOpen: onAgentOpen)
        case .calendar, .date:
            CompactDateWidget()
        case .clock:
            ClockWidget()
        case .system:
            SystemWidget(metrics: board.metrics)
        case .battery:
            StatWidget(symbol: board.metrics.batterySymbol, title: "Battery", value: board.metrics.batteryDisplay,
                caption: board.metrics.batteryStateLabel, tint: board.metrics.batteryTint)
        case .disk:
            StatWidget(symbol: "internaldrive", title: "Storage", value: board.metrics.diskDisplay, caption: "free")
        case .uptime:
            StatWidget(symbol: "clock.arrow.circlepath", title: "Uptime", value: board.metrics.uptimeDisplay, caption: "since boot")
        case .thermal:
            StatWidget(symbol: "fanblades", title: "Thermal", value: board.metrics.thermalDisplay, caption: "pressure", tint: board.metrics.thermalTint)
        case .weather:
            WeatherWidget(snapshot: board.weather, city: board.config.weatherCity, isLoading: board.isWeatherLoading, isStale: board.isWeatherStale)
        case .stock:
            StockWidget(snapshot: board.stock, symbol: board.config.stockSymbol, isLoading: board.isStockLoading, isStale: board.isStockStale)
        case .cpu:
            StatWidget(symbol: "cpu", title: "CPU", value: board.metrics.cpuDisplay, caption: "current")
        case .memory:
            StatWidget(symbol: "memorychip", title: "Memory", value: board.metrics.memoryDisplay, caption: "\(board.metrics.memoryUsedDisplay) used")
        case .loadAverage:
            StatWidget(symbol: "waveform.path.ecg", title: "Unix Load", value: board.metrics.loadAverageDisplay, caption: "1 min avg")
        case .diskUsage:
            StatWidget(symbol: "chart.pie", title: "Disk", value: board.metrics.diskUsedDisplay, caption: "used · \(board.metrics.diskDisplay) free")
        case .network:
            StatWidget(symbol: "network", title: "Network", value: board.metrics.localIPAddressDisplay, caption: "local IP")
        case .clipboard:
            DynamicStatWidget(symbol: "doc.on.clipboard", title: "Clipboard", caption: WidgetSystemInfo.clipboardCaption) { WidgetSystemInfo.clipboardValue }
        case .downloads:
            StatWidget(symbol: "arrow.down.circle", title: "Downloads", value: "\(board.downloads.count) files",
                caption: board.downloads.newestName ?? "Downloads")
        }
    }
}

private struct CompactFileShelfWidget: View {
    var shelf: FileShelfState
    let open: (() -> Void)?

    var body: some View {
        Button {
            open?()
        } label: {
            HStack(spacing: 8) {
                ZStack(alignment: .bottomTrailing) {
                    ShelfIconStack(files: Array(shelf.files.prefix(3)))
                        .scaleEffect(0.76, anchor: .leading)
                        .frame(width: 58, height: 38, alignment: .leading)

                    if shelf.files.count > 3 {
                        Text("+\(shelf.files.count - 3)")
                            .font(FoundryTheme.Strip.mono(10, weight: .semibold))
                            .foregroundStyle(FoundryTheme.textOnDarkSurface)
                            .padding(.horizontal, 4)
                            .frame(height: FoundryTheme.Control.glyph)
                            .background(FoundryTheme.scrimStrong)
                            .clipShape(Capsule())
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("File Shelf")
                        .font(FoundryTheme.Strip.text(11, weight: .semibold))
                        .foregroundStyle(FoundryTheme.textPrimary)
                        .lineLimit(1)
                    Text(shelf.compactSummary)
                        .font(FoundryTheme.Strip.text(10, weight: .medium))
                        .foregroundStyle(shelf.isRemovingBackground ? FoundryTheme.accent : FoundryTheme.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.right")
                    .font(FoundryTheme.glyph(9, weight: .bold))
                    .foregroundStyle(FoundryTheme.textQuaternary)
            }
            .padding(.horizontal, 0)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel("File Shelf")
        .accessibilityValue(shelf.compactSummary)
        .accessibilityHint("Open waiting files")
    }
}

private enum WidgetChrome {
    static let glyphRadius: CGFloat = 7
}

private struct StatWidget: View {
    let symbol: String
    let title: String
    let value: String
    let caption: String
    var tint: Color = FoundryTheme.textSecondary

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(FoundryTheme.glyph(14, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 24, height: 24)
                .background(tint.opacity(FoundryTheme.Alpha.tint))
                .clipShape(RoundedRectangle(cornerRadius: WidgetChrome.glyphRadius, style: .continuous))

            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(FoundryTheme.Strip.text(12, weight: .semibold))
                    .foregroundStyle(FoundryTheme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)

                Text(title)
                    .font(FoundryTheme.Strip.text(11, weight: .semibold))
                    .foregroundStyle(FoundryTheme.textQuaternary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .frame(maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityValue("\(value), \(caption)")
    }
}

private struct DynamicStatWidget: View {
    let symbol: String
    let title: String
    let caption: String
    let value: () -> String

    var body: some View {
        TimelineView(.periodic(from: .now, by: 10)) { _ in
            StatWidget(symbol: symbol, title: title, value: value(), caption: caption)
        }
    }
}

private struct AgentWidget: View {
    var agents: AgentMonitorState
    var onOpen: (() -> Void)?

    var body: some View {
        compactContent
    }

    @ViewBuilder
    private var compactContent: some View {
        if let session = agents.visibleSessions.first {
            AgentWidgetRow(session: session, additionalCount: agents.hiddenCount) {
                if let onOpen {
                    onOpen()
                } else {
                    agents.open(session)
                }
            }
        }
    }
}

private struct AgentWidgetRow: View {
    let session: AgentSessionCard
    var additionalCount = 0
    let open: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: open) {
            HStack(spacing: 7) {
                AgentProviderBadge(provider: session.provider)

                VStack(alignment: .leading, spacing: 1) {
                    Text(session.title)
                        .font(FoundryTheme.Strip.text(11, weight: .semibold))
                        .foregroundStyle(FoundryTheme.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Text(statusLabel)
                        .font(FoundryTheme.Strip.text(10, weight: .medium))
                        .foregroundStyle(statusColor)
                        .lineLimit(1)
                }
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)

                if additionalCount > 0 {
                    Text("+\(additionalCount)")
                        .font(FoundryTheme.Strip.text(11, weight: .semibold))
                        .foregroundStyle(FoundryTheme.textSecondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(FoundryTheme.fillTint)
                        .clipShape(Capsule())
                        .fixedSize()
                }

                Image(systemName: "arrow.up.right")
                    .font(FoundryTheme.glyph(8, weight: .bold))
                    .foregroundStyle(FoundryTheme.textTertiary)
                    .opacity(isHovering ? FoundryTheme.Alpha.faint : FoundryTheme.Alpha.half)
                    .frame(width: 16)
            }
            .padding(.horizontal, 0)
            .frame(height: FoundryTheme.Control.field)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(session.title)
        .accessibilityValue(statusLabel)
        .accessibilityHint("Open agent session")
    }

    private var statusLabel: String {
        let label: String
        switch session.status {
        case .needsInput:
            if session.capabilities.contains(.approve) || session.capabilities.contains(.questions) {
                label = "Needs you"
            } else {
                label = "Needs you in \(session.provider.rawValue)"
            }
        case .reviewReady:
            label = session.capabilities.contains(.reply) ? "Review" : "Review in \(session.provider.rawValue)"
        case .completed: label = "Done"
        case .idle, .recent: label = "Recent"
        default: label = session.status.rawValue
        }
        guard let updatedAt = session.updatedAt else { return label }
        return "\(label) · \(Self.relativeFormatter.localizedString(for: updatedAt, relativeTo: Date()))"
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    private var statusColor: Color { session.status.color }
}

private struct AgentProviderBadge: View {
    let provider: AgentProviderKind

    var body: some View {
        AgentProviderIcon(provider: provider, size: 23)
            .frame(width: 23, height: 23)
            .background(FoundryTheme.fillHover)
            .clipShape(RoundedRectangle(cornerRadius: FoundryTheme.Radius.control, style: .continuous))
    }
}

private enum WidgetSystemInfo {
    static var clipboardValue: String {
        guard let text = NSPasteboard.general.string(forType: .string), text.isEmpty == false else { return "Empty" }
        return "\(text.count) chars"
    }

    static var clipboardCaption: String {
        NSPasteboard.general.string(forType: .string)?.components(separatedBy: .newlines).first?.trimmingCharacters(
            in: .whitespacesAndNewlines).isEmpty == false ? "text" : "no text"
    }
}

private struct SystemWidget: View {
    let metrics: SystemMetrics

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            meter(symbol: "cpu", label: "CPU", value: metrics.cpuPercent, display: metrics.cpuDisplay)
            meter(symbol: "memorychip", label: "RAM", value: metrics.memoryPercent, display: metrics.memoryDisplay)
        }
        .frame(maxHeight: .infinity, alignment: .center)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("System load")
        .accessibilityValue("CPU \(metrics.cpuDisplay), memory \(metrics.memoryDisplay)")
    }

    private func meter(symbol: String, label: String, value: Double, display: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: symbol)
                .font(FoundryTheme.glyph(11, weight: .semibold))
                .foregroundStyle(FoundryTheme.textSecondary)
                .frame(width: 15)

            Text(label)
                .font(FoundryTheme.Strip.text(10, weight: .semibold))
                .foregroundStyle(FoundryTheme.textQuaternary)
                .frame(width: 25, alignment: .leading)

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(FoundryTheme.fillTint)
                    Capsule()
                        .fill(FoundryTheme.textTertiary)
                        .frame(width: max(4, geometry.size.width * min(max(value / 100, 0), 1)))
                }
            }
            .frame(height: FoundryTheme.Control.track)

            Text(display)
                .font(FoundryTheme.Strip.mono(10, weight: .semibold))
                .foregroundStyle(FoundryTheme.textSecondary)
                .frame(width: 36, alignment: .trailing)
        }
    }
}

private struct WeatherWidget: View {
    let snapshot: WeatherSnapshot?
    let city: String
    let isLoading: Bool
    let isStale: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: snapshot?.symbol ?? "cloud")
                .font(FoundryTheme.glyph(18, weight: .medium))
                .foregroundStyle(FoundryTheme.textPrimary)
                .frame(width: 27)

            VStack(alignment: .leading, spacing: 1) {
                if let snapshot {
                    Text("\(Int(snapshot.temperature.rounded()))°")
                        .font(FoundryTheme.Strip.text(16, weight: .semibold))
                        .foregroundStyle(FoundryTheme.textPrimary)
                    Text(isStale ? "Offline · last known" : snapshot.condition)
                        .font(FoundryTheme.Strip.text(10, weight: .regular))
                        .foregroundStyle(FoundryTheme.textTertiary)
                        .lineLimit(1)
                } else {
                    Text(isLoading ? "Loading" : city.isEmpty ? "Set city" : "Unavailable")
                        .font(FoundryTheme.Strip.text(12, weight: .medium))
                        .foregroundStyle(FoundryTheme.textSecondary)
                    Text(city.isEmpty ? "Widget settings" : city)
                        .font(FoundryTheme.Strip.text(10, weight: .regular))
                        .foregroundStyle(FoundryTheme.textTertiary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)
        }
        .frame(maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Weather")
        .accessibilityValue(snapshot.map { "\(Int($0.temperature.rounded())) degrees, \($0.condition)" } ?? (city.isEmpty ? "Not configured" : city))
    }
}

private struct StockWidget: View {
    let snapshot: StockSnapshot?
    let symbol: String
    let isLoading: Bool
    let isStale: Bool

    private var changeColor: Color {
        guard let snapshot else { return FoundryTheme.textTertiary }
        return snapshot.changePercent >= 0 ? FoundryTheme.success : FoundryTheme.destructive
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(FoundryTheme.glyph(15, weight: .medium))
                .foregroundStyle(changeColor)
                .frame(width: 25)

            VStack(alignment: .leading, spacing: 1) {
                Text(snapshot?.symbol ?? symbol)
                    .font(FoundryTheme.Strip.text(12, weight: .semibold))
                    .foregroundStyle(FoundryTheme.textPrimary)
                if let snapshot {
                    Text("\(String(format: "%.2f", snapshot.price)) \(isStale ? "· offline" : snapshot.currency)")
                        .font(FoundryTheme.Strip.text(10, weight: .regular))
                        .foregroundStyle(FoundryTheme.textTertiary)
                } else {
                    Text(isLoading ? "Loading" : symbol.isEmpty ? "Set symbol" : "Unavailable")
                        .font(FoundryTheme.Strip.text(10, weight: .regular))
                        .foregroundStyle(FoundryTheme.textTertiary)
                }
            }

            Spacer(minLength: 0)

            if let snapshot {
                Text(String(format: "%+.1f%%", snapshot.changePercent))
                    .font(FoundryTheme.Strip.mono(10, weight: .semibold))
                    .foregroundStyle(changeColor)
            }
        }
        .frame(maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Stock")
        .accessibilityValue(
            snapshot.map { "\($0.symbol), \(String(format: "%.2f", $0.price)), \(String(format: "%+.1f", $0.changePercent)) percent" } ?? (
                symbol.isEmpty ? "Not configured" : symbol))
    }
}

private struct CompactDateWidget: View {
    var body: some View {
        TimelineView(.everyMinute) { context in
            HStack(spacing: 8) {
                Image(systemName: "calendar")
                    .font(FoundryTheme.glyph(14, weight: .semibold))
                    .foregroundStyle(FoundryTheme.textSecondary)
                    .frame(width: 23, height: 23)
                    .background(FoundryTheme.fillTint)
                    .clipShape(RoundedRectangle(cornerRadius: WidgetChrome.glyphRadius, style: .continuous))

                VStack(alignment: .leading, spacing: 1) {
                    Text(context.date.formatted(.dateTime.day()))
                        .font(FoundryTheme.Strip.text(18, weight: .semibold))
                        .foregroundStyle(FoundryTheme.textPrimary)
                        .monospacedDigit()
                    Text(context.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated)))
                        .font(FoundryTheme.Strip.text(11, weight: .semibold))
                        .foregroundStyle(FoundryTheme.textSecondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }
            .frame(maxHeight: .infinity)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Date")
            .accessibilityValue(context.date.formatted(date: .complete, time: .omitted))
        }
    }
}

private struct ClockWidget: View {
    var body: some View {
        TimelineView(.everyMinute) { context in
            HStack(spacing: 8) {
                Image(systemName: "clock")
                    .font(FoundryTheme.glyph(14, weight: .semibold))
                    .foregroundStyle(FoundryTheme.textSecondary)
                    .frame(width: 23, height: 23)
                    .background(FoundryTheme.fillTint)
                    .clipShape(RoundedRectangle(cornerRadius: WidgetChrome.glyphRadius, style: .continuous))

                VStack(alignment: .leading, spacing: 1) {
                    Text(Self.time.string(from: context.date))
                        .font(FoundryTheme.Strip.mono(12, weight: .semibold))
                        .foregroundStyle(FoundryTheme.textPrimary)
                    Text(TimeZone.current.localizedName(for: .shortStandard, locale: .current) ?? TimeZone.current.identifier)
                        .font(FoundryTheme.Strip.text(11, weight: .semibold))
                        .foregroundStyle(FoundryTheme.textQuaternary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }
            .frame(maxHeight: .infinity)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Clock")
            .accessibilityValue(Self.time.string(from: context.date))
        }
    }

    private static let time: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()
}
