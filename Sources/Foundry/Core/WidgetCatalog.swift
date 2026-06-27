import Foundation

enum WidgetKind: String, Codable, CaseIterable, Sendable, Identifiable {
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
    case activeApp
    case device
    case osVersion
    case user
    case timeZone
    case display
    case boot
    case host
    case cores

    static let allCases: [WidgetKind] = [
        .calendar,
        .system,
        .battery,
        .date,
        .disk,
        .uptime,
        .clock,
        .cpu,
        .memory,
        .diskUsage,
        .weather,
        .stock
    ]

    var id: String { rawValue }

    var title: String {
        switch self {
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
        case .activeApp: return "Active App"
        case .device: return "Device"
        case .osVersion: return "macOS"
        case .user: return "User"
        case .timeZone: return "Time Zone"
        case .display: return "Display"
        case .boot: return "Boot"
        case .host: return "Host"
        case .cores: return "Cores"
        }
    }

    var summary: String {
        switch self {
        case .calendar: return "Month at a glance"
        case .date: return "Today's day and date"
        case .clock: return "Analog wall clock"
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
        case .activeApp: return "Frontmost application"
        case .device: return "Mac device name"
        case .osVersion: return "Installed macOS version"
        case .user: return "Current signed-in user"
        case .timeZone: return "Current time zone"
        case .display: return "Main display resolution"
        case .boot: return "Approximate last boot time"
        case .host: return "Host name"
        case .cores: return "Active processor count"
        }
    }

    var symbol: String {
        switch self {
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
        case .activeApp: return "macwindow"
        case .device: return "desktopcomputer"
        case .osVersion: return "apple.logo"
        case .user: return "person.crop.circle"
        case .timeZone: return "globe"
        case .display: return "display"
        case .boot: return "power"
        case .host: return "bonjour"
        case .cores: return "cpu.fill"
        }
    }

    var span: Int {
        switch self {
        case .calendar, .system, .weather, .stock, .activeApp, .display:
            2
        default:
            1
        }
    }

    var heightUnits: Int {
        self == .calendar ? 3 : 1
    }

    var needsNetwork: Bool {
        self == .weather || self == .stock
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
    static let maxEnabled = 8

    var enabled: [WidgetKind]
    var weatherCity: String
    var stockSymbol: String

    static let `default` = WidgetBoardConfig(
        enabled: [.calendar, .system, .battery, .date, .disk, .uptime, .clock],
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
        WidgetKind.allCases.filter { kind in
            enabled.contains(kind) == false && enabled.contains { $0.conflicts.contains(kind) } == false
        } 
    }
}

struct WeatherSnapshot: Sendable, Equatable {
    let city: String
    let temperature: Double
    let condition: String
    let symbol: String
    let isDay: Bool
}

struct StockSnapshot: Sendable, Equatable {
    let symbol: String
    let price: Double
    let changePercent: Double
    let currency: String
}
