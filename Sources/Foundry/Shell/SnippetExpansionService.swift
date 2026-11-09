import AppKit
import ApplicationServices
import Carbon
import Foundation

/// All state is main-thread confined: the event tap's runloop source is
/// added to the main runloop, and every caller (ShellController, tests) is
/// @MainActor. Actor isolation replaces the previous unchecked conformance.
@MainActor
final class SnippetExpansionService {
    static let accessibilitySettingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!

    private let snippetStore: any SnippetStore
    private let directPaste: DirectPasteService
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var engine: SnippetExpansionEngine
    private var isConfigured = false
    private var accessibilityRetryCancellation: (() -> Void)?
    private var accessibilityRetryAttempts = 0
    private var testEventTapRunning = false
    private let accessibilityTrusted: () -> Bool
    private let requestAccessibilityPrompt: () -> Void
    private let scheduleAccessibilityRetry: (@escaping @MainActor @Sendable () -> Void) -> (() -> Void)
    private let startEventTap: (() -> Bool)?
    private(set) var lastError: String?
    var onStatusChanged: ((String?) -> Void)?

    init(
        snippetStore: any SnippetStore = FileSnippetStore(),
        directPaste: DirectPasteService,
        accessibilityTrusted: @escaping () -> Bool = AXIsProcessTrusted,
        requestAccessibilityPrompt: @escaping () -> Void = { _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary) },
        scheduleAccessibilityRetry: @escaping (@escaping @MainActor @Sendable () -> Void) -> (() -> Void) = SnippetExpansionService.scheduleRetry,
        startEventTap: (() -> Bool)? = nil
    ) {
        self.snippetStore = snippetStore
        self.directPaste = directPaste
        self.engine = SnippetExpansionEngine(snippets: [])
        self.accessibilityTrusted = accessibilityTrusted
        self.requestAccessibilityPrompt = requestAccessibilityPrompt
        self.scheduleAccessibilityRetry = scheduleAccessibilityRetry
        self.startEventTap = startEventTap
    }

    var isRunning: Bool { eventTap != nil || testEventTapRunning }

    private var hapticsEnabled = true

    func configure(isEnabled: Bool, excludedBundleIdentifiers: [String], delimiters: [String] = SnippetExpansionConfig.defaultDelimiters,
        hapticsEnabled: Bool = true) {
        lastError = nil
        onStatusChanged?(nil)
        activeDelimiters = Set(delimiters)
        self.hapticsEnabled = hapticsEnabled
        engine = SnippetExpansionEngine(
            snippets: snippetStore.load().filter { SnippetRenderer.argumentNames(in: $0.content).isEmpty },
            excludedBundleIdentifiers: excludedBundleIdentifiers,
            render: { SnippetRenderer.render($0.content) }
        )
        engine.setEnabled(isEnabled)
        isConfigured = isEnabled
        if isEnabled && accessibilityTrusted() { start() } else { stop() }
    }

    func start() {
        guard isConfigured, accessibilityTrusted(), eventTap == nil, testEventTapRunning == false else { return }
        if let startEventTap {
            testEventTapRunning = startEventTap()
            return
        }
        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else { return Unmanaged.passUnretained(event) }
            let service = Unmanaged<SnippetExpansionService>.fromOpaque(userInfo).takeUnretainedValue()
            nonisolated(unsafe) let event = event
            // The tap's runloop source is bound to the main runloop below.
            let consumed = MainActor.assumeIsolated {
                service.handle(type: type, event: event) == nil
            }
            return consumed ? nil : Unmanaged.passUnretained(event)
        }
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: CGEventMask(1 << CGEventType.keyDown.rawValue),
            callback: callback, userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            lastError = String(localized: "Could not start snippet expansion. Check Accessibility access and try again.")
            onStatusChanged?(lastError)
            return
        }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        eventTap = tap
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    func stop() {
        accessibilityRetryCancellation?()
        accessibilityRetryCancellation = nil
        testEventTapRunning = false
        if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: false) }
        if let runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes) }
        eventTap = nil
        runLoopSource = nil
        _ = engine.receive(.reset)
    }

    func handleApplicationActivation(bundleIdentifier: String?) { _ = engine.receive(.appChanged(bundleIdentifier: bundleIdentifier)) }
    func recoverFromWake() { _ = engine.receive(.reset); start() }

    func requestAccessibilityAccess() {
        requestAccessibilityPrompt()
        guard isConfigured, eventTap == nil, testEventTapRunning == false, accessibilityRetryCancellation == nil else { return }
        accessibilityRetryAttempts = 0
        accessibilityRetryCancellation = scheduleAccessibilityRetry { [weak self] in
            guard let self else { return }
            self.accessibilityRetryAttempts += 1
            if self.accessibilityTrusted() {
                self.accessibilityRetryCancellation?()
                self.accessibilityRetryCancellation = nil
                self.start()
            } else if self.accessibilityRetryAttempts >= 60 {
                self.accessibilityRetryCancellation?()
                self.accessibilityRetryCancellation = nil
            }
        }
    }

    func openAccessibilitySettings() { NSWorkspace.shared.open(Self.accessibilitySettingsURL) }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: true) }
            _ = engine.receive(.reset)
            return Unmanaged.passUnretained(event)
        }
        guard type == .keyDown, isConfigured else { return Unmanaged.passUnretained(event) }
        guard let nsEvent = NSEvent(cgEvent: event) else { _ = engine.receive(.nonText); return Unmanaged.passUnretained(event) }
        if IsSecureEventInputEnabled() { _ = engine.receive(.secureInputChanged(true)); return Unmanaged.passUnretained(event) }
        _ = engine.receive(.secureInputChanged(false))
        let flags = nsEvent.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.command) || flags.contains(.control) || flags.contains(.option) {
            _ = engine.receive(.modifier); return Unmanaged.passUnretained(event)
        }
        guard let characters = nsEvent.characters, !characters.isEmpty else { _ = engine.receive(.nonText); return Unmanaged.passUnretained(event) }
        if characters == String(UnicodeScalar(NSDeleteCharacter)!) { _ = engine.receive(.backspace); return Unmanaged.passUnretained(event) }
        if characters.count != 1 {
            _ = engine.receive(.nonText); return Unmanaged.passUnretained(event)
        }
        let input: SnippetExpansionEngine.Input = isDelimiter(characters) ? .delimiter(characters) : .character(characters)
        guard case let .expanded(expansion) = engine.receive(input) else { return Unmanaged.passUnretained(event) }
        let directPaste = self.directPaste
        let hapticsEnabled = self.hapticsEnabled
        Task { @MainActor in
            directPaste.captureTarget()
            do {
                try directPaste.stage(.text(expansion.pasteText), cursorOffset: expansion.cursorOffset)
                for _ in 0..<expansion.deleteCount { Self.sendBackspace() }
                try await directPaste.completePendingPaste()
                let store = self.snippetStore
                let snippetID = expansion.snippetID
                Task.detached {
                    var snippets = store.load()
                    guard let index = snippets.firstIndex(where: { $0.id == snippetID }) else { return }
                    snippets[index].recordUse()
                    _ = store.save(snippets)
                }
                if hapticsEnabled {
                    NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
                }
            } catch {
                self.lastError = Self.message(for: error)
                self.onStatusChanged?(self.lastError)
            }
        }
        return nil
    }

    private static func message(for error: Error) -> String {
        switch error as? DirectPasteError {
        case .missingTarget: return "Could not paste the snippet because the target app was unavailable."
        case .accessibilityPermission: return "Snippet expansion is blocked until Accessibility access is granted."
        case .stagingFailed: return "Could not stage the snippet for insertion."
        case .activationFailed: return "Could not activate the target app for snippet insertion."
        case .cancelled: return "Snippet insertion was cancelled."
        case .eventFailed: return "Could not send the snippet insertion event."
        case nil: return "Could not insert the snippet. Try again."
        }
    }

    private var activeDelimiters: Set<String> = Set(SnippetExpansionConfig.defaultDelimiters)

    private func isDelimiter(_ value: String) -> Bool { activeDelimiters.contains(value) }

    nonisolated private static func scheduleRetry(_ callback: @escaping @MainActor @Sendable () -> Void) -> (() -> Void) {
        var timer: Timer?
        // Scheduled from requestAccessibilityAccess (main) — the timer fires
        // on the main runloop.
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            MainActor.assumeIsolated { callback() }
        }
        return {
            timer?.invalidate()
            timer = nil
        }
    }

    private static func sendBackspace() {
        let down = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_Delete), keyDown: true)
        let up = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_Delete), keyDown: false)
        down?.post(tap: .cgAnnotatedSessionEventTap); up?.post(tap: .cgAnnotatedSessionEventTap)
    }
}
