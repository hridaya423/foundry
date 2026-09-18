import Foundation

enum WidgetCategory: String, CaseIterable, Sendable {
    case workspace
    case system
    case web

    var title: String {
        switch self {
        case .workspace: return "Workspace"
        case .system: return "System"
        case .web: return "Web"
        }
    }
}

enum WidgetKind: String, Codable, CaseIterable, Sendable, Identifiable {
    case agents
    case calendar
    case date
    case clock
    case system
    case battery
    case disk
    case uptime
    case thermal
    case weather
    case stock
    case cpu
    case memory
    case loadAverage
    case diskUsage
    case network
    case clipboard
    case downloads

    var id: String { rawValue }

    var category: WidgetCategory {
        switch self {
        case .agents, .calendar, .date, .clock, .uptime, .clipboard, .downloads:
            return .workspace
        case .system, .cpu, .memory, .loadAverage, .thermal, .disk, .diskUsage, .battery, .network:
            return .system
        case .weather, .stock:
            return .web
        }
    }

    var title: String {
        switch self {
        case .agents: return "Agents"
        case .calendar: return "Calendar"
        case .date: return "Date"
        case .clock: return "Clock"
        case .system: return "System Load"
        case .battery: return "Battery"
        case .disk: return "Disk"
        case .uptime: return "Uptime"
        case .thermal: return "Thermal"
        case .weather: return "Weather"
        case .stock: return "Stock"
        case .cpu: return "CPU"
        case .memory: return "Memory"
        case .loadAverage: return "System Load"
        case .diskUsage: return "Disk Used"
        case .network: return "Network"
        case .clipboard: return "Clipboard"
        case .downloads: return "Downloads"
        }
    }

    var summary: String {
        switch self {
        case .agents: return "Recent local coding sessions"
        case .calendar: return "Month at a glance"
        case .date: return "Today's day and date"
        case .clock: return "Current time and time zone"
        case .system: return "Live CPU and memory load"
        case .battery: return "Charge level and state"
        case .disk: return "Free space on Macintosh HD"
        case .uptime: return "Time since last boot"
        case .thermal: return "System thermal pressure"
        case .weather: return "Current conditions for a city"
        case .stock: return "Latest quote for a ticker"
        case .cpu: return "Current processor usage"
        case .memory: return "Physical memory usage"
        case .loadAverage: return "One-minute Unix load average"
        case .diskUsage: return "Used boot volume space"
        case .network: return "Primary local IP address"
        case .clipboard: return "Current clipboard text size"
        case .downloads: return "Recent files in Downloads"
        }
    }

    var symbol: String {
        switch self {
        case .agents: return "sparkles.rectangle.stack"
        case .calendar: return "calendar"
        case .date: return "calendar.badge.clock"
        case .clock: return "clock"
        case .system: return "cpu"
        case .battery: return "battery.100"
        case .disk: return "internaldrive"
        case .uptime: return "clock.arrow.circlepath"
        case .thermal: return "fanblades"
        case .weather: return "cloud.sun"
        case .stock: return "chart.line.uptrend.xyaxis"
        case .cpu: return "cpu"
        case .memory: return "memorychip"
        case .loadAverage: return "waveform.path.ecg"
        case .diskUsage: return "chart.pie"
        case .network: return "network"
        case .clipboard: return "doc.on.clipboard"
        case .downloads: return "arrow.down.circle"
        }
    }

    var conflicts: Set<WidgetKind> {
        switch self {
        case .system:
            return [.cpu, .memory]
        case .cpu, .memory:
            return [.system]
        case .disk:
            return [.diskUsage]
        case .diskUsage:
            return [.disk]
        default:
            return []
        }
    }
}

struct WidgetBoardConfig: Codable, Equatable {
    static let maxEnabled = 4

    var enabled: [WidgetKind]
    var weatherCity: String
    var stockSymbol: String

    init(enabled: [WidgetKind], weatherCity: String, stockSymbol: String) {
        self.enabled = enabled
        self.weatherCity = weatherCity
        self.stockSymbol = stockSymbol
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let raw = try container.decodeIfPresent([String].self, forKey: .enabled) ?? []
        enabled = raw.compactMap(WidgetKind.init(rawValue:))
        weatherCity = try container.decodeIfPresent(String.self, forKey: .weatherCity) ?? ""
        stockSymbol = try container.decodeIfPresent(String.self, forKey: .stockSymbol) ?? ""
    }

    static let `default` = WidgetBoardConfig(
        enabled: [.agents, .calendar, .system, .battery],
        weatherCity: "",
        stockSymbol: ""
    )

    static let legacyExpandedDefault = WidgetBoardConfig(
        enabled: [.agents, .calendar, .system, .battery, .date, .disk, .uptime, .clock],
        weatherCity: "",
        stockSymbol: ""
    )

    static let legacyDefault = WidgetBoardConfig(
        enabled: [.calendar, .date, .clock, .battery, .system, .disk, .uptime, .thermal],
        weatherCity: "",
        stockSymbol: ""
    )

    static let legacyDemo = WidgetBoardConfig(
        enabled: [.calendar, .system, .weather, .stock, .battery, .clock, .date],
        weatherCity: "San Francisco",
        stockSymbol: "AAPL"
    )

    var available: [WidgetKind] {
        guard enabled.count < Self.maxEnabled else { return [] }
        return WidgetKind.allCases.filter { kind in
            enabled.contains(kind) == false && enabled.contains { $0.conflicts.contains(kind) } == false
        }
    }
}

struct WeatherSnapshot: Sendable, Equatable {
    let temperature: Double
    let condition: String
    let symbol: String
}

struct StockSnapshot: Sendable, Equatable {
    let symbol: String
    let price: Double
    let changePercent: Double
    let currency: String
}
