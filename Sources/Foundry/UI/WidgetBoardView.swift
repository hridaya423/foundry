import AppKit
import SwiftUI

struct WidgetBoardView: View {
    @ObservedObject var board: WidgetBoardState

    var body: some View {
        WidgetGridLayout(spacing: 8) {
            ForEach(arrangedWidgets) { kind in
                widget(for: kind)
                    .widgetCell(kind.footprint)
            }
        }
    }

    private var arrangedWidgets: [WidgetKind] {
        let order = Dictionary(uniqueKeysWithValues: board.homeWidgets.enumerated().map { ($1, $0) })
        return board.homeWidgets.sorted {
            if $0.homePriority != $1.homePriority { return $0.homePriority < $1.homePriority }
            return order[$0, default: 0] < order[$1, default: 0]
        }
    }

    private func widget(for kind: WidgetKind) -> some View {
        WidgetCard {
            widgetContent(for: kind)
        }
    }

    @ViewBuilder
    private func widgetContent(for kind: WidgetKind) -> some View {
        switch kind {
        case .calendar:
            CalendarWidget()
        case .date:
            DateWidget()
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
            DynamicStatWidget(symbol: "arrow.down.circle", title: "Downloads", caption: WidgetSystemInfo.downloadsCaption) { WidgetSystemInfo.downloadsValue }
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

private struct WidgetCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(10)
            .background(Color.white.opacity(0.045))
            .clipShape(RoundedRectangle(cornerRadius: WidgetChrome.cardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: WidgetChrome.cardRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.07), lineWidth: 1)
            )
    }
}

private enum WidgetChrome {
    static let cardRadius: CGFloat = 12
    static let glyphRadius: CGFloat = 7
}

private enum WidgetFootprint {
    case hero
    case wide
    case medium
    case tall
    case flex

    var isFlexible: Bool { self == .flex }

    func size(columns: Int) -> (span: Int, height: Int) {
        switch self {
        case .hero:
            return (min(2, columns), 3)
        case .wide:
            return (columns >= 6 ? 3 : min(2, columns), 2)
        case .medium:
            return (columns >= 4 ? 2 : 1, 1)
        case .tall:
            return (columns >= 5 ? 1 : min(2, columns), columns >= 5 ? 2 : 1)
        case .flex:
            return (1, 1)
        }
    }
}

