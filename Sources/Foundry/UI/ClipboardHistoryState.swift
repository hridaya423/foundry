import AppKit
import SwiftUI
import Observation
import FoundryServices

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
@Observable
final class ClipboardHistoryState {
    enum KindFilter: String, CaseIterable, Identifiable {
        case all = "All", text = "Text", images = "Images", files = "Files", links = "Links"
        var id: String { rawValue }

        func matches(_ item: ClipboardHistoryItem) -> Bool {
            switch (self, item.payload) {
            case (.all, _), (.images, .image), (.files, .files): true
            case let (.text, .text(value)): ClipboardHistoryItem.isLink(value) == false
            case let (.links, .text(value)): ClipboardHistoryItem.isLink(value)
            default: false
            }
        }
    }

    var query = "" { didSet { keepSelectionValid() } }
    var kindFilter = KindFilter.all { didSet { invalidateVisibleItems(); keepSelectionValid() } }
    private(set) var items: [ClipboardHistoryItem] = []
    var selectedID: String?
    private(set) var isPaused = false
    private(set) var error: Error?
    private(set) var policy: ClipboardHistoryPolicy
    private(set) var excludedBundleIdentifiers: [String] = []
    private let pasteboard: PasteboardClient
    private let persistence: (any ClipboardHistoryPersisting)?
    private let persistenceWriter: ClipboardHistoryPersistenceWriter?
    private var timer: Timer?
    private var lastChangeCount: Int
    private var persistenceTask: Task<Void, Never>?
    private var visibleItemsCache: [ClipboardHistoryItem]?
    private var visibleItemsCacheQuery = ""
    var isMonitoring: Bool { timer != nil }

