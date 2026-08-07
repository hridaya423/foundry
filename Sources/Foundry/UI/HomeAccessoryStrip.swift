import AppKit
import SwiftUI

struct HomeAccessoryStrip: View {
    @ObservedObject var board: WidgetBoardState
    @ObservedObject var agents: AgentMonitorState
    @ObservedObject var fileShelf: FileShelfState
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
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.032))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
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
            .fill(Color.white.opacity(0.09))
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
            StatWidget(symbol: board.metrics.batterySymbol, title: "Battery", value: board.metrics.batteryDisplay, caption: board.metrics.batteryStateLabel, tint: board.metrics.batteryTint)
        case .disk:
            StatWidget(symbol: "internaldrive", title: "Storage", value: board.metrics.diskDisplay, caption: "free")
        case .uptime:
            StatWidget(symbol: "clock.arrow.circlepath", title: "Uptime", value: board.metrics.uptimeDisplay, caption: "since boot")
        case .thermal:
            StatWidget(symbol: "fanblades", title: "Thermal", value: board.metrics.thermalDisplay, caption: "pressure", tint: board.metrics.thermalTint)
        case .weather:
            WeatherWidget(snapshot: board.weather, city: board.config.weatherCity, isLoading: board.isWeatherLoading)
        case .stock:
            StockWidget(snapshot: board.stock, symbol: board.config.stockSymbol, isLoading: board.isStockLoading)
        case .cpu:
            StatWidget(symbol: "cpu", title: "CPU", value: board.metrics.cpuDisplay, caption: "current")
        case .memory:
            StatWidget(symbol: "memorychip", title: "Memory", value: board.metrics.memoryDisplay, caption: board.metrics.memoryUsedDisplay)
        case .loadAverage:
            StatWidget(symbol: "waveform.path.ecg", title: "Unix Load", value: board.metrics.loadAverageDisplay, caption: "1 min avg")
        case .diskUsage:
            StatWidget(symbol: "chart.pie", title: "Disk Used", value: board.metrics.diskUsedDisplay, caption: "boot volume")
        case .network:
            StatWidget(symbol: "network", title: "Network", value: board.metrics.localIPAddressDisplay, caption: "local IP")
        case .clipboard:
            DynamicStatWidget(symbol: "doc.on.clipboard", title: "Clipboard", caption: WidgetSystemInfo.clipboardCaption) { WidgetSystemInfo.clipboardValue }
        case .downloads:
            StatWidget(symbol: "arrow.down.circle", title: "Downloads", value: "\(board.downloads.count) files", caption: board.downloads.newestName ?? "Downloads")
        case .activeApp:
            DynamicStatWidget(symbol: "macwindow", title: "Active App", caption: "frontmost") { WidgetSystemInfo.activeAppName }
        case .device:
            StatWidget(symbol: "desktopcomputer", title: "Device", value: WidgetSystemInfo.deviceName, caption: "Mac")
        case .osVersion:
            StatWidget(symbol: "apple.logo", title: "macOS", value: WidgetSystemInfo.osVersion, caption: "system")
        case .user:
            StatWidget(symbol: "person.crop.circle", title: "User", value: WidgetSystemInfo.userName, caption: "account")
        case .timeZone:
            DynamicStatWidget(symbol: "globe", title: "Time Zone", caption: WidgetSystemInfo.timeZoneCaption) { WidgetSystemInfo.timeZoneValue }
        case .display:
            DynamicStatWidget(symbol: "display", title: "Display", caption: WidgetSystemInfo.displayCaption) { WidgetSystemInfo.displayValue }
        case .boot:
            StatWidget(symbol: "power", title: "Boot", value: board.metrics.bootDateDisplay, caption: board.metrics.bootClockDisplay)
        case .host:
            StatWidget(symbol: "bonjour", title: "Host", value: WidgetSystemInfo.hostName, caption: "network")
        case .cores:
            StatWidget(symbol: "cpu.fill", title: "Cores", value: "\(ProcessInfo.processInfo.processorCount)", caption: "processors")
        }
    }
}

