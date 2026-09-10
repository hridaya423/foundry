import Foundation
import SwiftUI
import FoundryServices

@MainActor
final class WidgetBoardState: ObservableObject {
    @Published private(set) var config: WidgetBoardConfig
    @Published private(set) var metrics = SystemMetrics.placeholder
    @Published private(set) var weather: WeatherSnapshot?
    @Published private(set) var stock: StockSnapshot?
    @Published private(set) var downloads = DownloadsSnapshot.empty
    @Published private(set) var isWeatherLoading = false
    @Published private(set) var isStockLoading = false

    private let configService: ConfigService
    private let diagnostics: DiagnosticsService
    var persistenceErrorHandler: ((Error) -> Void)?
    private let sampler = SystemMetricsSampler()
    private let weatherService = WeatherService()
    private let stockService = StockService()

    private var metricsTask: Task<Void, Never>?
    private var networkTask: Task<Void, Never>?
    private var downloadsTask: Task<Void, Never>?
    private var weatherTask: Task<Void, Never>?
    private var stockTask: Task<Void, Never>?
    private var weatherRequestID: UUID?
    private var stockRequestID: UUID?

    init(configService: ConfigService, diagnostics: DiagnosticsService = DiagnosticsService()) {
        self.configService = configService
        self.diagnostics = diagnostics
        let saved = configService.current.widgets
        var normalized = saved
        if saved == .legacyDefault || saved == .legacyExpandedDefault || saved == .legacyDemo {
            normalized = .default
        }
        normalized.enabled = Self.normalizedWidgets(from: normalized.enabled.filter { WidgetKind.allCases.contains($0) })
        if configService.current.showAgentShelf == false {
            normalized.enabled.removeAll { $0 == .agents }
        }
        normalized.enabled = Array(normalized.enabled.prefix(WidgetBoardConfig.maxEnabled))
        self.config = normalized
        if normalized != saved {
            try? configService.updateWidgets(normalized, showAgentShelf: normalized.enabled.contains(.agents))
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
        updateMetricsTask()
        updateDownloadsTask()
        updateNetworkTask()
    }

    func stop() {
        metricsTask?.cancel()
        metricsTask = nil
        networkTask?.cancel()
        networkTask = nil
        downloadsTask?.cancel()
        downloadsTask = nil
        weatherTask?.cancel()
        weatherTask = nil
        stockTask?.cancel()
        stockTask = nil
        weatherRequestID = nil
        stockRequestID = nil
    }

    func add(_ kind: WidgetKind) {
        guard config.enabled.count < WidgetBoardConfig.maxEnabled, config.enabled.contains(kind) == false else { return }
        let normalized = Self.normalizedWidgets(from: config.enabled + [kind])
        guard normalized != config.enabled else { return }
        var next = config
        next.enabled = normalized
        guard persist(next) else { return }
        updateMetricsTask()
        updateDownloadsTask()
        updateNetworkTask()
        if kind == .weather { fetchWeather() }
        if kind == .stock { fetchStock() }
    }

    func remove(_ kind: WidgetKind) {
        var next = config
        next.enabled.removeAll { $0 == kind }
        guard persist(next) else { return }
        updateMetricsTask()
        updateDownloadsTask()
        updateNetworkTask()
    }

    func moveUp(_ kind: WidgetKind) {
        guard let index = config.enabled.firstIndex(of: kind), index > 0 else { return }
        var next = config
        next.enabled.swapAt(index, index - 1)
        _ = persist(next)
    }

    func moveDown(_ kind: WidgetKind) {
        guard let index = config.enabled.firstIndex(of: kind), index < config.enabled.count - 1 else { return }
        var next = config
        next.enabled.swapAt(index, index + 1)
        _ = persist(next)
    }

    func setWeatherCity(_ city: String) {
        let trimmed = city.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false, trimmed != config.weatherCity else { return }
        var next = config
        next.weatherCity = trimmed
        guard persist(next) else { return }
        weather = nil
        fetchWeather()
    }

    func setStockSymbol(_ symbol: String) {
        let trimmed = symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard trimmed.isEmpty == false, trimmed != config.stockSymbol else { return }
        var next = config
        next.stockSymbol = trimmed
        guard persist(next) else { return }
        stock = nil
        fetchStock()
    }

    private func persist(_ next: WidgetBoardConfig) -> Bool {
        do {
            try configService.updateWidgets(next, showAgentShelf: next.enabled.contains(.agents))
            config = next
            return true
        } catch {
            persistenceErrorHandler?(error)
            return false
        }
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
        let needs = metricNeeds
        let span = diagnostics.startSpan("home.metrics")
        let sampled = await Task.detached(priority: .utility) {
            sampler.sample(needs: needs)
        }.value
        diagnostics.endSpan(span)
        guard Task.isCancelled == false else { return }
        metrics = sampled
    }

    private func updateMetricsTask() {
        if metricNeeds.isEmpty {
            metricsTask?.cancel()
            metricsTask = nil
            return
        }
        guard metricsTask == nil else { return }
        metricsTask = Task { [weak self] in
            while Task.isCancelled == false {
                await self?.sampleMetrics()
                do {
                    try await Task.sleep(for: FoundryPollingPolicy.current.metricsInterval)
                } catch {
                    return
                }
            }
        }
    }

    private func updateDownloadsTask() {
        guard homeWidgets.contains(.downloads) else {
            downloadsTask?.cancel()
            downloadsTask = nil
            return
        }
        guard downloadsTask == nil else { return }
        downloadsTask = Task { [weak self] in
            while Task.isCancelled == false {
                await self?.refreshDownloads()
                do {
                    try await Task.sleep(for: FoundryPollingPolicy.current.downloadsInterval)
                } catch {
                    return
                }
            }
        }
    }

    private func refreshDownloads() async {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let span = diagnostics.startSpan("home.downloads")
        let snapshot = await Task.detached(priority: .utility) {
            let directory = home.appendingPathComponent("Downloads")
            let files = (try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )) ?? []
            var count = 0
            var newest: (date: Date, name: String)?
            for file in files {
                guard let values = try? file.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey]),
                      values.isRegularFile == true else { continue }
                count += 1
                if let date = values.contentModificationDate, newest?.date ?? .distantPast < date {
                    newest = (date, file.lastPathComponent)
                }
            }
            return DownloadsSnapshot(count: count, newestName: newest?.name)
        }.value
        diagnostics.endSpan(span)
        guard Task.isCancelled == false else { return }
        downloads = snapshot
    }

    private func updateNetworkTask() {
        guard homeWidgets.contains(.weather) || homeWidgets.contains(.stock) else {
            networkTask?.cancel()
            networkTask = nil
            return
        }
        guard networkTask == nil else { return }
        networkTask = Task { [weak self] in
            while Task.isCancelled == false {
                await self?.refreshNetwork()
                do {
                    try await Task.sleep(for: FoundryPollingPolicy.current.networkInterval)
                } catch {
                    return
                }
            }
        }
    }

    private var metricNeeds: SystemMetricNeeds {
        homeWidgets.reduce(into: SystemMetricNeeds()) { needs, kind in
            switch kind {
            case .system:
                needs.formUnion([.cpu, .memory])
            case .cpu:
                needs.insert(.cpu)
            case .memory:
                needs.insert(.memory)
            case .battery:
                needs.insert(.battery)
            case .disk, .diskUsage:
                needs.insert(.disk)
            case .network:
                needs.insert(.network)
            case .loadAverage:
                needs.insert(.loadAverage)
            default:
                break
            }
        }
    }

    private func refreshNetwork() async {
        if homeWidgets.contains(.weather) { fetchWeather() }
        if homeWidgets.contains(.stock) { fetchStock() }
    }

    private func fetchWeather() {
        weatherTask?.cancel()
        if weather == nil { isWeatherLoading = true }
        let city = config.weatherCity
        let service = weatherService
        let requestID = UUID()
        weatherRequestID = requestID
        weatherTask = Task { [weak self] in
            let snapshot = await service.fetch(city: city)
            guard let self else { return }
            guard self.weatherRequestID == requestID, self.config.weatherCity == city else { return }
            if let snapshot { self.weather = snapshot }
            self.isWeatherLoading = false
        }
    }

    private func fetchStock() {
        stockTask?.cancel()
        if stock == nil { isStockLoading = true }
        let symbol = config.stockSymbol
        let service = stockService
        let requestID = UUID()
        stockRequestID = requestID
        stockTask = Task { [weak self] in
            let snapshot = await service.fetch(symbol: symbol)
            guard let self else { return }
            guard self.stockRequestID == requestID, self.config.stockSymbol == symbol else { return }
            if let snapshot { self.stock = snapshot }
            self.isStockLoading = false
        }
    }
}

struct DownloadsSnapshot: Sendable, Equatable {
    let count: Int
    let newestName: String?

    static let empty = DownloadsSnapshot(count: 0, newestName: nil)
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
