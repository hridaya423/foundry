import AppKit
import Carbon
import SwiftUI
import FoundryDomain

/// Runs an NSOpenPanel/NSSavePanel as a sheet on the key window — the
/// Settings window when the call came from its UI — falling back to
/// app-modal only when no window is available.
@MainActor
func runFilePanelAsSheet(_ panel: NSSavePanel) async -> Bool {
    guard let window = NSApp.keyWindow ?? NSApp.mainWindow else {
        return panel.runModal() == .OK
    }
    return await withCheckedContinuation { continuation in
        panel.beginSheetModal(for: window) { response in
            continuation.resume(returning: response == .OK)
        }
    }
}

struct SettingsGroup<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0, content: content)
            .padding(.horizontal, 2)
            .background(FoundryTheme.fillSubtle)
            .clipShape(RoundedRectangle(cornerRadius: FoundryTheme.Radius.row, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: FoundryTheme.Radius.row, style: .continuous)
                    .stroke(FoundryTheme.separator, lineWidth: 1)
            )
    }
}

struct SettingsSectionLabel: View {
    let title: LocalizedStringResource
    let value: String?

    init(title: LocalizedStringResource, value: String? = nil) {
        self.title = title
        self.value = value
    }

    var body: some View {
        HStack {
            Text(title)
                .font(FoundryTheme.body)
                .foregroundStyle(FoundryTheme.textSecondary)
            Spacer()
            if let value {
                Text(value)
                    .font(FoundryTheme.bodySecondary)
                    .foregroundStyle(FoundryTheme.textTertiary)
            }
        }
        .padding(.horizontal, 2)
    }
}

struct SettingsDivider: View {
    var body: some View {
        Rectangle()
            .fill(FoundryTheme.fillTint)
            .frame(height: 1)
            .padding(.horizontal, 12)
    }
}

