import AppKit
import SwiftUI

struct SnippetsView: View {
    var state: SnippetState
    var expansionEnabled = true
    var setExpansionEnabled: ((Bool) -> Void)? = nil
    let insert: () -> Bool
    @State private var isConfirmingDelete = false

    var body: some View {
        HStack(spacing: 14) {
            sidebar
            detail
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .alert("Delete Snippet?", isPresented: $isConfirmingDelete) {
            Button("Delete Snippet", role: .destructive) { state.removeSelected() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the snippet from Foundry's saved library.")
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text(state.visibleItems.count == 1 ? "1 SNIPPET" : "\(state.visibleItems.count) SNIPPETS")
                    .font(FoundryTheme.micro)
                    .foregroundStyle(FoundryTheme.textQuaternary)
                    .tracking(0.6)
                    .padding(.leading, 11)
                Spacer()
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
            .frame(height: 30)

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
                ScrollView {
                    LazyVStack(spacing: 3) {
                        ForEach(state.visibleItems) { snippet in
                            SnippetRow(
                                snippet: snippet,
                                subtitle: snippetSubtitle(snippet),
                                isSelected: state.selectedItem?.id == snippet.id,
                                select: { state.select(id: snippet.id) }
                            )
                        }
                    }
                    .padding(.bottom, 2)
                }
                .scrollIndicators(.never)
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
            Button("Clear filters") {
                state.query = ""
                state.selectedTag = nil
            }
                .buttonStyle(PressableButtonStyle())
                .font(FoundryTheme.body)
                .foregroundStyle(FoundryTheme.textPrimary)
                .padding(.horizontal, 14)
                .frame(height: 32)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(FoundryTheme.fillTint)
                        .overlay(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .strokeBorder(FoundryTheme.fillSelected, lineWidth: 1)
                        )
                )
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var detail: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let persistenceError = state.persistenceError {
                Label(persistenceError, systemImage: "exclamationmark.triangle.fill")
                    .font(FoundryTheme.bodySecondary)
                    .foregroundStyle(FoundryTheme.destructive)
                    .lineLimit(2)
            }
            if let selected = state.selectedItem {
                HStack(spacing: 4) {
                    Text("EDIT SNIPPET")
                        .font(FoundryTheme.micro)
                        .foregroundStyle(FoundryTheme.textQuaternary)
                        .tracking(0.6)
                        .padding(.leading, 13)
                    Spacer()
                    SnippetIconButton(
                        symbol: selected.isPinned ? "pin.fill" : "pin",
                        help: selected.isPinned ? "Unpin" : "Pin",
                        tint: selected.isPinned ? FoundryTheme.textPrimary : FoundryTheme.textSecondary,
                        action: state.togglePinnedSelected
                    )
                    SnippetIconButton(symbol: "doc.on.doc", help: "Copy to clipboard", action: state.copySelected)
                    SnippetIconButton(symbol: "arrow.down.doc", help: "Insert snippet", action: { _ = insert() })
                    SnippetIconButton(symbol: "trash", help: "Delete snippet", destructive: true, action: { isConfirmingDelete = true })
                }
                .frame(height: 30)
                SnippetEditor(state: state)
                if state.duplicateKeywords.isEmpty == false {
                    Label(
                        "Duplicate keywords: \(state.duplicateKeywords.joined(separator: ", ")). "
                            + "Save is allowed, but auto-expansion is disabled until resolved.",
                        systemImage: "exclamationmark.triangle"
                    )
                        .font(FoundryTheme.caption)
                        .foregroundStyle(FoundryTheme.destructive)
                        .lineLimit(2)
                }
                HStack(spacing: 8) {
                    Text(state.expansionAvailabilityMessage)
                        .font(FoundryTheme.caption)
                        .foregroundStyle(FoundryTheme.textQuaternary)
                    Spacer()
                    if let setExpansionEnabled {
                        Toggle("Auto-expand", isOn: Binding(
                            get: { expansionEnabled },
                            set: { setExpansionEnabled($0) }
                        ))
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                        .font(FoundryTheme.caption)
                        .foregroundStyle(FoundryTheme.textSecondary)
                        .accessibilityLabel("Auto-expand snippet keywords")
                    }
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
        Button(action: state.newSnippet) {
            HStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(FoundryTheme.Glyph.xs)
                Text("New Snippet")
                    .font(FoundryTheme.body)
            }
            .foregroundStyle(FoundryTheme.textPrimary)
            .padding(.horizontal, 14)
            .frame(height: 32)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(FoundryTheme.fillTint)
                    .overlay(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .strokeBorder(FoundryTheme.fillSelected, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(PressableButtonStyle())
    }

    private func tagChip(label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(FoundryTheme.caption)
                .foregroundStyle(selected ? FoundryTheme.textPrimary : FoundryTheme.textSecondary)
                .padding(.horizontal, 8)
                .frame(height: 22)
                .background(
                    Capsule(style: .continuous)
                        .fill(selected ? FoundryTheme.accentTintFill : FoundryTheme.fillHover)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Filter by tag \(label)")
    }

    private func snippetSubtitle(_ snippet: StoredSnippet) -> String {
        let parts: [String?] = [
            snippet.keyword.isEmpty ? nil : snippet.keyword,
            snippet.tags.isEmpty ? nil : snippet.tags.map { "#\($0)" }.joined(separator: " "),
            snippet.useCount > 0 ? "used \(snippet.useCount)×" : nil,
            relativeDate(snippet.updatedAt)
        ]
        return parts.compactMap { $0 }.joined(separator: "  •  ")
    }
}

private struct SnippetPanelSurface: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(FoundryTheme.fillHover)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
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
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(isHovering ? 0.09 : 0))
                )
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isHovering)
        .onHover { hovering in
            isHovering = hovering

        }
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
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
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
        }
        .padding(.horizontal, 11)
        .frame(height: 48)
        .background(RowBackground(isSelected: isSelected, isHovering: isHovering, cornerRadius: 10))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(snippet.title.isEmpty ? "Untitled Snippet" : snippet.title)
        .accessibilityValue(isSelected ? "Selected" : subtitle)
        .accessibilityAddTraits(.isButton)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityHint("Select snippet")
        .onTapGesture(perform: select)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.10), value: isHovering)
        .onHover { hovering in
            isHovering = hovering

        }
    }
}

