import AppKit
import SwiftUI

actor ClipboardHistoryPersistenceWriter {
    private let persistence: any ClipboardHistoryPersisting
    private var pendingItems: [ClipboardHistoryItem]?
    private var drainTask: Task<Void, Never>?
    private var lastErrorMessage: String?

    init(_ persistence: any ClipboardHistoryPersisting) {
        self.persistence = persistence
    }

    func schedule(_ items: [ClipboardHistoryItem]) {
        pendingItems = items
        guard drainTask == nil else { return }
        drainTask = Task { await drain() }
    }

    func flush() async -> String? {
        while let drainTask {
            await drainTask.value
        }
        return lastErrorMessage
    }

    private func drain() async {
        while let items = pendingItems {
            pendingItems = nil
            let persistence = persistence
            let message = await Task.detached(priority: .utility) {
                do {
                    try persistence.save(items)
                    return nil as String?
                } catch {
                    return error.localizedDescription
                }
            }.value
            lastErrorMessage = message
        }
        drainTask = nil
    }
}

@MainActor
final class ClipboardHistoryState: ObservableObject {
    @Published var query = "" { didSet { keepSelectionValid() } }
    @Published private(set) var items: [ClipboardHistoryItem] = []
    @Published var selectedID: String?
    @Published private(set) var isPaused = false
    @Published private(set) var error: Error?
    @Published private(set) var policy: ClipboardHistoryPolicy
    private(set) var excludedBundleIdentifiers: [String] = []
    private let pasteboard: PasteboardClient
    private let persistenceWriter: ClipboardHistoryPersistenceWriter?
    private var timer: Timer?
    private var lastChangeCount: Int
    private var persistenceTask: Task<Void, Never>?
    private var visibleItemsCache: [ClipboardHistoryItem]?
    private var visibleItemsCacheQuery = ""
    var isMonitoring: Bool { timer != nil }