struct SettingsLabel: View {
    let title: LocalizedStringResource
    let subtitle: LocalizedStringResource

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(FoundryTheme.body)
                .foregroundStyle(FoundryTheme.textPrimary)
            Text(subtitle)
                .font(FoundryTheme.bodySecondary)
                .foregroundStyle(FoundryTheme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct SettingsToggleRow: View {
    let title: LocalizedStringResource
    let subtitle: LocalizedStringResource
    let isOn: Bool
    let set: (Bool) -> Void

    var body: some View {
        HStack(spacing: 12) {
            SettingsLabel(title: title, subtitle: subtitle)
            Spacer()
            Toggle("", isOn: Binding(get: { isOn }, set: { value in set(value) }))
                .labelsHidden()
                .toggleStyle(.switch)
                .accessibilityLabel(Text(title))
                .accessibilityValue(isOn ? String(localized: "On") : String(localized: "Off"))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
    }
}

struct SettingsNotice: View {
    let text: LocalizedStringResource
    let symbol: String
    var actionTitle: LocalizedStringResource? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        InlineNotice(level: .error, text: text, symbol: symbol, actionTitle: actionTitle, action: action)
    }
}

struct SettingsTextFieldRow: View {
    let title: LocalizedStringResource
    let placeholder: LocalizedStringResource
    let value: String
    let error: String?
    let commit: (String) -> Void

    @State private var text: String

    init(title: LocalizedStringResource, placeholder: LocalizedStringResource, value: String, error: String?, commit: @escaping (String) -> Void) {
        self.title = title
        self.placeholder = placeholder
        self.value = value
        self.error = error
        self.commit = commit
        _text = State(initialValue: value)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 10) {
                Text(title)
                    .font(FoundryTheme.body)
                    .foregroundStyle(FoundryTheme.textPrimary)
                    .frame(width: 72, alignment: .leading)
                VStack(alignment: .leading, spacing: 2) {
                    TextField(String(localized: placeholder), text: $text)
                        .textFieldStyle(.plain)
                        .font(FoundryTheme.body)
                        .foregroundStyle(FoundryTheme.textPrimary)
                        .modifier(CommitOnBlur { commit(text) })
                }
                Spacer()
            }
            if let error {
                Text(error)
                    .font(FoundryTheme.caption)
                    .foregroundStyle(FoundryTheme.destructive)
                    .padding(.leading, 82)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .onAppear { text = value }
        .onChange(of: value) { _, newValue in text = newValue }
    }
}

struct CommitOnBlur: ViewModifier {
    let commit: () -> Void
    @FocusState private var isFocused: Bool

    func body(content: Content) -> some View {
        content
            .focused($isFocused)
            .onSubmit(commit)
            .onChange(of: isFocused) { wasFocused, nowFocused in
                if wasFocused, nowFocused == false { commit() }
            }
    }
}

struct SettingsSecureFieldRow: View {
    let title: LocalizedStringResource
    let placeholder: LocalizedStringResource
    @Binding var value: String
    let commit: (String) -> Void

    var body: some View {
        HStack(spacing: 10) {
            Text(title)
                .font(FoundryTheme.body)
                .foregroundStyle(FoundryTheme.textPrimary)
                .frame(width: 72, alignment: .leading)
            SecureField(String(localized: placeholder), text: $value)
                .textFieldStyle(.plain)
                .font(FoundryTheme.body)
                .foregroundStyle(FoundryTheme.textPrimary)
                .modifier(CommitOnBlur { commit(value) })
            Button("Save") {
                commit(value)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
    }
}

struct ShortcutRecorder: NSViewRepresentable {
    let hotkey: FoundryHotkey
    var placeholder: String? = nil
    let onChange: (FoundryHotkey) -> Void
    var onClear: (() -> Void)? = nil

    func makeNSView(context: Context) -> ShortcutRecorderView {
        let view = ShortcutRecorderView()
        updateNSView(view, context: context)
        return view
    }

    func updateNSView(_ view: ShortcutRecorderView, context: Context) {
        view.hotkey = hotkey
        view.placeholder = placeholder
        view.onHotkey = onChange
        view.onClear = onClear
    }
}

final class ShortcutRecorderView: NSView {
    var hotkey = FoundryHotkey.commandSpace { didSet { needsDisplay = true } }
    var placeholder: String? { didSet { needsDisplay = true } }
    var onHotkey: ((FoundryHotkey) -> Void)?
    var onClear: (() -> Void)?
    private(set) var isRecording = false { didSet { needsDisplay = true } }

    override var acceptsFirstResponder: Bool { true }
    override var canBecomeKeyView: Bool { true }
    override var focusRingMaskBounds: NSRect { bounds }

    override func drawFocusRingMask() {
        NSBezierPath(roundedRect: bounds, xRadius: FoundryTheme.Radius.control, yRadius: FoundryTheme.Radius.control).fill()
    }

    override func draw(_ dirtyRect: NSRect) {
        let background = isRecording ? NSColor.labelColor.withAlphaComponent(0.14) : NSColor.labelColor.withAlphaComponent(0.08)
        background.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: FoundryTheme.Radius.control, yRadius: FoundryTheme.Radius.control).fill()

        let text = isRecording ? String(localized: "Press shortcut…") : (placeholder ?? hotkey.displayName)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: NSColor.labelColor.withAlphaComponent(isRecording ? 0.7 : 0.95)
        ]
        let size = text.size(withAttributes: attributes)
        text.draw(at: NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2), withAttributes: attributes)
    }

    override func mouseDown(with event: NSEvent) {
        isRecording = true
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        let plain = event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty
        guard isRecording else {
            switch (Int(event.keyCode), plain) {
            case (kVK_Space, true), (kVK_Return, true):
                isRecording = true
            case (kVK_Delete, true) where onClear != nil, (kVK_ForwardDelete, true) where onClear != nil:
                onClear?()
            default:
                super.keyDown(with: event)
            }
            return
        }
        if Int(event.keyCode) == kVK_Escape, plain {
            isRecording = false
            return
        }
        guard let recorded = FoundryHotkey(recording: event) else {
            NSSound.beep()
            return
        }
        isRecording = false
        onHotkey?(recorded)
    }

    override func resignFirstResponder() -> Bool {
        isRecording = false
        return super.resignFirstResponder()
    }

    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .button }
    override func accessibilityLabel() -> String? { isRecording ? String(localized: "Press shortcut…") : (placeholder ?? hotkey.displayName) }

    override func accessibilityPerformPress() -> Bool {
        isRecording = true
        window?.makeFirstResponder(self)
        return true
    }
}