struct WidgetGridLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let width = proposal.width ?? 0
        return CGSize(width: width, height: frames(for: subviews, width: width).height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        let result = frames(for: subviews, width: bounds.width)
        for (index, frame) in result.frames.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                proposal: ProposedViewSize(width: frame.width, height: frame.height)
            )
        }
    }

    private func frames(for subviews: Subviews, width: CGFloat) -> (frames: [CGRect], height: CGFloat) {
        guard width > 0 else { return ([], 0) }
        let metrics = gridMetrics(for: width)
        let columns = metrics.columns
        let unitHeight = metrics.unitHeight
        let columnWidth = (width - spacing * CGFloat(columns - 1)) / CGFloat(columns)
        var columnUnits = Array(repeating: 0, count: columns)
        var frames: [CGRect] = []
        let footprints = subviews.map { $0[WidgetFootprintKey.self] }
        frames.reserveCapacity(subviews.count)

        for index in subviews.indices {
            let remainingFlex = footprints[index...].filter(\.isFlexible).count
            let placement = placement(for: footprints[index], columns: columns, columnUnits: columnUnits, remainingFlex: remainingFlex)
            let bestColumn = placement.column
            let bestRow = placement.row
            let span = placement.span
            let heightUnits = placement.height

            let x = CGFloat(bestColumn) * (columnWidth + spacing)
            let y = CGFloat(bestRow) * (unitHeight + spacing)
            let cellWidth = columnWidth * CGFloat(span) + spacing * CGFloat(span - 1)
            let cellHeight = unitHeight * CGFloat(heightUnits) + spacing * CGFloat(heightUnits - 1)
            frames.append(CGRect(x: x, y: y, width: cellWidth, height: cellHeight))

            for column in bestColumn..<(bestColumn + span) {
                columnUnits[column] = bestRow + heightUnits
            }
        }

        let maxUnits = columnUnits.max() ?? 0
        let height = maxUnits == 0 ? 0 : CGFloat(maxUnits) * unitHeight + CGFloat(maxUnits - 1) * spacing
        return (frames, height)
    }

    private func gridMetrics(for width: CGFloat) -> (columns: Int, unitHeight: CGFloat) {
        if width < 460 { return (3, 52) }
        if width < 640 { return (4, 52) }
        return (6, 54)
    }

    private func placement(for footprint: WidgetFootprint, columns: Int, columnUnits: [Int], remainingFlex: Int) -> (column: Int, row: Int, span: Int, height: Int) {
        if footprint.isFlexible {
            return flexiblePlacement(columns: columns, columnUnits: columnUnits, remainingFlex: max(remainingFlex, 1))
        }

        let size = footprint.size(columns: columns)
        let span = min(max(size.span, 1), columns)
        var bestColumn = 0
        var bestRow = Int.max
        for start in 0...(columns - span) {
            let row = (start..<(start + span)).map { columnUnits[$0] }.max() ?? 0
            if row < bestRow {
                bestRow = row
                bestColumn = start
            }
        }
        return (bestColumn, bestRow, span, max(size.height, 1))
    }

    private func flexiblePlacement(columns: Int, columnUnits: [Int], remainingFlex: Int) -> (column: Int, row: Int, span: Int, height: Int) {
        let maxRow = columnUnits.max() ?? 0
        for row in 0...maxRow {
            if let run = bestOpenRun(in: columnUnits, at: row) {
                let slots = min(remainingFlex, run.length)
                let span = Int(ceil(Double(run.length) / Double(max(slots, 1))))
                return (run.start, row, max(span, 1), 1)
            }
        }
        return (0, maxRow, max(1, Int(ceil(Double(columns) / Double(max(remainingFlex, 1))))), 1)
    }

    private func bestOpenRun(in columnUnits: [Int], at row: Int) -> (start: Int, length: Int)? {
        var best: (start: Int, length: Int)?
        var start: Int?
        for column in 0..<columnUnits.count {
            if columnUnits[column] <= row {
                if start == nil { start = column }
            } else if let currentStart = start {
                best = betterRun(best, (currentStart, column - currentStart))
                start = nil
            }
        }
        if let currentStart = start {
            best = betterRun(best, (currentStart, columnUnits.count - currentStart))
        }
        return best
    }

    private func betterRun(_ current: (start: Int, length: Int)?, _ candidate: (start: Int, length: Int)) -> (start: Int, length: Int) {
        guard let current else { return candidate }
        if candidate.length != current.length { return candidate.length > current.length ? candidate : current }
        return candidate.start < current.start ? candidate : current
    }
}

private struct WidgetFootprintKey: LayoutValueKey {
    static let defaultValue = WidgetFootprint.flex
}

private extension View {
    func widgetCell(_ footprint: WidgetFootprint) -> some View {
        layoutValue(key: WidgetFootprintKey.self, value: footprint)
    }
}

private extension WidgetKind {
    var homePriority: Int {
        switch self {
        case .calendar: return 0
        case .system: return 1
        case .weather: return 2
        case .stock: return 3
        case .battery: return 4
        case .date: return 5
        case .disk: return 6
        case .uptime: return 7
        case .thermal: return 8
        case .clock: return 9
        case .cpu: return 10
        case .memory: return 11
        case .network: return 12
        case .loadAverage: return 13
        case .clipboard: return 14
        case .downloads: return 15
        case .diskUsage: return 16
        case .boot: return 17
        case .activeApp: return 18
        case .display: return 19
        case .device: return 20
        case .osVersion: return 21
        case .user: return 22
        case .timeZone: return 23
        case .host: return 24
        case .cores: return 25
        }
    }

