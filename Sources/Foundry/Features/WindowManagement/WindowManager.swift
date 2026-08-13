import AppKit
import ApplicationServices
import Foundation
import FoundryDomain

enum WindowOperationResult: Equatable, Sendable {
    case tiled(WindowPlacement)
    case constrained(WindowPlacement)
    case restored
    case needsAccessibilityPermission
    case failed(String)
}

@MainActor
protocol WindowManaging: Sendable {
    func isTrusted() -> Bool
    func apply(_ placement: WindowPlacement) async -> WindowOperationResult
}

struct WindowIdentity: Hashable, Sendable {
    let pid: pid_t
    let windowNumber: String

    static func accessibilityElement(pid: pid_t, elementHash: UInt) -> WindowIdentity {
        WindowIdentity(pid: pid, windowNumber: "ax:\(elementHash)")
    }
}

struct WindowElementCache<Element> {
    private var elements: [WindowIdentity: Element] = [:]

    mutating func store(_ element: Element, for identity: WindowIdentity) {
        elements = elements.filter { $0.key.pid != identity.pid }
        elements[identity] = element
    }

    func element(for identity: WindowIdentity) -> Element? {
        elements[identity]
    }
}

struct WindowRestoreStore: Sendable {
    private var frames: [WindowIdentity: CGRect] = [:]

    mutating func save(_ frame: CGRect, for identity: WindowIdentity) {
        frames[identity] = frame
    }

    func frame(for identity: WindowIdentity) -> CGRect? {
        frames[identity]
    }

    mutating func removeFrame(for identity: WindowIdentity) -> CGRect? {
        frames.removeValue(forKey: identity)
    }
}

struct AXWindowSnapshot: Sendable {
    let identity: WindowIdentity
    let frame: CGRect
    let canMove: Bool
    let canResize: Bool
}

protocol WindowAccessibilityClient: Sendable {
    func window(for pid: pid_t, anchorHeight: CGFloat) async -> AXWindowSnapshot?
    func setFrame(_ frame: CGRect, for identity: WindowIdentity, anchorHeight: CGFloat) async -> WindowFrameApplicationResult
}

enum WindowFrameApplicationResult: Sendable, Equatable {
    case applied(CGRect)
    case constrained(CGRect)
    case failed
    case cancelled
}