private struct SnippetEditor: View {
    var state: SnippetState
    @State private var title = ""
    @State private var keyword = ""
    @State private var tags = ""
    @State private var content = ""
    @State private var insertRequest: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Snippet title", text: $title)
                .textFieldStyle(.plain)
                .font(FoundryTheme.body)
                .foregroundStyle(FoundryTheme.textPrimary)
                .padding(.horizontal, 13)
                .frame(height: 40)
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
                SnippetTextEditor(text: $content, insertRequest: $insertRequest)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                        Text("Insert placeholder")
                            .font(FoundryTheme.micro)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(FoundryTheme.Glyph.xs)
                            .foregroundStyle(FoundryTheme.textQuaternary)
                    }
                    .foregroundStyle(FoundryTheme.textSecondary)
                    .padding(.horizontal, 10)
                    .frame(height: 24)
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

                Text("Dynamic values fill in when the snippet is pasted")
                    .font(FoundryTheme.caption)
                    .foregroundStyle(FoundryTheme.textQuaternary)
                    .lineLimit(1)

                Spacer(minLength: 8)

                Text("\(content.count.formatted()) characters")
                    .font(FoundryTheme.mono)
                    .foregroundStyle(FoundryTheme.textQuaternary)
                    .contentTransition(.numericText())
            }
            .padding(.leading, 2)

            let rendered = SnippetRenderer.render(content)
            if rendered.text != content {
                VStack(alignment: .leading, spacing: 4) {
                    Text("PREVIEW")
                        .font(FoundryTheme.micro)
                        .foregroundStyle(FoundryTheme.textQuaternary)
                        .tracking(0.6)
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
        .onChange(of: state.selectedID) { _, _ in sync() }
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
        .frame(height: 36)
        .frame(maxWidth: .infinity)
        .background(fieldBackground)
    }

    private var fieldBackground: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(FoundryTheme.fillHover)
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
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
        textView.font = NSFont.systemFont(ofSize: 13.5)
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

private func relativeDate(_ date: Date) -> String {
    let seconds = max(0, Int(Date().timeIntervalSince(date)))
    if seconds < 60 { return "now" }
    let minutes = seconds / 60
    if minutes < 60 { return "\(minutes)m ago" }
    let hours = minutes / 60
    if hours < 24 { return "\(hours)h ago" }
    return "\(hours / 24)d ago"
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
            VStack(alignment: .leading, spacing: 12) {
                Text(names.count == 1 ? "One placeholder to fill in" : "\(names.count) placeholders to fill in")
                    .font(FoundryTheme.body)
                    .foregroundStyle(FoundryTheme.textPrimary)
                ForEach(names, id: \.self) { name in
                    TextField(name, text: binding(for: name))
                        .textFieldStyle(.plain)
                        .font(FoundryTheme.bodySecondary)
                        .foregroundStyle(FoundryTheme.textPrimary)
                        .padding(.horizontal, 13)
                        .frame(height: 36)
                        .background(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(FoundryTheme.fillHover)
                        )
                        .focused($focused, equals: name)
                        .onSubmit(submit)
                }
                HStack {
                    Button("Cancel", action: onCancel)
                        .keyboardShortcut(.cancelAction)
                    Spacer()
                    Button("Insert", action: submit)
                        .keyboardShortcut(.defaultAction)
                }
                .buttonStyle(PressableButtonStyle())
            }
            .padding(18)
            .frame(width: 320)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(nsColor: .windowBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(FoundryTheme.fillSelected, lineWidth: 1)
                    )
            )
        }
        .onAppear { focused = names.first }
    }

    private func binding(for name: String) -> Binding<String> {
        Binding(get: { values[name] ?? "" }, set: { values[name] = $0 })
    }

    private func submit() { onSubmit(values) }
}