private struct CompactFileShelfWidget: View {
    @ObservedObject var shelf: FileShelfState
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
                            .font(FoundryTheme.mono(size: 9, weight: .bold))
                            .foregroundStyle(FoundryTheme.primaryText)
                            .padding(.horizontal, 4)
                            .frame(height: 16)
                            .background(Color.black.opacity(0.55))
                            .clipShape(Capsule())
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("File Shelf")
                        .font(FoundryTheme.body(size: 11, weight: .semibold))
                        .foregroundStyle(FoundryTheme.primaryText)
                        .lineLimit(1)
                    Text(shelf.compactSummary)
                        .font(FoundryTheme.body(size: 9.5, weight: .medium))
                        .foregroundStyle(shelf.isRemovingBackground ? FoundryTheme.accentTint : FoundryTheme.secondaryText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(FoundryTheme.faintText)
            }
            .padding(.horizontal, 0)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle())
        .pointerCursor()
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
    var tint: Color = FoundryTheme.secondaryText

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 24, height: 24)
                .background(tint.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: WidgetChrome.glyphRadius, style: .continuous))

            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(FoundryTheme.body(size: 12, weight: .semibold))
                    .foregroundStyle(FoundryTheme.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)

                Text(title)
                    .font(FoundryTheme.body(size: 9.5, weight: .semibold))
                    .foregroundStyle(FoundryTheme.faintText)
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
    @ObservedObject var agents: AgentMonitorState
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
                        .font(FoundryTheme.body(size: 11, weight: .semibold))
                        .foregroundStyle(FoundryTheme.primaryText)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Text(statusLabel)
                        .font(FoundryTheme.body(size: 9.5, weight: .medium))
                        .foregroundStyle(statusColor)
                        .lineLimit(1)
                }
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)

                if additionalCount > 0 {
                    Text("+\(additionalCount)")
                        .font(FoundryTheme.body(size: 9, weight: .bold))
                        .foregroundStyle(FoundryTheme.secondaryText)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.white.opacity(0.08))
                        .clipShape(Capsule())
                        .fixedSize()
                }

                Image(systemName: "arrow.up.right")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(FoundryTheme.mutedText)
                    .opacity(isHovering ? 0.9 : 0.35)
                    .frame(width: 16)
            }
            .padding(.horizontal, 0)
            .frame(height: 38)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .pointerCursor()
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
}

private struct AgentProviderBadge: View {
    let provider: AgentProviderKind

    var body: some View {
        AgentProviderIcon(provider: provider, size: 23)
            .frame(width: 23, height: 23)
            .background(Color.white.opacity(0.055))
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}

private enum WidgetSystemInfo {
    static var activeAppName: String {
        NSWorkspace.shared.frontmostApplication?.localizedName ?? "None"
    }

    static var deviceName: String {
        Host.current().localizedName ?? ProcessInfo.processInfo.hostName
    }

    static var hostName: String {
        ProcessInfo.processInfo.hostName
    }

    static var osVersion: String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        if version.patchVersion > 0 { return "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)" }
        return "\(version.majorVersion).\(version.minorVersion)"
    }

    static var userName: String {
        let fullName = NSFullUserName()
        return fullName.isEmpty ? NSUserName() : fullName
    }

    static var timeZoneValue: String {
        TimeZone.current.abbreviation() ?? "GMT"
    }

    static var timeZoneCaption: String {
        TimeZone.current.identifier
    }

    static var displayValue: String {
        guard let screen = NSScreen.main else { return "—" }
        let scale = screen.backingScaleFactor
        return "\(Int(screen.frame.width * scale))×\(Int(screen.frame.height * scale))"
    }

    static var displayCaption: String {
        guard let screen = NSScreen.main else { return "main" }
        return "\(String(format: "%.0fx", screen.backingScaleFactor)) main"
    }

    static var clipboardValue: String {
        guard let text = NSPasteboard.general.string(forType: .string), text.isEmpty == false else { return "Empty" }
        return "\(text.count) chars"
    }

    static var clipboardCaption: String {
        NSPasteboard.general.string(forType: .string)?.components(separatedBy: .newlines).first?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? "text" : "no text"
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
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(FoundryTheme.secondaryText)
                .frame(width: 15)

            Text(label)
                .font(FoundryTheme.body(size: 10, weight: .semibold))
                .foregroundStyle(FoundryTheme.faintText)
                .frame(width: 25, alignment: .leading)

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.08))
                    Capsule()
                        .fill(Color.white.opacity(0.55))
                        .frame(width: max(4, geometry.size.width * min(max(value / 100, 0), 1)))
                }
            }
            .frame(height: 5)

            Text(display)
                .font(FoundryTheme.mono(size: 10, weight: .semibold))
                .foregroundStyle(FoundryTheme.secondaryText)
                .frame(width: 36, alignment: .trailing)
        }
    }
}