    var footprint: WidgetFootprint {
        switch self {
        case .calendar:
            return .hero
        case .system:
            return .wide
        case .weather, .stock, .activeApp, .display, .user, .timeZone, .boot, .host, .downloads:
            return .medium
        case .date:
            return .tall
        case .clock, .battery, .disk, .uptime, .thermal, .cpu, .memory, .loadAverage, .diskUsage, .network, .clipboard, .device, .osVersion, .cores:
            return .flex
        }
    }
}

private struct StatWidget: View {
    let symbol: String
    let title: String
    let value: String
    let caption: String
    var tint: Color = FoundryTheme.secondaryText

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 24, height: 24)
                .background(tint.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: WidgetChrome.glyphRadius, style: .continuous))

            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(FoundryTheme.body(size: 13, weight: .semibold))
                    .foregroundStyle(FoundryTheme.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)

                Text(title)
                    .font(FoundryTheme.body(size: 10, weight: .semibold))
                    .foregroundStyle(FoundryTheme.faintText)
                    .lineLimit(1)
            }

        }
        .frame(maxHeight: .infinity)
    }
}

private struct DynamicStatWidget: View {
    let symbol: String
    let title: String
    let caption: String
    let value: () -> String

    var body: some View {
        TimelineView(.periodic(from: .now, by: 2)) { _ in
            StatWidget(symbol: symbol, title: title, value: value(), caption: caption)
        }
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

    static var downloadsValue: String {
        "\(downloads.count) files"
    }

    static var downloadsCaption: String {
        downloads.first?.lastPathComponent ?? "Downloads"
    }

    private static var downloads: [URL] {
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
        let files = (try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        return files.sorted {
            let left = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let right = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return left > right
        }
    }
}

private struct SystemWidget: View {
    let metrics: SystemMetrics

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            meter(symbol: "cpu", label: "CPU", value: metrics.cpuPercent, display: metrics.cpuDisplay)
            meter(symbol: "memorychip", label: "RAM", value: metrics.memoryPercent, display: metrics.memoryDisplay)
        }
        .frame(maxHeight: .infinity, alignment: .center)
    }

    private func meter(symbol: String, label: String, value: Double, display: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(FoundryTheme.secondaryText)
                .frame(width: 16)

            Text(label)
                .font(FoundryTheme.body(size: 11, weight: .semibold))
                .foregroundStyle(FoundryTheme.faintText)
                .frame(width: 28, alignment: .leading)

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.08))
                    Capsule()
                        .fill(Color.white.opacity(0.55))
                        .frame(width: max(4, geometry.size.width * min(max(value / 100, 0), 1)))
                }
            }
            .frame(height: 5)

            Text(display)
                .font(FoundryTheme.body(size: 11, weight: .semibold))
                .foregroundStyle(FoundryTheme.secondaryText)
                .monospacedDigit()
                .frame(width: 40, alignment: .trailing)
        }
    }
}

