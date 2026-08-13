import AppKit
import Carbon

enum DirectPasteError: Error, Equatable, LocalizedError {
    case missingTarget
    case accessibilityPermission
    case stagingFailed
    case activationFailed
    case cancelled
    case eventFailed

    var errorDescription: String? {
        switch self {
        case .missingTarget: return "The target app was unavailable."
        case .accessibilityPermission: return "Accessibility access is required."
        case .stagingFailed: return "The paste could not be staged."
        case .activationFailed: return "The target app could not be activated."
        case .cancelled: return "The paste was cancelled."
        case .eventFailed: return "The paste event could not be sent."
        }
    }
}

enum DirectPasteEvent: Equatable {
    case staged
    case targetActivated
    case pasted
    case cursorMoved(count: Int)
    case pasteboardRestored
}

protocol DirectPasteTarget: AnyObject {
    var processIdentifier: pid_t { get }
    func activate(options: NSApplication.ActivationOptions) -> Bool
}

extension NSRunningApplication: DirectPasteTarget {}

@MainActor
final class DirectPasteService {
    static let shared = DirectPasteService()
    static let foundryMarker = NSPasteboard.PasteboardType("com.hridya.foundry.ephemeral")

    private let pasteboard: NSPasteboard
    private let targetProvider: () -> (any DirectPasteTarget)?
    private let ownProcessIdentifier: pid_t
    private let accessibilityTrusted: () -> Bool
    private let record: (DirectPasteEvent) -> Void
    private let sendPaste: () -> Bool
    private let sendLeft: () -> Bool
    private var target: (any DirectPasteTarget)?
    private var stagedChangeCount: Int?
    private var previousPayload: ClipboardPayload?
    private var previousItems: [NSPasteboardItem]?
    private var pending: PendingPaste?

    struct PendingPaste: Equatable {
        let cursorOffset: Int
        let snippetID: String?
    }

    init(
        pasteboard: NSPasteboard = .general,
        ownProcessIdentifier: pid_t = ProcessInfo.processInfo.processIdentifier,
        targetProvider: @escaping () -> (any DirectPasteTarget)? = { NSWorkspace.shared.frontmostApplication },
        accessibilityTrusted: @escaping () -> Bool = AXIsProcessTrusted,
        record: @escaping (DirectPasteEvent) -> Void = { _ in },
        sendPaste: @escaping () -> Bool = { DirectPasteService.send(keyCode: 9, flags: .maskCommand) },
        sendLeft: @escaping () -> Bool = { DirectPasteService.send(keyCode: 123, flags: []) }
    ) {
        self.pasteboard = pasteboard
        self.ownProcessIdentifier = ownProcessIdentifier
        self.targetProvider = targetProvider
        self.accessibilityTrusted = accessibilityTrusted
        self.record = record
        self.sendPaste = sendPaste
        self.sendLeft = sendLeft
    }

    func captureTarget() {
        guard let candidate = targetProvider(), candidate.processIdentifier != ownProcessIdentifier else { return }
        target = candidate
    }

    var hasPendingPaste: Bool { pending != nil }

    func stage(_ payload: ClipboardPayload, cursorOffset: Int = 0, snippetID: String? = nil) throws {
        guard target != nil else { throw DirectPasteError.missingTarget }
        previousItems = pasteboard.pasteboardItems?.map { item in
            let copy = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) { copy.setData(data, forType: type) }
            }
            return copy
        }
        previousPayload = readPayload()
        pasteboard.clearContents()
        pasteboard.setString("Foundry", forType: Self.foundryMarker)
        switch payload {
        case .text(let value): pasteboard.setString(value, forType: .string)
        case .files(let urls): pasteboard.writeObjects(urls as [NSURL])
        case .image(let data): pasteboard.setData(data, forType: .tiff)
        }
        stagedChangeCount = pasteboard.changeCount
        pending = PendingPaste(cursorOffset: max(0, cursorOffset), snippetID: snippetID)
        record(.staged)
    }

    func completePendingPaste(after delay: Duration = .milliseconds(80)) async throws {
        defer {
            restorePasteboardIfUnchanged()
            self.pending = nil
            self.target = nil
            self.stagedChangeCount = nil
            self.previousPayload = nil
            self.previousItems = nil
        }
        guard let target, let pending else { throw DirectPasteError.missingTarget }
        guard accessibilityTrusted() else { throw DirectPasteError.accessibilityPermission }
        guard target.activate(options: []) else { throw DirectPasteError.activationFailed }
        record(.targetActivated)
        do {
            try await Task.sleep(for: delay)
        } catch is CancellationError {
            throw DirectPasteError.cancelled
        }
        guard !Task.isCancelled else { throw DirectPasteError.cancelled }
        guard sendPaste() else { throw DirectPasteError.eventFailed }
        record(.pasted)
        if pending.cursorOffset > 0 {
            for _ in 0..<pending.cursorOffset {
                guard sendLeft() else { throw DirectPasteError.eventFailed }
            }
            record(.cursorMoved(count: pending.cursorOffset))
        }
    }

    private func restorePasteboardIfUnchanged() {
        guard let stagedChangeCount, pasteboard.changeCount == stagedChangeCount else { return }
        pasteboard.clearContents()
        if let previousItems {
            pasteboard.writeObjects(previousItems)
        } else if let previousPayload {
            write(previousPayload)
        }
        record(.pasteboardRestored)
    }

    private func readPayload() -> ClipboardPayload? {
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL], !urls.isEmpty { return .files(urls) }
        if let text = pasteboard.string(forType: .string) { return .text(text) }
        if let data = pasteboard.data(forType: .tiff) { return .image(data) }
        return nil
    }

    private func write(_ payload: ClipboardPayload) {
        switch payload {
        case .text(let value): pasteboard.setString(value, forType: .string)
        case .files(let urls): pasteboard.writeObjects(urls as [NSURL])
        case .image(let data): pasteboard.setData(data, forType: .tiff)
        }
    }

    private static func send(keyCode: CGKeyCode, flags: CGEventFlags) -> Bool {
        guard let source = CGEventSource(stateID: .hidSystemState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else { return false }
        down.flags = flags; up.flags = flags
        down.post(tap: .cghidEventTap); up.post(tap: .cghidEventTap)
        return true
    }
}
