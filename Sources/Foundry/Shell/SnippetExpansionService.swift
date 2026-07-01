import AppKit
import ApplicationServices
import Carbon
import Foundation

final class SnippetExpansionService: @unchecked Sendable {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var buffer = ""
    private var suppressing = false

    @MainActor
    func start() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        guard AXIsProcessTrustedWithOptions(options) else { return }
        guard eventTap == nil else { return }

        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else { return Unmanaged.passUnretained(event) }
            let service = Unmanaged<SnippetExpansionService>.fromOpaque(userInfo).takeUnretainedValue()
            return service.handle(type: type, event: event)
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(1 << CGEventType.keyDown.rawValue),
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        eventTap = tap
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    func stop() {
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        buffer = ""
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        guard type == .keyDown, suppressing == false else { return Unmanaged.passUnretained(event) }
        guard let nsEvent = NSEvent(cgEvent: event) else { return Unmanaged.passUnretained(event) }

        let flags = nsEvent.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.command) || flags.contains(.control) || flags.contains(.option) {
            return Unmanaged.passUnretained(event)
        }

        guard let characters = nsEvent.characters, characters.isEmpty == false else { return Unmanaged.passUnretained(event) }

        if characters == String(UnicodeScalar(NSDeleteCharacter)!) {
            if buffer.isEmpty == false { buffer.removeLast() }
            return Unmanaged.passUnretained(event)
        }

        guard characters.count == 1 else {
            if characters.contains("\n") || characters.contains("\r") || characters.contains("\t") || characters.contains(" ") {
                attemptExpansion(delimiter: characters)
            } else {
                buffer = ""
            }
            return Unmanaged.passUnretained(event) 
        }

        if isDelimiter(characters) {
            attemptExpansion(delimiter: characters)
        } else {
            buffer.append(characters)
            if buffer.count > 64 { buffer.removeFirst(buffer.count - 64) }
        }

        return Unmanaged.passUnretained(event)
    }

    private func attemptExpansion(delimiter: String) {
        defer { buffer = "" }
        let keyword = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard keyword.isEmpty == false,
              let snippet = matchingSnippet(for: keyword) else { return }
        expand(snippet: snippet, delimiter: delimiter)
    }

    private func matchingSnippet(for keyword: String) -> StoredSnippet? {
        LibraryPersistence.loadSnippets()
            .filter { $0.keyword.isEmpty == false }
            .sorted {
                if $0.isPinned != $1.isPinned { return $0.isPinned && !$1.isPinned }
                if $0.keyword.count != $1.keyword.count { return $0.keyword.count > $1.keyword.count }
                return $0.updatedAt > $1.updatedAt
            }
            .first { $0.keyword == keyword }
    }

    private func expand(snippet: StoredSnippet, delimiter: String) {
        suppressing = true
        let expanded = expandPlaceholders(in: snippet.content) + delimiter
        sendBackspaces(count: snippet.keyword.count + 1)
        sendText(expanded)
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.2) {
            self.suppressing = false
        }
    }

    private func sendBackspaces(count: Int) {
        guard count > 0 else { return }
        for _ in 0..<count {
            let down = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_Delete), keyDown: true)
            let up = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_Delete), keyDown: false)
            down?.post(tap: .cgAnnotatedSessionEventTap)
            up?.post(tap: .cgAnnotatedSessionEventTap)
        }
    }

    private func sendText(_ text: String) {
        let down = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true)
        let up = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false)
        down?.keyboardSetUnicodeString(stringLength: text.utf16.count, unicodeString: Array(text.utf16))
        up?.keyboardSetUnicodeString(stringLength: text.utf16.count, unicodeString: Array(text.utf16))
        down?.post(tap: .cgAnnotatedSessionEventTap)
        up?.post(tap: .cgAnnotatedSessionEventTap)
    }

    private func isDelimiter(_ value: String) -> Bool {
        value == " " || value == "\n" || value == "\r" || value == "\t" || value == "'" || value == "\"" || value == "`"
    }

    private func expandPlaceholders(in content: String) -> String {
        var value = content
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        value = value.replacingOccurrences(of: "{date}", with: formatter.string(from: Date()))
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        value = value.replacingOccurrences(of: "{time}", with: formatter.string(from: Date()))
        value = value.replacingOccurrences(of: "{clipboard}", with: NSPasteboard.general.string(forType: .string) ?? "")
        value = value.replacingOccurrences(of: "{cursor}", with: "")
        return value
    }
}