private struct WeatherWidget: View {
    let snapshot: WeatherSnapshot?
    let city: String
    let isLoading: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: snapshot?.symbol ?? "cloud")
                .font(.system(size: 21, weight: .medium))
                .foregroundStyle(FoundryTheme.primaryText)
                .frame(width: 34)

            VStack(alignment: .leading, spacing: 2) {
                if let snapshot {
                    Text("\(Int(snapshot.temperature.rounded()))°")
                        .font(FoundryTheme.display(size: 18, weight: .semibold))
                        .foregroundStyle(FoundryTheme.primaryText)
                    Text(snapshot.condition)
                        .font(FoundryTheme.body(size: 11, weight: .regular))
                        .foregroundStyle(FoundryTheme.mutedText)
                        .lineLimit(1)
                } else {
                    Text(isLoading ? "Loading…" : "Set city")
                        .font(FoundryTheme.body(size: 14, weight: .medium))
                        .foregroundStyle(FoundryTheme.secondaryText)
                    Text(city.isEmpty ? "Widget settings" : city)
                        .font(FoundryTheme.body(size: 12, weight: .regular))
                        .foregroundStyle(FoundryTheme.mutedText)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)

            if let snapshot, snapshot.city.isEmpty == false {
                Text(snapshot.city)
                    .font(FoundryTheme.body(size: 11, weight: .medium))
                    .foregroundStyle(FoundryTheme.faintText)
                    .lineLimit(1)
            }
        }
        .frame(maxHeight: .infinity)
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
        HStack(spacing: 10) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(changeColor)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(snapshot?.symbol ?? symbol)
                    .font(FoundryTheme.body(size: 13, weight: .semibold))
                    .foregroundStyle(FoundryTheme.primaryText)
                if let snapshot {
                    Text("\(String(format: "%.2f", snapshot.price)) \(snapshot.currency)")
                        .font(FoundryTheme.body(size: 11, weight: .regular))
                        .foregroundStyle(FoundryTheme.mutedText)
                } else {
                    Text(isLoading ? "Loading…" : "Set symbol")
                        .font(FoundryTheme.body(size: 12, weight: .regular))
                        .foregroundStyle(FoundryTheme.mutedText)
                }
            }

            Spacer(minLength: 0)

            if let snapshot {
                Text(String(format: "%+.2f%%", snapshot.changePercent))
                    .font(FoundryTheme.body(size: 12, weight: .semibold))
                    .foregroundStyle(changeColor)
                    .monospacedDigit()
            }
        }
        .frame(maxHeight: .infinity)
    }
}

private struct DateWidget: View {
    var body: some View {
        TimelineView(.everyMinute) { context in
            VStack(alignment: .leading, spacing: 0) {
                Image(systemName: "calendar")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(FoundryTheme.secondaryText)
                    .frame(width: 28, height: 28)
                    .background(Color.white.opacity(0.09))
                    .clipShape(RoundedRectangle(cornerRadius: WidgetChrome.glyphRadius, style: .continuous))

                Spacer(minLength: 8)

                Text(Self.day.string(from: context.date))
                    .font(FoundryTheme.display(size: 30, weight: .semibold))
                    .foregroundStyle(FoundryTheme.primaryText)
                    .monospacedDigit()
                    .lineLimit(1)

                Text(Self.weekdayMonth.string(from: context.date))
                    .font(FoundryTheme.body(size: 12, weight: .semibold))
                    .foregroundStyle(FoundryTheme.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                Text(Self.year.string(from: context.date))
                    .font(FoundryTheme.body(size: 10, weight: .semibold))
                    .foregroundStyle(FoundryTheme.faintText)
                    .lineLimit(1)
            }
            .frame(maxHeight: .infinity)
        }
    }

    private static let day: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "d"
        return formatter
    }()

    private static let weekdayMonth: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE MMM"
        return formatter
    }()

    private static let year: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy"
        return formatter
    }()
}

private struct ClockWidget: View {
    var body: some View {
        TimelineView(.everyMinute) { context in
            HStack(spacing: 10) {
                Image(systemName: "clock")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(FoundryTheme.secondaryText)
                    .frame(width: 24, height: 24)
                    .background(Color.white.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: WidgetChrome.glyphRadius, style: .continuous))

                VStack(alignment: .leading, spacing: 1) {
                    Text(Self.time.string(from: context.date))
                        .font(FoundryTheme.body(size: 14, weight: .semibold))
                        .foregroundStyle(FoundryTheme.primaryText)
                        .monospacedDigit()
                    Text(TimeZone.current.localizedName(for: .shortStandard, locale: .current) ?? TimeZone.current.identifier)
                        .font(FoundryTheme.body(size: 10, weight: .semibold))
                        .foregroundStyle(FoundryTheme.faintText)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }
            .frame(maxHeight: .infinity)
        }
    }

    private static let time: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()
}

private struct CalendarWidget: View {
    var body: some View {
        TimelineView(.everyMinute) { context in
            GeometryReader { geometry in
                content(for: context.date, size: geometry.size)
            }
        }
    }