@MainActor
final class NativeWindowManager: WindowManaging {
    static let accessibilitySettingsURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
    )!

    private let accessibility: any WindowAccessibilityClient
    private let trustProvider: @MainActor () -> Bool
    private let targetProvider: @MainActor () -> pid_t?
    private var restoreStore = WindowRestoreStore()
    private var lastExternalPID: pid_t?
    private var pendingPID: pid_t?
    nonisolated(unsafe) private var activationObserver: NSObjectProtocol?

    init(
        accessibility: any WindowAccessibilityClient = NativeWindowAccessibilityClient(),
        trustProvider: @escaping @MainActor () -> Bool = { AXIsProcessTrusted() },
        targetProvider: @escaping @MainActor () -> pid_t? = { nil }
    ) {
        self.accessibility = accessibility
        self.trustProvider = trustProvider
        self.targetProvider = targetProvider
        let ownPID = ProcessInfo.processInfo.processIdentifier
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.processIdentifier != ownPID else { return }
            Task { @MainActor in
                self?.lastExternalPID = app.processIdentifier
            }
        }
    }

    deinit {
        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
        }
    }

    func isTrusted() -> Bool {
        trustProvider()
    }

    func apply(_ placement: WindowPlacement) async -> WindowOperationResult {
        guard isTrusted() else {
            pendingPID = currentTargetPID()
            return .needsAccessibilityPermission
        }

        let anchorHeight = Self.screenMirrorAnchorHeight
        guard let pid = targetPID(), let target = await accessibility.window(for: pid, anchorHeight: anchorHeight) else {
            return .failed("No movable window to control")
        }
        pendingPID = nil
        guard target.canMove || target.canResize else {
            return .failed("The frontmost window cannot be moved or resized")
        }

        let currentFrame = target.frame

        if placement == .restore {
            guard let previousFrame = restoreStore.frame(for: target.identity) else {
                return .failed("No previous frame to restore")
            }
            switch await accessibility.setFrame(previousFrame, for: target.identity, anchorHeight: anchorHeight) {
            case .applied:
                _ = restoreStore.removeFrame(for: target.identity)
                return .restored
            case .constrained:
                return .failed("The window could not be restored to its previous frame")
            case .cancelled:
                return .failed("Window restore was cancelled")
            case .failed:
                return .failed("Could not restore the window")
            }
        }

        guard let targetFrame = targetFrame(for: placement, currentFrame: currentFrame) else {
            return .failed(placement == .nextDisplay || placement == .previousDisplay ? "No other display available" : "Unsupported placement")
        }
        switch await accessibility.setFrame(targetFrame, for: target.identity, anchorHeight: anchorHeight) {
        case .applied:
            restoreStore.save(target.frame, for: target.identity)
            return .tiled(placement)
        case .constrained:
            restoreStore.save(target.frame, for: target.identity)
            return .constrained(placement)
        case .cancelled:
            return .failed("Window operation was cancelled")
        case .failed:
            return .failed("The frontmost window could not be resized")
        }
    }

    nonisolated static func resolvedTargetPID(frontmostPID: pid_t?, ownPID: pid_t, lastExternalPID: pid_t?) -> pid_t? {
        if let frontmostPID, frontmostPID != ownPID {
            return frontmostPID
        }
        if let lastExternalPID, lastExternalPID != ownPID {
            return lastExternalPID
        }
        return nil
    }

    nonisolated static func appkitFrame(fromAX frame: CGRect, anchorHeight: CGFloat) -> CGRect {
        CGRect(x: frame.minX, y: anchorHeight - frame.maxY, width: frame.width, height: frame.height)
    }

    nonisolated static func axFrame(fromAppKit frame: CGRect, anchorHeight: CGFloat) -> CGRect {
        CGRect(x: frame.minX, y: anchorHeight - frame.maxY, width: frame.width, height: frame.height)
    }

    nonisolated static func isAcceptableConstrainedFrame(_ actualAXFrame: CGRect, targetAXFrame: CGRect) -> Bool {
        abs(actualAXFrame.minX - targetAXFrame.minX) <= 4
            && abs(actualAXFrame.minY - targetAXFrame.minY) <= 4
            && actualAXFrame.width >= 100
            && actualAXFrame.height >= 60
    }

    private func currentTargetPID() -> pid_t? {
        if let target = targetProvider() {
            return target
        }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        if let frontmostPID, frontmostPID != ownPID {
            return frontmostPID
        }
        return Self.resolvedTargetPID(
            frontmostPID: frontmostPID,
            ownPID: ownPID,
            lastExternalPID: lastExternalPID
        )
    }

    private func targetPID() -> pid_t? {
        pendingPID ?? currentTargetPID()
    }

    private func targetFrame(for placement: WindowPlacement, currentFrame: CGRect) -> CGRect? {
        if placement == .nextDisplay || placement == .previousDisplay {
            return displayMoveFrame(for: placement, from: currentFrame)
        }
        guard let visibleFrame = screen(containing: currentFrame)?.visibleFrame else { return nil }
        return WindowLayoutEngine.frame(for: placement, currentFrame: currentFrame, visibleFrame: visibleFrame)
    }

    private func displayMoveFrame(for placement: WindowPlacement, from frame: CGRect) -> CGRect? {
        let screens = NSScreen.screens
        guard screens.count > 1,
              let currentScreen = screen(containing: frame),
              let currentIndex = screens.firstIndex(where: { $0 === currentScreen }) else {
            return nil
        }
        let direction: WindowDisplayLayout.Direction = placement == .nextDisplay ? .next : .previous
        guard let destinationIndex = WindowDisplayLayout.nextDisplayIndex(from: currentIndex, screens: screens.map(\.frame), direction: direction) else {
            return nil
        }
        let destination = screens[destinationIndex]
        let translated = CGRect(
            x: frame.minX + destination.frame.minX - currentScreen.frame.minX,
            y: frame.minY + destination.frame.minY - currentScreen.frame.minY,
            width: frame.width,
            height: frame.height
        )
        return WindowDisplayLayout.moveFrame(translated, to: destination.visibleFrame)
    }

    private func screen(containing frame: CGRect) -> NSScreen? {
        let center = CGPoint(x: frame.midX, y: frame.midY)
        return NSScreen.screens.first { $0.frame.contains(center) }
            ?? NSScreen.screens.first { $0.frame.intersects(frame) }
            ?? NSScreen.main
    }

    private static var screenMirrorAnchorHeight: CGFloat {
        let frame = NSScreen.screens.first { $0.frame.origin == .zero }?.frame ?? NSScreen.main?.frame
        guard let frame else { return 0 }
        return frame.maxY
    }

}