struct ActiveWidgetRow: View {
    let kind: WidgetKind
    let isFirst: Bool
    let isLast: Bool
    let moveUp: () -> Void
    let moveDown: () -> Void
    let remove: () -> Void
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: kind.symbol)
                .font(FoundryTheme.Glyph.sm)
                .foregroundStyle(FoundryTheme.textSecondary)
                .frame(width: 20)
            SettingsLabel(title: kind.title, subtitle: kind.summary)
            Spacer()
            HStack(spacing: 10) {
                SettingsIconButton(symbol: "chevron.up", label: "Move \(kind.title) up", action: moveUp)
                    .disabled(isFirst)
                SettingsIconButton(symbol: "chevron.down", label: "Move \(kind.title) down", action: moveDown)
                    .disabled(isLast)
                SettingsIconButton(symbol: "minus", label: "Remove \(kind.title)", action: remove, tint: FoundryTheme.destructive)
            }
            .opacity(isHovering ? 1 : 0.5)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
    }
}

struct AvailableWidgetRow: View {
    let kind: WidgetKind
    let add: () -> Void

    var body: some View {
        Button(action: add) {
            HStack(spacing: 10) {
                Image(systemName: kind.symbol)
                    .font(FoundryTheme.Glyph.sm)
                    .foregroundStyle(FoundryTheme.textSecondary)
                    .frame(width: 20)
                SettingsLabel(title: kind.title, subtitle: kind.summary)
                Spacer()
                Image(systemName: "plus")
                    .font(FoundryTheme.Glyph.sm)
                    .foregroundStyle(FoundryTheme.textSecondary)
                    .frame(width: 24, height: 24)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
    }
}

struct SettingsIconButton: View {
    let symbol: String
    let label: LocalizedStringResource
    let action: () -> Void
    var tint: Color = FoundryTheme.textSecondary

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(FoundryTheme.Glyph.xs)
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
                .background(FoundryTheme.fillTint)
                .clipShape(RoundedRectangle(cornerRadius: FoundryTheme.Radius.control, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label))
        .help(Text(label))
    }
}

struct ConfigFieldRow: View {
    let title: LocalizedStringResource
    let placeholder: LocalizedStringResource
    let initialValue: String
    let commit: (String) -> Void
    @State private var text = ""

    var body: some View {
        HStack(spacing: 10) {
            Text(title)
                .font(FoundryTheme.body)
                .foregroundStyle(FoundryTheme.textPrimary)
                .frame(width: 112, alignment: .leading)
            TextField(String(localized: placeholder), text: $text)
                .textFieldStyle(.plain)
                .font(FoundryTheme.body)
                .foregroundStyle(FoundryTheme.textPrimary)
                .modifier(CommitOnBlur { commit(text) })
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .onAppear { text = initialValue }
    }
}

struct CommandSettingsRow: View {
    let row: CommandSettingsRowModel
    let isExpanded: Bool
    let setEnabled: (Bool) -> Void
    let setFavorite: (Bool) -> Void
    let commitAliases: (String) -> Void
    let setHotkey: (FoundryHotkey?) -> Void
    let setFallbackEligible: (Bool) -> Void
    let reset: () -> Void
    let toggleExpanded: () -> Void
    /// Owner of a chord (`launcher`/commandID) or nil when free.
    let hotkeyConflict: (UInt32, UInt32) -> String?

    @State private var aliasesText: String

    init(
        row: CommandSettingsRowModel,
        isExpanded: Bool,
        setEnabled: @escaping (Bool) -> Void,
        setFavorite: @escaping (Bool) -> Void,
        commitAliases: @escaping (String) -> Void,
        setHotkey: @escaping (FoundryHotkey?) -> Void,
        setFallbackEligible: @escaping (Bool) -> Void,
        reset: @escaping () -> Void,
        toggleExpanded: @escaping () -> Void,
        hotkeyConflict: @escaping (UInt32, UInt32) -> String?
    ) {
        self.row = row
        self.isExpanded = isExpanded
        self.setEnabled = setEnabled
        self.setFavorite = setFavorite
        self.commitAliases = commitAliases
        self.setHotkey = setHotkey
        self.setFallbackEligible = setFallbackEligible
        self.reset = reset
        self.toggleExpanded = toggleExpanded
        self.hotkeyConflict = hotkeyConflict
        _aliasesText = State(initialValue: row.preference.aliases.joined(separator: ", "))
    }