private struct WeatherWidget: View {
    let snapshot: WeatherSnapshot?
    let city: String
    let isLoading: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: snapshot?.symbol ?? "cloud")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(FoundryTheme.primaryText)
                .frame(width: 27)

            VStack(alignment: .leading, spacing: 1) {
                if let snapshot {
                    Text("\(Int(snapshot.temperature.rounded()))°")
                        .font(FoundryTheme.display(size: 16, weight: .semibold))
                        .foregroundStyle(FoundryTheme.primaryText)
                    Text(snapshot.condition)
                        .font(FoundryTheme.body(size: 10, weight: .regular))
                        .foregroundStyle(FoundryTheme.mutedText)
                        .lineLimit(1)
                } else {
                    Text(isLoading ? "Loading" : city.isEmpty ? "Set city" : "Unavailable")
                        .font(FoundryTheme.body(size: 12, weight: .medium))
                        .foregroundStyle(FoundryTheme.secondaryText)
                    Text(city.isEmpty ? "Widget settings" : city)
                        .font(FoundryTheme.body(size: 10, weight: .regular))
                        .foregroundStyle(FoundryTheme.mutedText)
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

    private var changeColor: Color {
        guard let snapshot else { return FoundryTheme.mutedText }
        return snapshot.changePercent >= 0 ? Color.green.opacity(0.9) : Color.red.opacity(0.9)
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(changeColor)
                .frame(width: 25)

            VStack(alignment: .leading, spacing: 1) {
                Text(snapshot?.symbol ?? symbol)
                    .font(FoundryTheme.body(size: 12, weight: .semibold))
                    .foregroundStyle(FoundryTheme.primaryText)
                if let snapshot {
                    Text("\(String(format: "%.2f", snapshot.price)) \(snapshot.currency)")
                        .font(FoundryTheme.body(size: 10, weight: .regular))
                        .foregroundStyle(FoundryTheme.mutedText)
                } else {
                    Text(isLoading ? "Loading" : symbol.isEmpty ? "Set symbol" : "Unavailable")
                        .font(FoundryTheme.body(size: 10, weight: .regular))
                        .foregroundStyle(FoundryTheme.mutedText)
                }
            }

            Spacer(minLength: 0)

            if let snapshot {
                Text(String(format: "%+.1f%%", snapshot.changePercent))
                    .font(FoundryTheme.mono(size: 10, weight: .semibold))
                    .foregroundStyle(changeColor)
            }
        }
        .frame(maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Stock")
        .accessibilityValue(snapshot.map { "\($0.symbol), \(String(format: "%.2f", $0.price)), \(String(format: "%+.1f", $0.changePercent)) percent" } ?? (symbol.isEmpty ? "Not configured" : symbol))
    }
}

private struct CompactDateWidget: View {
    var body: some View {
        TimelineView(.everyMinute) { context in
            HStack(spacing: 8) {
                Image(systemName: "calendar")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(FoundryTheme.secondaryText)
                    .frame(width: 23, height: 23)
                    .background(Color.white.opacity(0.09))
                    .clipShape(RoundedRectangle(cornerRadius: WidgetChrome.glyphRadius, style: .continuous))

                VStack(alignment: .leading, spacing: 1) {
                    Text(context.date.formatted(.dateTime.day()))
                        .font(FoundryTheme.display(size: 18, weight: .semibold))
                        .foregroundStyle(FoundryTheme.primaryText)
                        .monospacedDigit()
                    Text(context.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated)))
                        .font(FoundryTheme.body(size: 9.5, weight: .semibold))
                        .foregroundStyle(FoundryTheme.secondaryText)
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
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(FoundryTheme.secondaryText)
                    .frame(width: 23, height: 23)
                    .background(Color.white.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: WidgetChrome.glyphRadius, style: .continuous))

                VStack(alignment: .leading, spacing: 1) {
                    Text(Self.time.string(from: context.date))
                        .font(FoundryTheme.mono(size: 12, weight: .semibold))
                        .foregroundStyle(FoundryTheme.primaryText)
                    Text(TimeZone.current.localizedName(for: .shortStandard, locale: .current) ?? TimeZone.current.identifier)
                        .font(FoundryTheme.body(size: 9.5, weight: .semibold))
                        .foregroundStyle(FoundryTheme.faintText)
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