    private func content(for date: Date, size: CGSize) -> some View {
        let model = MonthModel(reference: date)
        let rowGap: CGFloat = model.weeks.count > 5 ? 2 : 4
        let rowHeight = max(15, min(18, (size.height - 50 - rowGap * CGFloat(max(model.weeks.count - 1, 0))) / CGFloat(max(model.weeks.count, 1))))

        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text(model.month)
                    .font(FoundryTheme.body(size: 12, weight: .bold))
                    .foregroundStyle(FoundryTheme.primaryText)
                    .tracking(0.8)

                Text(model.year)
                    .font(FoundryTheme.body(size: 11, weight: .semibold))
                    .foregroundStyle(FoundryTheme.faintText)

                Spacer(minLength: 0)
            }

            Spacer(minLength: 7)

            HStack(spacing: 0) {
                ForEach(Array(model.weekdays.enumerated()), id: \.offset) { _, symbol in
                    Text(symbol)
                        .font(FoundryTheme.body(size: 9.5, weight: .bold))
                        .foregroundStyle(FoundryTheme.faintText)
                        .frame(maxWidth: .infinity)
                }
            }

            Spacer(minLength: 5)

            VStack(spacing: rowGap) {
                ForEach(model.weeks) { week in
                    HStack(spacing: 0) {
                        ForEach(week.cells) { cell in
                            DayCell(cell: cell, height: rowHeight)
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
            .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct DayCell: View {
    let cell: MonthModel.DayCell
    let height: CGFloat

    var body: some View {
        ZStack {
            if cell.isToday {
                Circle()
                    .fill(FoundryTheme.primaryText)
                    .frame(width: height + 5, height: height + 5)
                    .shadow(color: Color.white.opacity(0.18), radius: 5, x: 0, y: 0)
            }
            if let day = cell.day {
                Text("\(day)")
                    .font(FoundryTheme.body(size: cell.isToday ? 10.5 : 10, weight: cell.isToday ? .bold : .semibold))
                    .foregroundStyle(cell.isToday ? Color.black.opacity(0.85) : FoundryTheme.secondaryText)
                    .monospacedDigit()
            }
        }
        .frame(height: height)
    }
}

private struct MonthModel {
    struct DayCell: Identifiable {
        let id: Int
        let day: Int?
        let isToday: Bool
    }

    struct Week: Identifiable {
        let id: Int
        let cells: [DayCell]
    }

    let month: String
    let year: String
    let weekdays: [String]
    let weeks: [Week]

    init(reference: Date) {
        var calendar = Calendar.current
        calendar.firstWeekday = 2
        weekdays = ["M", "T", "W", "T", "F", "S", "S"]

        let monthFormatter = DateFormatter()
        monthFormatter.dateFormat = "MMMM"
        let yearFormatter = DateFormatter()
        yearFormatter.dateFormat = "yyyy"
        let today = calendar.startOfDay(for: reference)
        let monthComponents = calendar.dateComponents([.year, .month], from: today)
        let firstOfMonth = calendar.date(from: monthComponents) ?? today
        month = monthFormatter.string(from: firstOfMonth).uppercased()
        year = yearFormatter.string(from: firstOfMonth)

        let dayCount = calendar.range(of: .day, in: .month, for: firstOfMonth)?.count ?? 30
        let weekdayOfFirst = calendar.component(.weekday, from: firstOfMonth)
        let leading = (weekdayOfFirst - calendar.firstWeekday + 7) % 7
        let todayDay = calendar.component(.day, from: today)
        let rowCount = Int((Double(leading + dayCount) / 7).rounded(.up))

        var weeks: [Week] = []
        for row in 0..<max(rowCount, 1) {
            var cells: [DayCell] = []
            for column in 0..<7 {
                let index = row * 7 + column
                let dayNumber = index - leading + 1
                if dayNumber >= 1 && dayNumber <= dayCount {
                    cells.append(DayCell(id: index, day: dayNumber, isToday: dayNumber == todayDay))
                } else {
                    cells.append(DayCell(id: index, day: nil, isToday: false))
                }
            }
            weeks.append(Week(id: row, cells: cells))
        }
        self.weeks = weeks
    }
}