    init(pasteboard: PasteboardClient = SystemPasteboardClient(), persistence: (any ClipboardHistoryPersisting)? = ClipboardHistoryPersistence(), configuration: ClipboardConfig = .default) {
        self.pasteboard = pasteboard; persistenceWriter = persistence.map(ClipboardHistoryPersistenceWriter.init); lastChangeCount = pasteboard.changeCount
        self.policy = ClipboardHistoryPolicy(maxItems: configuration.maxItems, maxBytes: configuration.maxBytes)
        self.isPaused = configuration.isPaused
        self.excludedBundleIdentifiers = configuration.excludedBundleIdentifiers
        if let persistence { do { items = policy.bounded(try persistence.load()) } catch { self.error = error } }
    }
    var visibleItems: [ClipboardHistoryItem] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalizedQuery == visibleItemsCacheQuery, let visibleItemsCache { return visibleItemsCache }
        let visibleItems: [ClipboardHistoryItem]
        if normalizedQuery.isEmpty {
            visibleItems = items
        } else {
            visibleItems = items.filter {
                $0.title.lowercased().contains(normalizedQuery)
                    || $0.subtitle.lowercased().contains(normalizedQuery)
                    || $0.kindLabel.lowercased().contains(normalizedQuery)
            }
        }
        visibleItemsCacheQuery = normalizedQuery
        visibleItemsCache = visibleItems
        return visibleItems
    }
    var selectedItem: ClipboardHistoryItem? { visibleItems.first { $0.id == selectedID } ?? visibleItems.first }
    func start() { guard timer == nil else { return }; captureIfChanged(); timer = Timer.scheduledTimer(withTimeInterval: 0.7, repeats: true) { [weak self] _ in Task { @MainActor in self?.captureIfChanged() } }; timer?.tolerance = 0.2 }
    func stop() { timer?.invalidate(); timer = nil }
    func reset() { query = ""; selectedID = visibleItems.first?.id }
    func select(id: String) { selectedID = id }
    func moveSelection(offset: Int) { guard !visibleItems.isEmpty else { return }; let i = selectedID.flatMap { id in visibleItems.firstIndex { $0.id == id } } ?? 0; selectedID = visibleItems[min(max(i + offset, 0), visibleItems.count - 1)].id }
    func copySelected() { if let item = selectedItem { copy(item) } }
    func copy(_ item: ClipboardHistoryItem) { pasteboard.write(item.payload); lastChangeCount = pasteboard.changeCount }
    func removeSelected() { guard let id = selectedItem?.id else { return }; items.removeAll { $0.id == id }; persist(); keepSelectionValid() }
    func clear() { items.removeAll(); persist(); selectedID = nil }
    func setPaused(_ paused: Bool) { isPaused = paused }
    func report(_ error: Error) { self.error = error }
    func updatePolicy(maxItems: Int, maxBytes: Int) { policy = ClipboardHistoryPolicy(maxItems: maxItems, maxBytes: maxBytes); items = policy.bounded(items); persist(); keepSelectionValid() }
    func updateConfiguration(_ configuration: ClipboardConfig) { isPaused = configuration.isPaused; excludedBundleIdentifiers = configuration.excludedBundleIdentifiers; updatePolicy(maxItems: configuration.maxItems, maxBytes: configuration.maxBytes) }
    func pin(id: String, pinned: Bool) { guard let i = items.firstIndex(where: { $0.id == id }) else { return }; items[i].isPinned = pinned; persist() }
    func addSelectedFiles(to fileShelf: FileShelfState) { if let urls = selectedItem?.payload, case .files(let urls) = urls { fileShelf.add(urls: urls) } }
    private func captureIfChanged() { guard pasteboard.changeCount != lastChangeCount else { return }; lastChangeCount = pasteboard.changeCount; captureCurrentPasteboard() }
    func captureIfChangedForTesting() { captureIfChanged() }
    func waitForPersistenceForTesting() async { await persistenceTask?.value }
    func shutdown() async {
        stop()
        await persistenceTask?.value
        guard let message = await persistenceWriter?.flush() else { return }
        error = NSError(domain: "ClipboardHistoryPersistence", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
    private func captureCurrentPasteboard() { guard !isPaused, let snapshot = pasteboard.snapshot() else { return }; guard excludedBundleIdentifiers.contains(snapshot.sourceBundleIdentifier ?? "") == false else { return }; let hostile = snapshot.types.map(\.rawValue).contains { value in let lower = value.lowercased(); return lower.contains("concealed") || lower.contains("transient") || lower.contains("autogenerated") || lower.contains("password") || lower.contains("foundry") }; if hostile || snapshot.sourceBundleIdentifier?.lowercased().contains("password") == true { return }; let item: ClipboardHistoryItem; switch snapshot.payload { case .text(let v): guard v.utf8.count <= policy.maxTextBytes else { return }; item = ClipboardHistoryItem(payload: .text(v), sourceBundleIdentifier: snapshot.sourceBundleIdentifier); case .image(let d): guard d.count <= policy.maxImageBytes else { return }; item = ClipboardHistoryItem(payload: .image(d), sourceBundleIdentifier: snapshot.sourceBundleIdentifier); case .files: item = ClipboardHistoryItem(payload: snapshot.payload, sourceBundleIdentifier: snapshot.sourceBundleIdentifier) }; items = policy.bounded([item] + items); persist(); keepSelectionValid() }
    private func persist() {
        invalidateVisibleItems()
        guard let persistenceWriter else { return }
        let snapshot = items
        persistenceTask = Task { [weak self, persistenceWriter] in
            await persistenceWriter.schedule(snapshot)
            let message = await persistenceWriter.flush()
            guard let self, let message else { return }
            self.error = NSError(domain: "ClipboardHistoryPersistence", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
        }
    }
    private func keepSelectionValid() { if selectedID == nil || !visibleItems.contains(where: { $0.id == selectedID }) { selectedID = visibleItems.first?.id } }
    private func invalidateVisibleItems() { visibleItemsCache = nil }
}
