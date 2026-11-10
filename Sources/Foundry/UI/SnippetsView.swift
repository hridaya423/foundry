import AppKit
import SwiftUI

struct SnippetsView: View {
    var state: SnippetState
    var expansionWarning: LocalizedStringResource?
    var openSnippetSettings: () -> Void = {}
    let insert: () -> Bool
    let copy: () -> Bool
    var delete: () -> Void = {}
    @AppStorage("snippets.editor.monospace") private var monospace = false

    var body: some View {
        HStack(spacing: 14) {
            sidebar
            detail
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                FoundrySectionHeader(title: String(localized: "Snippets"), count: state.visibleItems.count.formatted())
                    .padding(.leading, 11)
                Menu {
                    Picker("Sort by", selection: Binding(
                        get: { state.sortMode },
                        set: { state.sortMode = $0 }
                    )) {
                        ForEach(SnippetState.SortMode.allCases, id: \.self) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.inline)
                    Divider()
                    Button("Import Snippets…") { state.importFromFile() }
                    Button("Export Snippets…") { state.exportToFile() }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(FoundryTheme.Glyph.xs)
                        .foregroundStyle(FoundryTheme.textSecondary)
                        .frame(width: 30, height: 30)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Import or export snippets")
                SnippetIconButton(symbol: "plus", help: "New snippet", action: state.newSnippet)
            }
            .frame(height: FoundryTheme.Control.compact)

            if state.allTags.isEmpty == false {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 5) {
                        tagChip(label: "All", selected: state.selectedTag == nil) {
                            state.selectedTag = nil
                        }
                        ForEach(state.allTags, id: \.self) { tag in
                            tagChip(label: "#\(tag)", selected: state.selectedTag == tag) {
                                state.selectedTag = state.selectedTag == tag ? nil : tag
                            }
                        }
                    }
                    .padding(.horizontal, 11)
                    .padding(.vertical, 2)
                }
            }

            if state.items.isEmpty {
                sidebarEmptyState
            } else if state.visibleItems.isEmpty {
                noMatchesState
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 3) {
                            ForEach(state.visibleItems) { snippet in
                                SnippetRow(
                                    snippet: snippet,
                                    subtitle: Self.firstLine(of: snippet.content),
                                    isSelected: state.selectedItem?.id == snippet.id,
                                    select: { state.select(id: snippet.id) }
                                )
                            }
                        }
                        .padding(.bottom, 2)
                    }
                    .scrollIndicators(.never)
                    .onChange(of: state.selectedID) { _, id in
                        guard let id else { return }
                        proxy.scrollTo(id)
                    }
                }
            }
        }
        .padding(16)
        .frame(width: 264)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .modifier(SnippetPanelSurface())
    }

    private var sidebarEmptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "curlybraces")
                .font(FoundryTheme.Glyph.lg)
                .foregroundStyle(FoundryTheme.textQuaternary)
            Text("No snippets yet")
                .font(FoundryTheme.body)
                .foregroundStyle(FoundryTheme.textSecondary)
            newSnippetButton
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var noMatchesState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "magnifyingglass")
                .font(FoundryTheme.Glyph.lg)
                .foregroundStyle(FoundryTheme.textQuaternary)
            Text("No matching snippets")
                .font(FoundryTheme.body)
                .foregroundStyle(FoundryTheme.textSecondary)
            FoundryActionButton(title: String(localized: "Clear Filters")) {
                state.query = ""
                state.selectedTag = nil
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var detail: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let persistenceError = state.persistenceError {
                InlineNotice(level: .error, text: "\(persistenceError)")
            }
            if let selected = state.selectedItem {
                HStack(spacing: 4) {
                    FoundrySectionHeader(title: String(localized: "Edit Snippet"))
                        .padding(.leading, 13)
                    SnippetIconButton(
                        symbol: monospace ? "textformat" : "chevron.left.forwardslash.chevron.right",
                        help: monospace ? "Show proportional text" : "Show monospaced text",
                        action: { monospace.toggle() }
                    )
                    SnippetIconButton(
                        symbol: selected.isPinned ? "pin.fill" : "pin",
                        help: selected.isPinned ? "Unpin" : "Pin",
                        tint: selected.isPinned ? FoundryTheme.textPrimary : FoundryTheme.textSecondary,
                        action: state.togglePinnedSelected
                    )
                    SnippetIconButton(symbol: "doc.on.doc", help: "Copy to clipboard", action: { _ = copy() })
                    SnippetIconButton(symbol: "arrow.down.doc", help: "Insert snippet", action: { _ = insert() })
                    SnippetIconButton(symbol: "trash", help: "Delete snippet", destructive: true, action: delete)
                }
                .frame(height: FoundryTheme.Control.compact)
                SnippetEditor(state: state, monospace: monospace)
                if let duplicate = state.duplicateKeyword {
                    InlineNotice(level: .warning,
                        text: "“\(duplicate.keyword)” is used by \(duplicate.count) snippets. Rename one to turn expansion back on.")
                }
                if let expansionWarning {
                    InlineNotice(level: .warning, text: expansionWarning, actionTitle: "Open Settings", action: openSnippetSettings)
                }
            } else {
                detailEmptyState
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .modifier(SnippetPanelSurface())
    }

    private var detailEmptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "curlybraces.square")
                .font(FoundryTheme.Glyph.xl)
                .foregroundStyle(FoundryTheme.textQuaternary)
            VStack(spacing: 4) {
                Text("No snippet selected")
                    .font(FoundryTheme.body)
                    .foregroundStyle(FoundryTheme.textSecondary)
                Text("Create a snippet or pick one from the list.")
                    .font(FoundryTheme.bodySecondary)
                    .foregroundStyle(FoundryTheme.textTertiary)
            }
            newSnippetButton
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var newSnippetButton: some View {
        FoundryActionButton(title: String(localized: "New Snippet"), systemName: "plus", action: state.newSnippet)
    }

    private func tagChip(label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(FoundryTheme.caption)
                .foregroundStyle(selected ? FoundryTheme.textPrimary : FoundryTheme.textSecondary)
                .padding(.horizontal, 8)
                .frame(height: FoundryTheme.Control.line)
                .background(
                    Capsule(style: .continuous)
                        .fill(selected ? FoundryTheme.accentTintFill : FoundryTheme.fillHover)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Filter by tag \(label)")
    }

    static func firstLine(of content: String) -> String {
        content.split(whereSeparator: \.isNewline).lazy
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { $0.isEmpty == false } ?? ""
    }
}

