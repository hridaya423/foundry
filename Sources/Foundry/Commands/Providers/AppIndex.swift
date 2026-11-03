import AppKit
import Foundation
import os

/// Supplies app-bundle URLs beyond the fixed directory roots —
/// implemented by Spotlight so apps on other volumes and in nested
/// folders are found. Updates arrive as they index rather than on a
/// rescan timer.
protocol AppIndexing: AnyObject, Sendable {
    /// Starts indexing. Idempotent.
    func start()
    /// Currently indexed app-bundle URLs.
    var urls: [URL] { get }
    /// Fires when the index reports new results or live updates.
    var onUpdate: (@Sendable () -> Void)? { get set }
}

/// Live `NSMetadataQuery` for `com.apple.application-bundle` over local
/// volumes. Gathering and update notifications push new URLs to the
/// cache; dead paths are filtered later by `Bundle(url:)` failing.
///
/// `@unchecked Sendable` is justified: `NSMetadataQuery` is an ObjC
/// object without a Sendable conformance. All query reads happen on a
/// dedicated serial `OperationQueue`; `query.start()` runs at most once
/// behind the lock's `started` gate; `query.stop()` runs once in
/// `deinit`. Every other piece of mutable state lives inside `lock`.
final class LiveAppIndex: NSObject, AppIndexing, @unchecked Sendable {
    private struct State {
        var urls: [URL] = []
        var started = false
        var onUpdate: (@Sendable () -> Void)?
    }

    private let query = NSMetadataQuery()
    private let callbackQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        return queue
    }()
    private let lock = OSAllocatedUnfairLock(initialState: State())
    private var observers: [NSObjectProtocol] = []

    var onUpdate: (@Sendable () -> Void)? {
        get { lock.withLock { $0.onUpdate } }
        set { lock.withLock { $0.onUpdate = newValue } }
    }

    override init() {
        super.init()
        query.predicate = NSPredicate(
            format: "%K == %@",
            NSMetadataItemContentTypeKey,
            "com.apple.application-bundle"
        )
        query.searchScopes = [NSMetadataQueryLocalComputerScope]
        query.notificationBatchingInterval = 0.2
        let center = NotificationCenter.default
        for name in [Notification.Name.NSMetadataQueryDidFinishGathering, .NSMetadataQueryDidUpdate] {
            observers.append(center.addObserver(forName: name, object: query, queue: callbackQueue) { [weak self] _ in
                self?.collect()
            })
        }
    }

    func start() {
        let shouldStart = lock.withLock { state -> Bool in
            if state.started { return false }
            state.started = true
            return true
        }
        guard shouldStart else { return }
        query.start()
    }

    var urls: [URL] { lock.withLock { $0.urls } }

    private func collect() {
        // Called on `callbackQueue` (serial). `disableUpdates`/`enableUpdates`
        // is the documented pattern for reading results while the query runs.
        query.disableUpdates()
        var found: [URL] = []
        for index in 0..<query.resultCount {
            guard let item = query.result(at: index) as? NSMetadataItem,
                  let path = item.value(forAttribute: NSMetadataItemPathKey) as? String else { continue }
            found.append(URL(fileURLWithPath: path))
        }
        query.enableUpdates()
        let collected = found
        let update = lock.withLock { state -> (@Sendable () -> Void)? in
            state.urls = collected
            return state.onUpdate
        }
        update?()
    }

    deinit {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
        query.stop()
    }
}