private actor NativeWindowAccessibilityClient: WindowAccessibilityClient {
    private var elementCache = WindowElementCache<AXUIElement>()

    func window(for pid: pid_t, anchorHeight: CGFloat) async -> AXWindowSnapshot? {
        let application = AXUIElementCreateApplication(pid)
        var focused: CFTypeRef?
        if AXUIElementCopyAttributeValue(application, attribute("AXFocusedWindow"), &focused) == .success,
           let focused,
           let element = standardWindow(unsafeDowncast(focused, to: AXUIElement.self), anchorHeight: anchorHeight) {
            return element
        }

        var windows: CFTypeRef?
        guard AXUIElementCopyAttributeValue(application, attribute("AXWindows"), &windows) == .success,
              let windows,
              CFGetTypeID(windows) == CFArrayGetTypeID() else { return nil }
        for window in axWindows(windows) {
            if let snapshot = standardWindow(window, anchorHeight: anchorHeight) {
                return snapshot
            }
        }
        return nil
    }

    func setFrame(_ frame: CGRect, for identity: WindowIdentity, anchorHeight: CGFloat) async -> WindowFrameApplicationResult {
        let application = AXUIElementCreateApplication(identity.pid)
        let element = elementCache.element(for: identity)
            ?? axWindowsForApplication(application).first(where: { windowIdentity(of: $0) == identity.windowNumber })
        guard let element else { return .failed }
        guard let originalAXFrame = currentFrame(of: element) else { return .failed }
        let targetAXFrame = NativeWindowManager.axFrame(fromAppKit: frame, anchorHeight: anchorHeight)
        var position = targetAXFrame.origin
        var size = targetAXFrame.size
        let needsMove = abs(originalAXFrame.minX - targetAXFrame.minX) > 1 || abs(originalAXFrame.minY - targetAXFrame.minY) > 1
        let needsResize = abs(originalAXFrame.width - targetAXFrame.width) > 1 || abs(originalAXFrame.height - targetAXFrame.height) > 1
        var canMove = DarwinBoolean(false)
        var canResize = DarwinBoolean(false)
        guard needsMove == false || (AXUIElementIsAttributeSettable(element, attribute("AXPosition"), &canMove) == .success && canMove.boolValue),
              needsResize == false || (AXUIElementIsAttributeSettable(element, attribute("AXSize"), &canResize) == .success && canResize.boolValue) else {
            return .failed
        }
        guard let positionValue = AXValueCreate(.cgPoint, &position),
              let sizeValue = AXValueCreate(.cgSize, &size),
              (needsResize == false || AXUIElementSetAttributeValue(element, attribute("AXSize"), sizeValue) == .success),
              (needsMove == false || AXUIElementSetAttributeValue(element, attribute("AXPosition"), positionValue) == .success) else {
            _ = rollback(originalAXFrame, element: element)
            return .failed
        }
        for _ in 0..<12 {
            if Task.isCancelled {
                _ = rollback(originalAXFrame, element: element)
                return .cancelled
            }
            if let actualAX = currentFrame(of: element) {
                let actual = NativeWindowManager.appkitFrame(fromAX: actualAX, anchorHeight: anchorHeight)
                if close(actual, to: frame) { return .applied(actual) }
                if NativeWindowManager.isAcceptableConstrainedFrame(actualAX, targetAXFrame: targetAXFrame) {
                    return .constrained(actual)
                }
            }
            try? await Task.sleep(for: .milliseconds(25))
        }
        _ = rollback(originalAXFrame, element: element)
        return .failed
    }

    private func standardWindow(_ element: AXUIElement, anchorHeight: CGFloat) -> AXWindowSnapshot? {
        guard isStandardWindow(element), let frame = currentFrame(of: element), let windowNumber = windowIdentity(of: element) else {
            return nil
        }
        let identity = WindowIdentity(pid: pid(of: element), windowNumber: windowNumber)
        elementCache.store(element, for: identity)
        return AXWindowSnapshot(
            identity: identity,
            frame: NativeWindowManager.appkitFrame(fromAX: frame, anchorHeight: anchorHeight),
            canMove: true,
            canResize: true
        )
    }

    private func rollback(_ frame: CGRect, element: AXUIElement) -> Bool {
        var position = frame.origin
        var size = frame.size
        guard let positionValue = AXValueCreate(.cgPoint, &position),
              let sizeValue = AXValueCreate(.cgSize, &size) else { return false }
        _ = AXUIElementSetAttributeValue(element, attribute("AXSize"), sizeValue)
        _ = AXUIElementSetAttributeValue(element, attribute("AXPosition"), positionValue)
        return true
    }

    private func pid(of element: AXUIElement) -> pid_t {
        var pid: pid_t = 0
        AXUIElementGetPid(element, &pid)
        return pid
    }

    private func isStandardWindow(_ element: AXUIElement) -> Bool {
        guard stringAttribute(attribute("AXRole"), of: element) == "AXWindow" else { return false }
        let subrole = stringAttribute(attribute("AXSubrole"), of: element)
        return subrole == nil || subrole == "AXStandardWindow"
    }

    private func axWindows(_ value: CFTypeRef) -> [AXUIElement] {
        let array = unsafeDowncast(value, to: CFArray.self)
        return (0..<CFArrayGetCount(array)).compactMap { index in
            guard let pointer = CFArrayGetValueAtIndex(array, index) else { return nil }
            return unsafeBitCast(pointer, to: AXUIElement.self)
        }
    }

    private func axWindowsForApplication(_ application: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(application, attribute("AXWindows"), &value) == .success,
              let value,
              CFGetTypeID(value) == CFArrayGetTypeID() else { return [] }
        return axWindows(value)
    }

    private func currentFrame(of element: AXUIElement) -> CGRect? {
        var position: CFTypeRef?
        var size: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute("AXPosition"), &position) == .success,
              AXUIElementCopyAttributeValue(element, attribute("AXSize"), &size) == .success,
              let position,
              let size else { return nil }
        var point = CGPoint.zero
        var dimensions = CGSize.zero
        guard AXValueGetValue(unsafeDowncast(position, to: AXValue.self), .cgPoint, &point),
              AXValueGetValue(unsafeDowncast(size, to: AXValue.self), .cgSize, &dimensions) else { return nil }
        return CGRect(origin: point, size: dimensions)
    }

    private func windowIdentity(of element: AXUIElement) -> String? {
        if let windowID = windowServerID(of: element) {
            return "cg:\(windowID)"
        }
        var identifier: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, attribute("AXIdentifier"), &identifier) == .success,
           let identifier,
           let value = identifier as? String,
           value.isEmpty == false {
            return value
        }
        return WindowIdentity.accessibilityElement(
            pid: pid(of: element),
            elementHash: CFHash(element)
        ).windowNumber
    }

    private func windowServerID(of element: AXUIElement) -> UInt32? {
        guard let bounds = currentFrame(of: element) else { return nil }
        let pid = pid(of: element)
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return nil }
        return windows.first { info in
            guard let ownerPID = info[kCGWindowOwnerPID as String] as? Int,
                  ownerPID == Int(pid),
                  let windowBounds = info[kCGWindowBounds as String] as? [String: CGFloat],
                  let x = windowBounds["X"],
                  let y = windowBounds["Y"],
                  let width = windowBounds["Width"],
                  let height = windowBounds["Height"],
                  let number = info[kCGWindowNumber as String] as? UInt32 else { return false }
            let candidate = CGRect(x: x, y: y, width: width, height: height)
            return close(candidate, to: bounds) && number != kCGNullWindowID
        }.flatMap { $0[kCGWindowNumber as String] as? UInt32 }
    }

    private func attribute(_ value: String) -> CFString {
        value as CFString
    }

    private func stringAttribute(_ attribute: CFString, of element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success,
              let value else { return nil }
        return value as? String
    }

    private func close(_ lhs: CGRect, to rhs: CGRect) -> Bool {
        abs(lhs.minX - rhs.minX) <= 4
            && abs(lhs.minY - rhs.minY) <= 4
            && abs(lhs.width - rhs.width) <= 4
            && abs(lhs.height - rhs.height) <= 4
    }
}