private struct SnippetPanelSurface: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(FoundryTheme.fillHover)
            .clipShape(RoundedRectangle(cornerRadius: FoundryTheme.Radius.popover, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: FoundryTheme.Radius.popover, style: .continuous)
                    .strokeBorder(FoundryTheme.fillTint, lineWidth: 1)
            )
    }
}

private struct SnippetIconButton: View {
    let symbol: String
    var help: String = ""
    var tint: Color = FoundryTheme.textSecondary
    var destructive = false
    let action: () -> Void

    @State private var isHovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var foreground: Color {
        if isHovering {
            return destructive ? FoundryTheme.destructive : FoundryTheme.textPrimary
        }
        return tint
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(FoundryTheme.Glyph.sm)
                .foregroundStyle(foreground)
                .frame(width: 30, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: FoundryTheme.Radius.control, style: .continuous)
                        .fill(isHovering ? FoundryTheme.fillHover : .clear)
                )
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
        .animation(reduceMotion ? nil : FoundryTheme.Motion.hover, value: isHovering)
        .onHover { isHovering = $0 }
    }
}

private struct SnippetRow: View {
    let snippet: StoredSnippet
    let subtitle: String
    let isSelected: Bool
    let select: () -> Void

    @State private var isHovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(snippet.title.isEmpty ? "Untitled Snippet" : snippet.title)
                        .font(FoundryTheme.body)
                        .foregroundStyle(FoundryTheme.textPrimary)
                        .lineLimit(1)
                    if snippet.isPinned {
                        Image(systemName: "pin.fill")
                            .font(FoundryTheme.Glyph.xs)
                            .foregroundStyle(FoundryTheme.textTertiary)
                    }
                }
                if subtitle.isEmpty == false {
                    Text(subtitle)
                        .font(FoundryTheme.caption)
                        .foregroundStyle(FoundryTheme.textTertiary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if snippet.keyword.isEmpty == false {
                Text(snippet.keyword)
                    .font(FoundryTheme.mono)
                    .foregroundStyle(FoundryTheme.textSecondary)
                    .lineLimit(1)
                    .padding(.horizontal, 6)
                    .frame(height: FoundryTheme.Control.line)
                    .background(FoundryTheme.fillTint, in: RoundedRectangle(cornerRadius: FoundryTheme.Radius.badge, style: .continuous))
            }
        }
        .padding(.horizontal, FoundryTheme.Spacing.sm)
        .frame(height: FoundryTheme.Control.row)
        .background(RowBackground(isSelected: isSelected, isHovering: isHovering))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(snippet.title.isEmpty ? "Untitled Snippet" : snippet.title)
        .accessibilityValue(snippet.keyword.isEmpty ? subtitle : "\(subtitle), keyword \(snippet.keyword)")
        .accessibilityAddTraits(.isButton)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityHint("Select snippet")
        .onTapGesture(perform: select)
        .animation(reduceMotion ? nil : FoundryTheme.Motion.hover, value: isHovering)
        .onHover { isHovering = $0 }
    }
}