    private var suggestedHotkey: CommandHotkey? {
        guard row.id.hasPrefix("window.") else { return nil }
        guard let suggested = WindowPlacement(rawValue: String(row.id.dropFirst(7)))?.suggestedHotkey else {
            return nil
        }
        // Never offer a chord that's already bound elsewhere.
        guard hotkeyConflict(suggested.keyCode, suggested.modifiers) == nil else { return nil }
        return suggested
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 9) {
                CommandSettingsIcon(icon: row.icon)

                VStack(alignment: .leading, spacing: 2) {
                    Text(row.title)
                        .font(FoundryTheme.body)
                        .foregroundStyle(row.preference.isEnabled ? FoundryTheme.textPrimary : FoundryTheme.textTertiary)
                        .lineLimit(1)
                    Text(row.subtitle)
                        .font(FoundryTheme.caption)
                        .foregroundStyle(FoundryTheme.textTertiary)
                        .lineLimit(1)
                }

                Spacer()

                Button {
                    setFavorite(row.preference.favoriteRank == nil)
                } label: {
                    Image(systemName: row.preference.favoriteRank == nil ? "star" : "star.fill")
                        .font(FoundryTheme.Glyph.xs)
                        .foregroundStyle(row.preference.favoriteRank == nil ? FoundryTheme.textTertiary : FoundryTheme.accent)
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(row.preference.favoriteRank == nil ? "Favorite \(row.title)" : "Remove \(row.title) from favorites")

                Toggle("", isOn: Binding(get: { row.preference.isEnabled }, set: { value in setEnabled(value) }))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .scaleEffect(0.82)
                    .accessibilityLabel("Enable \(row.title)")

                Button {
                    if isExpanded {
                        commitAliases(aliasesText)
                    }
                    toggleExpanded()
                } label: {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(FoundryTheme.Glyph.xs)
                        .foregroundStyle(FoundryTheme.textTertiary)
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isExpanded ? "Hide settings for \(row.title)" : "Show settings for \(row.title)")
            }

            if isExpanded {
                HStack(spacing: 8) {
                    Text("Aliases")
                        .font(FoundryTheme.caption)
                        .foregroundStyle(FoundryTheme.textTertiary)
                        .frame(width: 48, alignment: .leading)
                    TextField("comma separated", text: $aliasesText)
                        .textFieldStyle(.plain)
                        .font(FoundryTheme.bodySecondary)
                        .foregroundStyle(FoundryTheme.textSecondary)
                        .modifier(CommitOnBlur { commitAliases(aliasesText) })
                    Spacer()
                    if row.preference.aliases.isEmpty == false || row.preference.favoriteRank != nil || row.preference.isEnabled == false
                        || row.preference.globalHotkey != nil || row.preference.fallbackEligible == false {
                        Button("Reset") { reset() }
                            .buttonStyle(.plain)
                            .font(FoundryTheme.caption)
                            .foregroundStyle(FoundryTheme.textTertiary)
                    }
                }

                HStack(spacing: 8) {
                    Text("Hotkey")
                        .font(FoundryTheme.caption)
                        .foregroundStyle(FoundryTheme.textTertiary)
                        .frame(width: 48, alignment: .leading)
                    ShortcutRecorder(
                        hotkey: row.preference.globalHotkey.map {
                            FoundryHotkey(keyCode: $0.keyCode, modifiers: $0.modifiers, displayName: $0.displayName)
                        } ?? FoundryHotkey(keyCode: 0, modifiers: 0, displayName: "Set shortcut"),
                        placeholder: row.preference.globalHotkey == nil ? "Set shortcut" : nil,
                        onChange: { setHotkey($0) },
                        onClear: { setHotkey(nil) }
                    )
                    .frame(width: FoundryTheme.Control.settingsColumn, height: FoundryTheme.Control.compact)
                    if row.preference.globalHotkey != nil {
                        Button("Clear") { setHotkey(nil) }
                            .buttonStyle(.plain)
                            .font(FoundryTheme.caption)
                            .foregroundStyle(FoundryTheme.textTertiary)
                    } else if let suggested = suggestedHotkey {
                        Button("Use \(suggested.displayName)") {
                            setHotkey(FoundryHotkey(keyCode: suggested.keyCode, modifiers: suggested.modifiers, displayName: suggested.displayName))
                        }
                        .buttonStyle(.plain)
                        .font(FoundryTheme.caption)
                        .foregroundStyle(FoundryTheme.textTertiary)
                        .help("Suggested shortcut")
                    }
                    Spacer()
                }

                Toggle("Use as fallback result", isOn: Binding(
                    get: { row.preference.fallbackEligible },
                    set: { setFallbackEligible($0) }
                ))
                .toggleStyle(.switch)
                .font(FoundryTheme.caption)
                .foregroundStyle(FoundryTheme.textTertiary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .onChange(of: row.preference.aliases) { _, newValue in
            aliasesText = newValue.joined(separator: ", ")
        }
        .onChange(of: isExpanded) { wasExpanded, nowExpanded in
            if wasExpanded && !nowExpanded {
                commitAliases(aliasesText)
            }
        }
    }
}

struct CommandSettingsIcon: View {
    let icon: CommandIcon
    @State private var appImage: NSImage?

    var body: some View {
        Group {
            if let appImage {
                Image(nsImage: appImage)
                    .resizable()
                    .scaledToFit()
            } else if let systemName = icon.systemName {
                Image(systemName: systemName)
                    .font(FoundryTheme.Glyph.sm)
                    .foregroundStyle(FoundryTheme.textSecondary)
            } else {
                Text(icon.fallback)
                    .font(FoundryTheme.micro)
                    .foregroundStyle(FoundryTheme.textSecondary)
            }
        }
        .frame(width: 28, height: 28)
        .task(id: icon.filePath) {
            guard let filePath = icon.filePath else { return }
            appImage = await CommandIconRepository.shared.image(for: filePath)
        }
    }
}

/// Excluded-apps editor: removable chips for current bundle IDs plus a
/// running-app picker, with a manual bundle-ID field as the escape hatch.
struct ExcludedAppsRow: View {
    let title: String
    let bundleIDs: [String]
    let commit: ([String]) -> Void

    @State private var manualID = ""

    private var runningApps: [NSRunningApplication] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != nil }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 10) {
                Text(title)
                    .font(FoundryTheme.body)
                    .foregroundStyle(FoundryTheme.textPrimary)
                    .frame(width: 112, alignment: .leading)

                Menu {
                    ForEach(runningApps, id: \.bundleIdentifier) { app in
                        if let bundleID = app.bundleIdentifier {
                            Button(app.localizedName ?? bundleID) { add(bundleID) }
                        }
                    }
                    if runningApps.isEmpty {
                        Text("No running apps")
                    }
                } label: {
                    Label("Add running app…", systemImage: "plus.circle")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .accessibilityLabel("Add a running app to the exclusion list")

                Spacer()
            }

            if bundleIDs.isEmpty == false {
                FlowLayout(spacing: 6) {
                    ForEach(bundleIDs, id: \.self) { bundleID in
                        HStack(spacing: 5) {
                            Text(appName(for: bundleID))
                                .lineLimit(1)
                            Button { remove(bundleID) } label: {
                                Image(systemName: "xmark")
                                    .font(FoundryTheme.Glyph.xs)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Remove \(appName(for: bundleID))")
                        }
                        .font(FoundryTheme.caption)
                        .foregroundStyle(FoundryTheme.textSecondary)
                        .padding(.horizontal, 9)
                        .frame(height: 24)
                        .background(
                            Capsule(style: .continuous).fill(FoundryTheme.fillTint)
                        )
                    }
                }
            }

            TextField("Or type a bundle ID, e.g. com.example.app", text: $manualID)
                .textFieldStyle(.plain)
                .font(FoundryTheme.mono)
                .foregroundStyle(FoundryTheme.textSecondary)
                .onSubmit {
                    let value = manualID.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard value.isEmpty == false else { return }
                    add(value)
                    manualID = ""
                }
                .accessibilityLabel("Add bundle identifier")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
    }

    private func appName(for bundleID: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return bundleID }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }

    private func add(_ bundleID: String) {
        guard bundleIDs.contains(bundleID) == false else { return }
        commit(bundleIDs + [bundleID])
    }

    private func remove(_ bundleID: String) {
        commit(bundleIDs.filter { $0 != bundleID })
    }
}

/// Minimal wrapping layout for chip rows.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 {
                x = 0
                y += lineHeight + spacing
                lineHeight = 0
            }
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
        return CGSize(width: width, height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var lineHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += lineHeight + spacing
                lineHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}
