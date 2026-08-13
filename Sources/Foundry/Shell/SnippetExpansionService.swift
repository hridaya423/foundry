import AppKit
import ApplicationServices
import Carbon
import Foundation

final class SnippetExpansionService: @unchecked Sendable {
    static let accessibilitySettingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!

    private let snippetStore: any SnippetStore
    private let directPaste: DirectPasteService
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var engine: SnippetExpansionEngine
    private var isConfigured = false
    private(set) var lastError: String?
    var onStatusChanged: ((String?) -> Void)?

    init(snippetStore: any SnippetStore = FileSnippetStore(), directPaste: DirectPasteService) {
        self.snippetStore = snippetStore
        self.directPaste = directPaste
        self.engine = SnippetExpansionEngine(snippets: [])
    }

    var isRunning: Bool { eventTap != nil }
    var isAccessibilityTrusted: Bool { AXIsProcessTrusted() }

    func configure(isEnabled: Bool, excludedBundleIdentifiers: [String]) {
        lastError = nil
        onStatusChanged?(nil)
        engine = SnippetExpansionEngine(
            snippets: snippetStore.load(),
            excludedBundleIdentifiers: excludedBundleIdentifiers,
            render: { SnippetRenderer.render($0.content).text }
        )
        engine.setEnabled(isEnabled)
        isConfigured = isEnabled
        if isEnabled && AXIsProcessTrusted() { start() } else { stop() }
    }

    func start() {
        guard isConfigured, AXIsProcessTrusted(), eventTap == nil else { return }
        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else { return Unmanaged.passUnretained(event) }
            let service = Unmanaged<SnippetExpansionService>.fromOpaque(userInfo).takeUnretainedValue()
            return service.handle(type: type, event: event)
        }
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: CGEventMask(1 << CGEventType.keyDown.rawValue),
            callback: callback, userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            lastError = "Could not start snippet expansion. Check Accessibility access and try again."
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
        if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: false) }
        if let runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes) }
        eventTap = nil
        runLoopSource = nil
        _ = engine.receive(.reset)
    }

    func resetForApplicationChange() { _ = engine.receive(.reset) }
    func recoverFromWake() { _ = engine.receive(.reset); start() }

    func requestAccessibilityAccess() {
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
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
        if isSecureTextFieldFocused() { _ = engine.receive(.secureInputChanged(true)); return Unmanaged.passUnretained(event) }
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
        let rendered = SnippetRenderer.render(expansion.renderedContent)
        let directPaste = self.directPaste
        Task { @MainActor in
            directPaste.captureTarget()
            do {
                try directPaste.stage(.text(rendered.text + expansion.delimiter), cursorOffset: rendered.cursorOffsetFromEnd, snippetID: nil)
                for _ in 0..<expansion.deleteCount { Self.sendBackspace() }
                try await directPaste.completePendingPaste()
            } catch {
                self.lastError = Self.message(for: error)
                self.onStatusChanged?(self.lastError)
            }
        }
        return nil
    }

    private func isSecureTextFieldFocused() -> Bool {
        guard let app = NSWorkspace.shared.frontmostApplication else { return true }
        let element = AXUIElementCreateApplication(app.processIdentifier)
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focused else { return true }
        var role: CFTypeRef?
        guard CFGetTypeID(focused) == AXUIElementGetTypeID() else { return true }
        let focusedElement = unsafeDowncast(focused, to: AXUIElement.self)
        guard AXUIElementCopyAttributeValue(focusedElement, kAXRoleAttribute as CFString, &role) == .success,
              let role = role as? String else { return true }
        return role == "AXSecureTextField"
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

    private func isDelimiter(_ value: String) -> Bool { [" ", "\n", "\r", "\t", "'", "\"", "`"].contains(value) }

    private static func sendBackspace() {
        let down = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_Delete), keyDown: true)
        let up = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_Delete), keyDown: false)
        down?.post(tap: .cgAnnotatedSessionEventTap); up?.post(tap: .cgAnnotatedSessionEventTap)
    }
}
