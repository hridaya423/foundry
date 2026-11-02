import AppKit
import SwiftUI
import UniformTypeIdentifiers
import FoundryDomain

extension CommandPanelView {

    var dropChooserSurface: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("Dropped \(state.pendingDropURLs?.count ?? 0) file\((state.pendingDropURLs?.count ?? 0) == 1 ? "" : "s")")
                    .font(FoundryTheme.micro)
                    .foregroundStyle(FoundryTheme.textQuaternary)
                Spacer()
                Text("esc")
                    .font(FoundryTheme.micro)
                    .foregroundStyle(FoundryTheme.textQuaternary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(FoundryTheme.fillTint)
                    .clipShape(RoundedRectangle(cornerRadius: FoundryTheme.Radius.badge, style: .continuous))
            }
            .padding(.horizontal, 20)
            .frame(height: FoundryTheme.Control.row)

            VStack(spacing: 2) {
                ForEach(Array(state.dropChoices.enumerated()), id: \.offset) { index, choice in
                    Button {
                        state.resolveDrop(choice)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: choice.systemIcon)
                                .font(FoundryTheme.Glyph.sm)
                                .foregroundStyle(FoundryTheme.textSecondary)
                                .frame(width: 20)
                            Text(choice.title)
                                .font(FoundryTheme.body)
                                .foregroundStyle(FoundryTheme.textPrimary)
                            Spacer()
                            KeycapHint(text: index == state.dropSelection ? "↵" : "⌘\(index + 1)")
                        }
                        .padding(.horizontal, FoundryTheme.Spacing.sm)
                        .frame(height: FoundryTheme.Control.field)
                        .background(RowBackground(isSelected: index == state.dropSelection, isHovering: false, cornerRadius: FoundryTheme.Radius.control))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(KeyboardShortcut(.init(Character(UnicodeScalar(48 + index + 1)!)), modifiers: .command))
                    .accessibilityAddTraits(index == state.dropSelection ? .isSelected : [])
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 10)
        }
    }

    var actionsSurface: some View {
        VStack(spacing: 0) {
            if let title = state.session.featureActionsTitle ?? state.session.selectedResult?.title {
                Text(title)
                    .font(FoundryTheme.bodySecondary)
                    .foregroundStyle(FoundryTheme.textSecondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 4)
            }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 2) {
                        if state.session.visibleActions.isEmpty {
                            Text("No actions match \u{201C}\(state.session.actionFilter)\u{201D}")
                                .font(FoundryTheme.bodySecondary)
                                .foregroundStyle(FoundryTheme.textTertiary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 24)
                        }
                        ForEach(state.session.visibleActions, id: \.id) { action in
                            if action.id == firstDestructiveActionID {
                                Divider().padding(.vertical, 4).padding(.horizontal, 8)
                            }
                            ActionRow(
                                action: action,
                                shortcut: action.id == state.session.selectedActions.first?.id ? "↵" : state.session.actionShortcuts[action.id]?.display,
                                isSelected: state.session.selectedActionID == action.id
                            )
                            .id(action.id)
                            .rowActivation(isSelected: state.session.selectedActionID == action.id) {
                                state.session.select(actionID: action.id)
                                executeSelectedResult()
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 8)
                }
                .scrollIndicators(.never)
                .background(Color.clear)
                .onChange(of: state.session.selectedActionID) { _, actionID in
                    guard let actionID else { return }
                    proxy.scrollTo(actionID)
                }
            }
        }
    }

    private var firstDestructiveActionID: String? {
        let actions = state.session.visibleActions
        guard actions.contains(where: { $0.isDestructive == false }) else { return nil }
        return actions.first(where: \.isDestructive)?.id
    }

    var trimmedQuery: String {
        state.session.query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var emojiQueryBinding: Binding<String> {
        Binding(
            get: { state.emojiPicker.query },
            set: { state.emojiPicker.query = $0 }
        )
    }

    var clipboardQueryBinding: Binding<String> {
        Binding(
            get: { state.clipboardHistory.query },
            set: { state.clipboardHistory.query = $0 }
        )
    }

    var snippetsQueryBinding: Binding<String> {
        Binding(
            get: { state.snippets.query },
            set: { state.snippets.query = $0 }
        )
    }

    func handleFileDrop(_ providers: [NSItemProvider]) -> Bool {
        let fileProviders = providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }
        guard fileProviders.isEmpty == false else { return false }

        Task { @MainActor in
            var urls: [URL] = []
            for provider in fileProviders {
                if let url = await loadFileURL(from: provider) {
                    urls.append(url)
                }
            }
            state.handleDroppedFiles(urls)
        }
        return true
    }

    func loadFileURL(from provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                if let data = item as? Data {
                    continuation.resume(returning: URL(dataRepresentation: data, relativeTo: nil))
                } else {
                    continuation.resume(returning: item as? URL)
                }
            }
        }
    }

}
