import Foundation
import SwiftUI

@MainActor
final class WidgetBoardState: ObservableObject {
    @Published private(set) var config: WidgetBoardConfig
    @Published private(set) var metrics = SystemMetrics.placeholder
    @Published private(set) var weather: WeatherSnapshot?
    @Published private(set) var stock: StockSnapshot?
    @Published private(set) var isWeatherLoading = false
    @Published private(set) var isStockLoading = false

    private let configService: ConfigService
    private let sampler = SystemMetricsSampler()
    private let weatherService = WeatherService()
    private let stockService = StockService()

    private var metricsTask: Task<Void, Never>?
    private var networkTask: Task<Void, Never>?

    init(configService: ConfigService) {
        self.configService = configService
        let saved = configService.current.widgets
        var normalized = saved
        if saved == .legacyDefault || saved == .legacyDemo || (saved.weatherCity == "San Francisco" && saved.stockSymbol == "AAPL") {
            normalized = .default
        } else {
            if normalized.weatherCity == "San Francisco" { normalized.weatherCity = "" }
            if normalized.stockSymbol == "AAPL" { normalized.stockSymbol = "" }
        }
        normalized.enabled = Self.normalizedWidgets(from: normalized.enabled.filter { WidgetKind.allCases.contains($0) })
        for kind in WidgetBoardConfig.default.enabled where normalized.enabled.count < WidgetBoardConfig.maxEnabled && normalized.enabled.contains(kind) == false {
            normalized.enabled = Self.normalizedWidgets(from: normalized.enabled + [kind])
        }
        normalized.enabled = Array(normalized.enabled.prefix(WidgetBoardConfig.maxEnabled))
        self.config = normalized
        if normalized != saved {
            configService.updateWidgets(normalized)
        }
    }

    var enabled: [WidgetKind] {
        config.enabled
    }

    var homeWidgets: [WidgetKind] {
        config.enabled.filter { kind in
            guard WidgetKind.allCases.contains(kind) else { return false }
            switch kind {
            case .weather:
                return config.weatherCity.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            case .stock:
                return config.stockSymbol.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            default:
                return true
            }
        }
    }

    var isFull: Bool {
        config.enabled.count >= WidgetBoardConfig.maxEnabled
    }

    func start() {
        if metricsTask == nil {
            metricsTask = Task { [weak self] in
                while Task.isCancelled == false {
                    await self?.sampleMetrics()
                    do {
                        try await Task.sleep(for: .seconds(2))
                    } catch {
                        return
                    }
                }
            }
        }
        if networkTask == nil {
            networkTask = Task { [weak self] in
                while Task.isCancelled == false {
                    await self?.refreshNetwork()
                    do {
                        try await Task.sleep(for: .seconds(600))
                    } catch {
                        return
                    }
                }
            }
        }
    }

    func stop() {
        metricsTask?.cancel()
        metricsTask = nil
        networkTask?.cancel()
        networkTask = nil
    }

    func add(_ kind: WidgetKind) {
        guard config.enabled.contains(kind) == false else { return }
        let normalized = Self.normalizedWidgets(from: config.enabled + [kind])
        guard normalized != config.enabled else { return }
        config.enabled = normalized
        persist()
        if kind == .weather { fetchWeather() }
        if kind == .stock { fetchStock() }
    }

    func remove(_ kind: WidgetKind) {
        config.enabled.removeAll { $0 == kind }
        persist()
    }

    func moveUp(_ kind: WidgetKind) {
        guard let index = config.enabled.firstIndex(of: kind), index > 0 else { return }
        config.enabled.swapAt(index, index - 1)
        persist()
    }

    func moveDown(_ kind: WidgetKind) {
        guard let index = config.enabled.firstIndex(of: kind), index < config.enabled.count - 1 else { return }
        config.enabled.swapAt(index, index + 1)
        persist()
    }

    func setWeatherCity(_ city: String) {
        let trimmed = city.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false, trimmed != config.weatherCity else { return }
        config.weatherCity = trimmed
        weather = nil
        persist()
        fetchWeather()
    }

    func setStockSymbol(_ symbol: String) {
        let trimmed = symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard trimmed.isEmpty == false, trimmed != config.stockSymbol else { return }
        config.stockSymbol = trimmed
        stock = nil
        persist()
        fetchStock()
    }

    private func persist() {
        configService.updateWidgets(config)
    }