struct SnippetEditor: View {
    var state: SnippetState
    var monospace: Bool
    @FocusState private var titleFocused: Bool
    @State private var title = ""
    @State private var keyword = ""
    @State private var tags = ""
    @State private var content = ""
    @State private var insertRequest: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Snippet title", text: $title)
                .focused($titleFocused)
                .textFieldStyle(.plain)
                .font(FoundryTheme.body)
                .foregroundStyle(FoundryTheme.textPrimary)
                .padding(.horizontal, 13)
                .frame(height: FoundryTheme.Control.row)
                .background(fieldBackground)

            HStack(spacing: 10) {
                labeledField(icon: "number", placeholder: "Keyword", text: $keyword)
                labeledField(icon: "tag", placeholder: "Tags, comma separated", text: $tags)
            }

            ZStack(alignment: .topLeading) {
                if content.isEmpty {
                    Text("Write your snippet…")
                        .font(FoundryTheme.bodySecondary)
                        .foregroundStyle(FoundryTheme.textQuaternary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .allowsHitTesting(false)
                }
                SnippetTextEditor(text: $content, insertRequest: $insertRequest, monospace: monospace)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
            }
            .frame(maxWidth: .infinity, minHeight: 88, maxHeight: .infinity)
            .background(fieldBackground)

            HStack(spacing: 8) {
                Menu {
                    ForEach(Self.placeholders, id: \.token) { placeholder in
                        Button {
                            insertRequest = placeholder.token
                        } label: {
                            VStack(alignment: .leading) {
                                Text(placeholder.title)
                                Text(placeholder.token).font(.caption)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "curlybraces")
                            .font(FoundryTheme.Glyph.xs)
                        Text("Insert Placeholder")
                            .font(FoundryTheme.micro)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(FoundryTheme.Glyph.xs)
                            .foregroundStyle(FoundryTheme.textQuaternary)
                    }
                    .foregroundStyle(FoundryTheme.textSecondary)
                    .padding(.horizontal, 10)
                    .frame(height: FoundryTheme.Control.mini)
                    .background(
                        Capsule()
                            .fill(FoundryTheme.fillHover)
                            .overlay(Capsule().strokeBorder(FoundryTheme.fillTint, lineWidth: 1))
                    )
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Insert a dynamic placeholder at the cursor")

                Spacer(minLength: 8)

                Text(footerDetail)
                    .font(FoundryTheme.caption.monospacedDigit())
                    .foregroundStyle(FoundryTheme.textTertiary)
                    .lineLimit(1)
            }
            .padding(.leading, 2)

            let rendered = SnippetRenderer.render(content)
            if rendered.text != content {
                VStack(alignment: .leading, spacing: 4) {
                    FoundrySectionHeader(title: String(localized: "Preview"))
                    Text(rendered.text)
                        .font(FoundryTheme.bodySecondary)
                        .foregroundStyle(FoundryTheme.textSecondary)
                        .lineLimit(3)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 13)
                .padding(.vertical, 9)
                .background(fieldBackground)
            }
        }
        .onAppear { sync() }
        .onChange(of: state.selectedID) { _, id in
            sync()
            if id != nil, id == state.freshSnippetID { titleFocused = true }
        }
        .onChange(of: title) { _, _ in persist() }
        .onChange(of: keyword) { _, _ in persist() }
        .onChange(of: tags) { _, _ in persist() }
        .onChange(of: content) { _, _ in persist() }
    }

    private func labeledField(icon: String, placeholder: String, text: Binding<String>) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(FoundryTheme.Glyph.xs)
                .foregroundStyle(FoundryTheme.textQuaternary)
            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .font(FoundryTheme.body)
                .foregroundStyle(FoundryTheme.textPrimary)
        }
        .padding(.horizontal, 12)
        .frame(height: FoundryTheme.Control.field)
        .frame(maxWidth: .infinity)
        .background(fieldBackground)
    }

    private var footerDetail: String {
        var parts = [String(localized: "\(content.count.formatted()) characters")]
        if let selected = state.selectedItem {
            parts.insert(Self.edited(selected.updatedAt), at: 0)
            if selected.useCount > 0 { parts.insert(String(localized: "Used \(selected.useCount)×"), at: 0) }
        }
        return parts.joined(separator: " · ")
    }

    static func edited(_ date: Date, now: Date = .now) -> String {
        guard now.timeIntervalSince(date) >= 60 else { return String(localized: "Edited just now") }
        return String(localized: "Edited \(relative.localizedString(for: date, relativeTo: now))")
    }

    private static let relative: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    private var fieldBackground: some View {
        RoundedRectangle(cornerRadius: FoundryTheme.Radius.row, style: .continuous)
            .fill(FoundryTheme.fillHover)
            .overlay(
                RoundedRectangle(cornerRadius: FoundryTheme.Radius.row, style: .continuous)
                    .strokeBorder(FoundryTheme.fillTint, lineWidth: 1)
            )
    }

    private func sync() {
        title = state.selectedItem?.title ?? ""
        keyword = state.selectedItem?.keyword ?? ""
        tags = state.selectedItem?.tags.joined(separator: ", ") ?? ""
        content = state.selectedItem?.content ?? ""
    }

    private func persist() {
        state.updateSelected(title: title, content: content, keyword: keyword,
            tags: tags.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) })
    }
}

