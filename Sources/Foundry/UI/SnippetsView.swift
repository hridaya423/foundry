import AppKit
import SwiftUI

struct SnippetsView: View {
    @ObservedObject var state: SnippetState
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
                    .font(FoundryTheme.body(size: 11, weight: .semibold))
                    .foregroundStyle(FoundryTheme.faintText)
                    .tracking(0.6)
                    .padding(.leading, 11)
                Spacer()
                SnippetIconButton(symbol: "plus", help: "New snippet", action: state.newSnippet)
            }
            .frame(height: 30)

            if state.visibleItems.isEmpty {
                sidebarEmptyState
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
                .font(.system(size: 24, weight: .regular))
                .foregroundStyle(FoundryTheme.faintText)
            Text("No snippets yet")
                .font(FoundryTheme.body(size: 13, weight: .medium))
                .foregroundStyle(FoundryTheme.secondaryText)
            newSnippetButton
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var detail: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let persistenceError = state.persistenceError {
                Label(persistenceError, systemImage: "exclamationmark.triangle.fill")
                    .font(FoundryTheme.body(size: 12, weight: .medium))
                    .foregroundStyle(FoundryTheme.error)
                    .lineLimit(2)
            }
            if let selected = state.selectedItem {
                HStack(spacing: 4) {
                    Text("EDIT SNIPPET")
                        .font(FoundryTheme.body(size: 11, weight: .semibold))
                        .foregroundStyle(FoundryTheme.faintText)
                        .tracking(0.6)
                        .padding(.leading, 13)
                    Spacer()
                    SnippetIconButton(
                        symbol: selected.isPinned ? "pin.fill" : "pin",
                        help: selected.isPinned ? "Unpin" : "Pin",
                        tint: selected.isPinned ? FoundryTheme.primaryText : FoundryTheme.secondaryText,
                        action: state.togglePinnedSelected
                    )
                    SnippetIconButton(symbol: "doc.on.doc", help: "Copy to clipboard", action: state.copySelected)
                    SnippetIconButton(symbol: "trash", help: "Delete snippet", destructive: true, action: { isConfirmingDelete = true })
                }
                .frame(height: 30)
                SnippetEditor(state: state)
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
                .font(.system(size: 30, weight: .regular))
                .foregroundStyle(FoundryTheme.faintText)
            VStack(spacing: 4) {
                Text("No snippet selected")
                    .font(FoundryTheme.body(size: 14, weight: .semibold))
                    .foregroundStyle(FoundryTheme.secondaryText)
                Text("Create a snippet or pick one from the list.")
                    .font(FoundryTheme.body(size: 12, weight: .regular))
                    .foregroundStyle(FoundryTheme.mutedText)
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
                    .font(.system(size: 11, weight: .bold))
                Text("New Snippet")
                    .font(FoundryTheme.body(size: 12.5, weight: .semibold))
            }
            .foregroundStyle(FoundryTheme.primaryText)
            .padding(.horizontal, 14)
            .frame(height: 32)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.white.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(PressableButtonStyle())
        .pointerCursor()
    }

    private func snippetSubtitle(_ snippet: StoredSnippet) -> String {
        let parts: [String?] = [
            snippet.keyword.isEmpty ? nil : snippet.keyword,
            snippet.tags.isEmpty ? nil : snippet.tags.map { "#\($0)" }.joined(separator: " "),
            relativeDate(snippet.updatedAt)
        ]
        return parts.compactMap { $0 }.joined(separator: "  •  ")
    }
}

private struct SnippetPanelSurface: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Color.white.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.07), lineWidth: 1)
            )
    }
}

private struct SnippetIconButton: View {
    let symbol: String
    var help: String = ""
    var tint: Color = FoundryTheme.secondaryText
    var destructive = false
    let action: () -> Void

    @State private var isHovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var foreground: Color {
        if isHovering {
            return destructive ? Color(red: 1.0, green: 0.45, blue: 0.45) : FoundryTheme.primaryText
        }
        return tint
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(foreground)
                .frame(width: 30, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.white.opacity(isHovering ? 0.09 : 0))
                )
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isHovering)
        .onHover { hovering in
            isHovering = hovering
            if hovering { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
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
                        .font(FoundryTheme.body(size: 14, weight: .medium))
                        .foregroundStyle(FoundryTheme.primaryText)
                        .lineLimit(1)
                    if snippet.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(FoundryTheme.mutedText)
                    }
                }
                if subtitle.isEmpty == false {
                    Text(subtitle)
                        .font(FoundryTheme.body(size: 11.5, weight: .regular))
                        .foregroundStyle(FoundryTheme.mutedText)
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
            if hovering { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
        }
    }
}

private struct SnippetEditor: View {
    @ObservedObject var state: SnippetState
    @State private var title = ""
    @State private var keyword = ""
    @State private var tags = ""
    @State private var content = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Snippet title", text: $title)
                .textFieldStyle(.plain)
                .font(FoundryTheme.body(size: 16, weight: .semibold))
                .foregroundStyle(FoundryTheme.primaryText)
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
                        .font(FoundryTheme.body(size: 13.5, weight: .regular))
                        .foregroundStyle(FoundryTheme.faintText)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $content)
                    .font(FoundryTheme.body(size: 13.5, weight: .regular))
                    .foregroundStyle(FoundryTheme.primaryText)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(fieldBackground)

            HStack(spacing: 6) {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 10, weight: .semibold))
                Text("{clipboard}  {date}  {time}  {cursor}  auto-expand when used")
                    .font(FoundryTheme.body(size: 11, weight: .regular))
            }
            .foregroundStyle(FoundryTheme.faintText)
            .padding(.leading, 2)
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
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(FoundryTheme.faintText)
            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .font(FoundryTheme.body(size: 13, weight: .medium))
                .foregroundStyle(FoundryTheme.primaryText)
        }
        .padding(.horizontal, 12)
        .frame(height: 36)
        .frame(maxWidth: .infinity)
        .background(fieldBackground)
    }

    private var fieldBackground: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Color.white.opacity(0.06))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.07), lineWidth: 1)
            )
    }

    private func sync() {
        title = state.selectedItem?.title ?? ""
        keyword = state.selectedItem?.keyword ?? ""
        tags = state.selectedItem?.tags.joined(separator: ", ") ?? ""
        content = state.selectedItem?.content ?? ""
    }

    private func persist() {
        state.updateSelected(title: title, content: content, keyword: keyword, tags: tags.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) })
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