    init(pasteboard: PasteboardClient = SystemPasteboardClient(), persistence: (any ClipboardHistoryPersisting)? = ClipboardHistoryStore(),
        configuration: ClipboardConfig = .default) {
        self.pasteboard = pasteboard; self.persistence = persistence; persistenceWriter = persistence.map(
            ClipboardHistoryPersistenceWriter.init); lastChangeCount = pasteboard.changeCount
        self.policy = Self.policy(for: configuration)
        self.isPaused = configuration.isPaused
        self.excludedBundleIdentifiers = configuration.excludedBundleIdentifiers
        if let persistence { do { items = policy.bounded(try persistence.load()) } catch { self.error = error } }
    }
    var visibleItems: [ClipboardHistoryItem] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalizedQuery == visibleItemsCacheQuery, let visibleItemsCache { return visibleItemsCache }
        let matching = items.filter { item in
            guard kindFilter.matches(item) else { return false }
            guard normalizedQuery.isEmpty == false else { return true }
            if case let .text(value) = item.payload, value.localizedCaseInsensitiveContains(normalizedQuery) { return true }
            return item.title.lowercased().contains(normalizedQuery) || item.subtitle.lowercased().contains(normalizedQuery)
                || item.sourceBundleIdentifier?.lowercased().contains(normalizedQuery) == true
        }
        let visibleItems = matching.filter(\.isPinned) + matching.filter { $0.isPinned == false }
        visibleItemsCacheQuery = normalizedQuery
        visibleItemsCache = visibleItems
        return visibleItems
    }
    var countLabel: String {
        let shown = visibleItems.count
        return shown == items.count
            ? String(localized: "\(items.count) items")
            : String(localized: "\(shown) of \(items.count) items")
    }
    var selectedItem: ClipboardHistoryItem? {
        guard let item = visibleItems.first(where: { $0.id == selectedID }) ?? visibleItems.first else { return nil }
        return hydrated(item)
    }

    /// Loads image bytes for lazily-loaded rows on demand, writing them back
    /// into `items` so later reads are free.
    @discardableResult
    private func hydrated(_ item: ClipboardHistoryItem) -> ClipboardHistoryItem {
        guard case let .image(data) = item.payload, data.isEmpty,
              let loaded = BestEffort.attempt("hydrate clipboard image", {
                  try persistence?.imageData(signature: item.signature) ?? nil
              }) ?? nil, loaded.isEmpty == false else { return item }
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index].payload = .image(loaded)
            return items[index]
        }
        return item
    }

    /// Item payload by id, hydrating lazily-loaded images. Action paths
    /// (paste, OCR, barcode) must go through this rather than `items`.
    func resolvedPayload(for id: String) -> ClipboardPayload? {
        items.first(where: { $0.id == id }).map(hydrated)?.payload
    }
    nonisolated static func pollInterval(secondsSinceInput: TimeInterval) -> TimeInterval { secondsSinceInput < 60 ? 0.7 : 5 }
    /// Polling runs only while the panel is open — copies made while it's
    /// closed are caught by the `captureIfChanged()` on open, and the
    /// pasteboard only ever holds the latest item anyway. That removes the
    /// launcher's biggest idle CPU cost: a runloop wake every 0.7 s forever.
    func start() {
        guard timer == nil else { return }
        captureIfChanged()
        timer = Timer.scheduledTimer(withTimeInterval: 0.7, repeats: true) { [weak self] timer in
            let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
            let interval = Self.pollInterval(secondsSinceInput: idle)
            if interval > timer.timeInterval { timer.fireDate = Date(timeIntervalSinceNow: interval) }
            Task { @MainActor in self?.captureIfChanged() }
        }
        timer?.tolerance = 0.2
    }
    func stop() { timer?.invalidate(); timer = nil }
    func reset() { query = ""; selectedID = visibleItems.first?.id }
    func select(id: String) { selectedID = id }
    func moveSelection(offset: Int) {
        guard !visibleItems.isEmpty else { return }
        let index = selectedID.flatMap { id in visibleItems.firstIndex { $0.id == id } } ?? 0
        selectedID = visibleItems[min(max(index + offset, 0), visibleItems.count - 1)].id
    }
    func copySelected() { if let item = selectedItem { copy(item) } }
    func copy(_ item: ClipboardHistoryItem) { pasteboard.write(hydrated(item).payload); lastChangeCount = pasteboard.changeCount }

    var canMergeSelectedWithPrevious: Bool { mergedWithPrevious != nil }

    private var mergedWithPrevious: String? {
        guard let id = selectedItem?.id,
              let index = items.firstIndex(where: { $0.id == id }), index > 0,
              case let .text(current) = items[index].payload,
              case let .text(previous) = items[index - 1].payload else { return nil }
        return previous + "\n\n" + current
    }

    /// Copies the selected text merged with the entry copied after it (the
    /// row above it in history). Returns false when either side isn't text.
    @discardableResult
    func copyMergedWithPreviousSelected() -> Bool {
        guard let merged = mergedWithPrevious else { return false }
        pasteboard.write(.text(merged))
        lastChangeCount = pasteboard.changeCount
        return true
    }
    func togglePinSelected() {
        guard let id = selectedItem?.id, let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].isPinned.toggle()
        persist()
    }
    func removeSelected() { guard let id = selectedItem?.id else { return }; items.removeAll { $0.id == id }; persist(); keepSelectionValid() }
    func clear() { items.removeAll(); persist(); selectedID = nil }
    func itemsRemoved(maxItems: Int, maxBytes: Int, maxAgeDays: Int) -> Int {
        var candidate = policy
        candidate.maxItems = maxItems
        candidate.maxBytes = maxBytes
        candidate.maxAge = TimeInterval(maxAgeDays) * 86_400
        return items.count - candidate.bounded(items).count
    }
    func updatePolicy(maxItems: Int, maxBytes: Int, maxAgeDays: Int) {
        policy = ClipboardHistoryPolicy(
            maxItems: maxItems,
            maxBytes: maxBytes,
            maxAge: TimeInterval(maxAgeDays) * 86_400
        )
        items = policy.bounded(items)
        persist()
        keepSelectionValid()
    }
    func updateConfiguration(_ configuration: ClipboardConfig) {
        isPaused = configuration.isPaused
        excludedBundleIdentifiers = configuration.excludedBundleIdentifiers
        updatePolicy(
            maxItems: configuration.maxItems,
            maxBytes: configuration.maxBytes,
            maxAgeDays: configuration.maxAgeDays
        )
    }

    static func policy(for configuration: ClipboardConfig) -> ClipboardHistoryPolicy {
        ClipboardHistoryPolicy(maxItems: configuration.maxItems, maxBytes: configuration.maxBytes, maxAge: TimeInterval(configuration.maxAgeDays) * 86_400)
    }
    func addSelectedFiles(to fileShelf: FileShelfState) { if let urls = selectedItem?.payload, case .files(let urls) = urls { fileShelf.add(urls: urls) } }
    func captureIfChanged() { guard pasteboard.changeCount
        != lastChangeCount else { return }; lastChangeCount = pasteboard.changeCount; captureCurrentPasteboard() }
    func waitForPersistenceForTesting() async { await persistenceTask?.value }
    func shutdown() async {
        stop()
        await persistenceTask?.value
        guard let message = await persistenceWriter?.flush() else { return }
        error = NSError(domain: "ClipboardHistoryPersistence", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
    private func captureCurrentPasteboard() {
        guard !isPaused, let snapshot = pasteboard.snapshot() else { return }
        guard excludedBundleIdentifiers.contains(snapshot.sourceBundleIdentifier ?? "") == false else { return }
        let hostile = snapshot.types.map(\.rawValue).contains { value in
            let lower = value.lowercased()
            return lower.contains("concealed") || lower.contains("transient")
                || lower.contains("autogenerated") || lower.contains("password")
                || lower.contains("foundry")
        }
        if hostile || snapshot.sourceBundleIdentifier?.lowercased().contains("password") == true { return }
        let item: ClipboardHistoryItem
        switch snapshot.payload {
        case .text(let value):
            guard value.utf8.count <= policy.maxTextBytes, ClipboardHistoryPolicy.looksLikeSecret(value) == false else { return }
            item = ClipboardHistoryItem(payload: .text(value), sourceBundleIdentifier: snapshot.sourceBundleIdentifier)
        case .image(let data):
            guard data.count <= policy.maxImageBytes else { return }
            item = ClipboardHistoryItem(payload: .image(data), sourceBundleIdentifier: snapshot.sourceBundleIdentifier)
        case .files:
            item = ClipboardHistoryItem(payload: snapshot.payload, sourceBundleIdentifier: snapshot.sourceBundleIdentifier)
        }
        items = policy.bounded([item] + items)
        persist()
        keepSelectionValid()
    }
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