extension SnippetEditor {
    static let placeholders: [(title: String, token: String)] = [
        ("Clipboard contents", "{clipboard}"),
        ("Selected text", "{selection}"),
        ("Current date", "{date}"),
        ("Current time", "{time}"),
        ("Custom date format", "{date:yyyy-MM-dd}"),
        ("Cursor position", "{cursor}"),
        ("Prompt for a value", "{argument name=\"value\"}")
    ]
}

private struct SnippetTextEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var insertRequest: String?
    var monospace: Bool

    private var font: NSFont {
        monospace ? .monospacedSystemFont(ofSize: 12, weight: .regular) : .systemFont(ofSize: 13)
    }

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .noBorder

        let textView = NSTextView()
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.font = font
        textView.textColor = NSColor.labelColor
        textView.insertionPointColor = NSColor.labelColor
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 0, height: 2)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.delegate = context.coordinator
        context.coordinator.textView = textView
        textView.string = text

        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        if textView.font != font { textView.font = font }
        if textView.string != text {
            let selection = textView.selectedRange()
            textView.string = text
            if selection.location <= text.utf16.count {
                textView.setSelectedRange(selection)
            }
        }
        if let token = insertRequest {
            insertRequest = nil
            textView.insertText(token, replacementRange: textView.selectedRange())
            textView.window?.makeFirstResponder(textView)
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        weak var textView: NSTextView?

        init(text: Binding<String>) { self.text = text }

        func textDidChange(_ notification: Notification) {
            guard let textView else { return }
            text.wrappedValue = textView.string
        }
    }
}

struct SnippetArgumentPrompt: View {
    let names: [String]
    let onCancel: () -> Void
    let onSubmit: ([String: String]) -> Void
    @State private var values: [String: String] = [:]
    @FocusState private var focused: String?

    var body: some View {
        ZStack {
            FoundryTheme.scrim
                .onTapGesture(perform: onCancel)
            FoundryGlassSurface(role: .floatingOverlay, shape: RoundedRectangle(cornerRadius: FoundryTheme.Radius.popover, style: .continuous)) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(names.count == 1 ? "One placeholder to fill in" : "\(names.count) placeholders to fill in")
                        .font(FoundryTheme.body)
                        .foregroundStyle(FoundryTheme.textPrimary)
                    ForEach(names, id: \.self) { name in
                        TextField(name, text: binding(for: name))
                            .textFieldStyle(.plain)
                            .font(FoundryTheme.bodySecondary)
                            .foregroundStyle(FoundryTheme.textPrimary)
                            .padding(.horizontal, 12)
                            .frame(height: FoundryTheme.Control.compact)
                            .background(FoundryTheme.fillHover, in: RoundedRectangle(cornerRadius: FoundryTheme.Radius.control, style: .continuous))
                            .focused($focused, equals: name)
                            .onSubmit(submit)
                    }
                    HStack(spacing: 8) {
                        Button(action: onCancel) {
                            Text("Cancel")
                                .font(FoundryTheme.bodySecondary)
                                .foregroundStyle(FoundryTheme.textSecondary)
                                .padding(.horizontal, 10)
                                .frame(height: FoundryTheme.Control.mini)
                                .contentShape(.rect)
                        }
                        .buttonStyle(FoundryQuietButtonStyle())
                        Spacer()
                        Button(action: submit) {
                            Text("Insert")
                                .font(FoundryTheme.body)
                                .foregroundStyle(FoundryTheme.textPrimary)
                                .padding(.horizontal, 13)
                                .frame(height: FoundryTheme.Control.compact)
                                .background(FoundryTheme.fillTint, in: RoundedRectangle(cornerRadius: FoundryTheme.Radius.control, style: .continuous))
                                .contentShape(.rect)
                        }
                        .buttonStyle(PressableButtonStyle())
                        .keyboardShortcut(.defaultAction)
                    }
                }
                .padding(16)
                .frame(width: 340)
            }
            .shadow(color: FoundryTheme.shadow, radius: 24, y: 10)
        }
        .onAppear { focused = names.first }
    }

    private func binding(for name: String) -> Binding<String> {
        Binding(get: { values[name] ?? "" }, set: { values[name] = $0 })
    }

    private func submit() { onSubmit(values) }
}