    private static func normalizedWidgets(from widgets: [WidgetKind]) -> [WidgetKind] {
        var result: [WidgetKind] = []
        for kind in widgets where WidgetKind.allCases.contains(kind) {
            result.removeAll { kind.conflicts.contains($0) }
            if result.contains(kind) == false && result.contains(where: { $0.conflicts.contains(kind) }) == false {
                result.append(kind)
            }
        }
        return Array(result.prefix(WidgetBoardConfig.maxEnabled))
    }

    private func sampleMetrics() async {
        let sampler = sampler
        metrics = await Task.detached(priority: .utility) {
            sampler.sample()
        }.value
    }

    private func refreshNetwork() async {
        if config.enabled.contains(.weather) { fetchWeather() }
        if config.enabled.contains(.stock) { fetchStock() }
    }

    private func fetchWeather() {
        if weather == nil { isWeatherLoading = true }
        let city = config.weatherCity
        let service = weatherService
        Task { [weak self] in
            let snapshot = await service.fetch(city: city)
            guard let self else { return }
            if let snapshot { self.weather = snapshot }
            self.isWeatherLoading = false
        }
    }

    private func fetchStock() {
        if stock == nil { isStockLoading = true }
        let symbol = config.stockSymbol
        let service = stockService
        Task { [weak self] in
            let snapshot = await service.fetch(symbol: symbol)
            guard let self else { return }
            if let snapshot { self.stock = snapshot }
            self.isStockLoading = false
        }
    }
}

extension SystemMetrics {
    var cpuDisplay: String {
        "\(Int(cpuPercent.rounded()))%"
    }

    var memoryDisplay: String {
        "\(Int(memoryPercent.rounded()))%"
    }

    var batteryDisplay: String {
        guard let batteryPercent else { return "—" }
        return "\(batteryPercent)%"
    }

    var batterySymbol: String {
        if isCharging { return "battery.100.bolt" }
        switch batteryPercent ?? 0 {
        case ...10: return "battery.0"
        case ...37: return "battery.25"
        case ...62: return "battery.50"
        case ...87: return "battery.75"
        default: return "battery.100"
        }
    }

    var batteryTint: Color {
        if isCharging { return Color.green.opacity(0.9) }
        if let batteryPercent, batteryPercent <= 20 { return Color.red.opacity(0.9) }
        return FoundryTheme.secondaryText
    }

    var batteryStateLabel: String {
        if isCharging { return "Charging" }
        if hasBattery { return "On battery" }
        return "Plugged in"
    }

    var diskDisplay: String {
        ByteCountFormatter.string(fromByteCount: diskFreeBytes, countStyle: .decimal)
    }

    var diskUsedDisplay: String {
        guard diskTotalBytes > 0 else { return "—" }
        let used = max(diskTotalBytes - diskFreeBytes, 0)
        return "\(Int((Double(used) / Double(diskTotalBytes) * 100).rounded()))%"
    }

    var memoryUsedDisplay: String {
        ByteCountFormatter.string(fromByteCount: Int64(memoryUsed), countStyle: .decimal)
    }

    var memoryTotalDisplay: String {
        ByteCountFormatter.string(fromByteCount: Int64(memoryTotal), countStyle: .decimal)
    }

    var loadAverageDisplay: String {
        String(format: "%.2f", loadAverage1m)
    }

    var localIPAddressDisplay: String {
        localIPAddress ?? "Offline"
    }

    var bootDateDisplay: String {
        Self.bootDateFormatter.string(from: Date(timeIntervalSinceNow: -uptimeSeconds))
    }

    var bootClockDisplay: String {
        Self.bootClockFormatter.string(from: Date(timeIntervalSinceNow: -uptimeSeconds))
    }

    var uptimeDisplay: String {
        let total = Int(uptimeSeconds)
        let days = total / 86400
        let hours = (total % 86400) / 3600
        let minutes = (total % 3600) / 60
        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }

    var thermalDisplay: String {
        switch thermal {
        case .nominal: return "Nominal"
        case .fair: return "Fair"
        case .serious: return "Serious"
        case .critical: return "Critical"
        @unknown default: return "Unknown"
        }
    }

    var thermalTint: Color {
        switch thermal {
        case .nominal: return Color.green.opacity(0.85)
        case .fair: return Color.yellow.opacity(0.9)
        case .serious: return Color.orange.opacity(0.95)
        case .critical: return Color.red.opacity(0.95)
        @unknown default: return FoundryTheme.secondaryText
        }
    }

    private static let bootDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter
    }()

    private static let bootClockFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }()
}
