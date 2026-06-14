import Foundation

@MainActor
final class ActivityMonitorState: ObservableObject {
    @Published var query = ""
    @Published var snapshot = ActivitySnapshot.empty
    @Published var selectedGroupID: String?
    @Published var cpuHistory: [Double] = []
    @Published var memoryHistory: [Double] = []
    @Published var isLoading = true

    private let sampler = ActivityMonitorSampler()
    private var refreshTask: Task<Void, Never>?

    var visibleGroups: [ActivityProcessGroup] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let groups = groupedProcesses
        guard trimmed.isEmpty == false else {
            return groups
                .filter(\.isUsefulByDefault)
                .sorted(by: ActivityProcessGroup.memorySort)
                .prefixArray(64)
        }

        let needle = trimmed.lowercased()
        return groups.filter { group in
            group.displayName.lowercased().contains(needle)
                || group.processes.contains { process in
                    process.displayName.lowercased().contains(needle)
                        || process.name.lowercased().contains(needle)
                        || String(process.pid).contains(needle)
                        || (process.path?.lowercased().contains(needle) ?? false)
                }
        }
        .sorted(by: ActivityProcessGroup.memorySort)
        .prefixArray(64)
    }

    var selectedGroup: ActivityProcessGroup? {
        let groups = visibleGroups
        guard let selectedGroupID else { return groups.first }
        return groups.first { $0.id == selectedGroupID } ?? groups.first
    }

    var hiddenNoiseCount: Int {
        groupedProcesses.filter { $0.isUsefulByDefault == false }.count
    }

    var hasStableCPUSample: Bool {
        cpuHistory.count >= 2
    }

    func start() {
        guard refreshTask == nil else { return }
        refreshTask = Task { [weak self] in
            while Task.isCancelled == false {
                await self?.refresh()
                do {
                    try await Task.sleep(for: .seconds(1))
                } catch {
                    return
                }
            }
        }
    }

    func stop() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    func reset() {
        query = ""
        selectedGroupID = nil
        isLoading = true
        cpuHistory.removeAll(keepingCapacity: true)
        memoryHistory.removeAll(keepingCapacity: true)
    }

    func refreshNow() {
        Task { [weak self] in
            await self?.refresh()
        }
    }

    func moveSelection(offset: Int) {
        let groups = visibleGroups
        guard groups.isEmpty == false else { return }
        let currentIndex = selectedGroupID.flatMap { id in groups.firstIndex { $0.id == id } } ?? 0
        let nextIndex = min(max(currentIndex + offset, 0), groups.count - 1)
        selectedGroupID = groups[nextIndex].id
    }

    func select(groupID: String) {
        selectedGroupID = groupID
    }

    private func refresh() async {
        let sampler = sampler
        let nextSnapshot = await Task.detached(priority: .utility) {
            sampler.sample()
        }.value

        snapshot = nextSnapshot
        isLoading = false
        if selectedGroupID == nil {
            selectedGroupID = visibleGroups.first?.id
        } else if let selectedGroupID, visibleGroups.contains(where: { $0.id == selectedGroupID }) == false {
            self.selectedGroupID = visibleGroups.first?.id
        }

        appendHistory(value: nextSnapshot.cpuUsage, to: &cpuHistory)
        let memoryPercent = nextSnapshot.memoryTotal == 0 ? 0 : Double(nextSnapshot.memoryUsed) / Double(nextSnapshot.memoryTotal) * 100
        appendHistory(value: memoryPercent, to: &memoryHistory)
    }

    private func appendHistory(value: Double, to history: inout [Double]) {
        history.append(value)
        if history.count > 48 {
            history.removeFirst(history.count - 48)
        }
    }

    private var groupedProcesses: [ActivityProcessGroup] {
        let buckets = Dictionary(grouping: snapshot.processes) { process in
            process.groupKey
        }

        return buckets.map { key, processes in
            let sortedProcesses = processes.sorted {
                if $0.memoryBytes == $1.memoryBytes { return $0.cpuUsage > $1.cpuUsage }
                return $0.memoryBytes > $1.memoryBytes
            }
            let primary = sortedProcesses.first
            return ActivityProcessGroup(
                id: key,
                displayName: primary?.groupName ?? primary?.displayName ?? key,
                iconPath: primary?.iconPath,
                symbolName: primary?.symbolName,
                primaryPath: primary?.bundlePath ?? primary?.path,
                processCount: processes.count,
                hasCPUReading: processes.contains { $0.hasCPUReading },
                cpuUsage: processes.reduce(0) { $0 + $1.cpuUsage },
                memoryBytes: processes.reduce(0) { $0 + $1.memoryBytes },
                processes: sortedProcesses
            )
        }
    }
}

struct ActivityProcessGroup: Identifiable, Hashable, Sendable {
    let id: String
    let displayName: String
    let iconPath: String?
    let symbolName: String?
    let primaryPath: String?
    let processCount: Int
    let hasCPUReading: Bool
    let cpuUsage: Double
    let memoryBytes: UInt64
    let processes: [ActivityProcess]

    var subtitle: String {
        let processLabel = processCount == 1 ? "1 process" : "\(processCount) processes"
        return "\(processLabel) - \(ByteCountFormatter.string(fromByteCount: Int64(memoryBytes), countStyle: .memory))"
    }

    var topProcess: ActivityProcess? {
        processes.first
    }

    var isUsefulByDefault: Bool {
        let normalizedName = displayName.lowercased()
        if cpuUsage >= 0.5 { return true }
        if ActivityProcessGroup.noiseNames.contains(normalizedName) { return false }
        if normalizedName.hasPrefix("md") { return false }
        if normalizedName.hasPrefix("com.apple.") { return false }
        if normalizedName.hasPrefix("core") { return false }
        if normalizedName.hasPrefix("scopedbookmark") { return false }
        if normalizedName.hasPrefix("control") { return false }

        if primaryPath?.contains("/Applications/") == true { return true }
        if primaryPath?.hasPrefix(FileManager.default.homeDirectoryForCurrentUser.path) == true { return true }
        if memoryBytes >= 128 * 1_024 * 1_024 { return true }
        return false
    }

    static func memorySort(lhs: ActivityProcessGroup, rhs: ActivityProcessGroup) -> Bool {
        if lhs.memoryBytes == rhs.memoryBytes {
            return lhs.cpuUsage > rhs.cpuUsage
        }
        return lhs.memoryBytes > rhs.memoryBytes
    }

    private static let noiseNames: Set<String> = [
        "mdworker", "mdworker_shared", "mds", "mds_stores", "mdwrite", "cfprefsd", "runningboardd",
        "containermanagerd", "distnoted", "launchd", "loginwindow", "sysmond", "trustd", "nsurlsessiond",
        "controlcenter", "controlstrip", "contextstored", "suggestd", "knowledge-agent", "rapportd",
        "sharingd", "usernoted", "bird", "cloudd", "dasd", "duetexpertd", "backgroundtaskmanagementagent"
    ]
}

private extension ActivitySnapshot {
    static let empty = ActivitySnapshot(
        sampledAt: Date(),
        cpuUsage: 0,
        memoryUsed: 0,
        memoryTotal: ProcessInfo.processInfo.physicalMemory,
        processCount: 0,
        groupCount: 0,
        processes: []
    )
}

private extension Array {
    func prefixArray(_ maxLength: Int) -> [Element] {
        Array(prefix(maxLength))
    }
}
