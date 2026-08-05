import AppKit
import Foundation
import SwiftUI

struct QuickAIHeaderControlsView: View {
    @ObservedObject var quickAI: QuickAIState
    @FocusState.Binding var inputFocused: Bool
    let onNewChat: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            QuickAIComposer(
                text: $quickAI.quickAIQuery,
                placeholder: "Ask follow-up...",
                onSubmit: { Task { await quickAI.submit() } }
            )
            .focused($inputFocused)
            .frame(height: 42)

            Menu {
                Button("New Chat") { onNewChat() }
                if quickAI.quickAIThreads.isEmpty == false {
                    Divider()
                    ForEach(quickAI.quickAIThreads) { thread in
                        Button(thread.title) { quickAI.selectThread(thread) }
                    }
                }
             } label: {
                 Image(systemName: "text.bubble")
                     .font(.system(size: 15, weight: .medium))
                     .foregroundStyle(FoundryTheme.secondaryText)
                     .frame(width: 30, height: 30)
             }
             .menuStyle(.borderlessButton)
             .pointerCursor()
        }
    }
}

struct QuickAISurfaceView: View {
    @ObservedObject var quickAI: QuickAIState

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                if let active = quickAI.quickAIThreads.first(where: { $0.id == quickAI.activeQuickAIThreadID }) {
                    ForEach(active.messages) { message in
                        quickAIMessageRow(message)
                    }
                }

                if quickAI.isQuickAILoading,
                   quickAI.quickAIStatus.hasPrefix("Using ") == false,
                   quickAI.quickAIStatus.hasPrefix("Finished ") == false {
                    QuickAIActivityRow(status: quickAI.quickAIStatus)
                }

                if quickAI.quickAIResponse.isEmpty == false,
                   quickAI.isQuickAILoading || quickAI.quickAIThreads.first(where: { $0.id == quickAI.activeQuickAIThreadID })?.messages.last?.content != quickAI.quickAIResponse {
                    AIFormattedText(content: quickAI.quickAIResponse)
                        .font(FoundryTheme.body(size: 15, weight: .regular))
                        .foregroundStyle(FoundryTheme.primaryText)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if quickAI.quickAILastFailedPrompt != nil, quickAI.isQuickAILoading == false {
                    FoundryActionButton(title: "Retry", systemName: "arrow.clockwise") {
                        quickAI.retry()
                    }
                        .padding(.top, 2)
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
        }
    }

    @ViewBuilder
    private func quickAIMessageRow(_ message: AIChatMessage) -> some View {
        if message.role == .tool {
            let isRunning = message.content.hasPrefix("running:")
            let isComplete = message.content.hasPrefix("complete:")
            let markerLength = isRunning ? 8 : isComplete ? 9 : 0
            let payload = String(message.content.dropFirst(markerLength))
            let parts = payload.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
            let name = parts.first.map(String.init) ?? payload
            let result = parts.dropFirst().first.map(String.init)
            QuickAIToolEventRow(name: name, isRunning: isRunning, result: result)
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Image(systemName: message.role == .user ? "person.crop.circle" : "sparkles")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(FoundryTheme.faintText)
                    .frame(width: 20)

                AIFormattedText(content: message.content)
                    .font(FoundryTheme.body(size: 15, weight: .regular))
                    .foregroundStyle(message.role == .user ? FoundryTheme.secondaryText : FoundryTheme.primaryText)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

private struct QuickAIActivityRow: View {
    let status: String

    var body: some View {
        let presentation = QuickAIToolPresentation.activity(for: status)
        HStack(spacing: 10) {
            Image(systemName: presentation.icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(FoundryTheme.faintText)
                .frame(width: 20)

            QuickAIShimmerLabel(text: presentation.label)
        }
    }
}

private struct QuickAIToolEventRow: View {
    let name: String
    let isRunning: Bool
    let result: String?

    var body: some View {
        let presentation = QuickAIToolPresentation.tool(named: name, running: isRunning)
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: presentation.icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(FoundryTheme.faintText)
                    .frame(width: 20)

                if isRunning {
                    QuickAIShimmerLabel(text: presentation.label)
                } else {
                    Text(presentation.label)
                        .font(FoundryTheme.body(size: 14, weight: .medium))
                        .foregroundStyle(FoundryTheme.secondaryText)
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(FoundryTheme.faintText)
                }
            }

            if let result, result.isEmpty == false {
                Text(result)
                    .font(FoundryTheme.body(size: 11, weight: .regular))
                    .foregroundStyle(FoundryTheme.mutedText)
                    .lineLimit(4)
                    .padding(.leading, 30)
            }
        }
    }
}

private struct QuickAIShimmerLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(FoundryTheme.body(size: 14, weight: .medium))
            .foregroundStyle(FoundryTheme.secondaryText)
    }
}

private enum QuickAIToolPresentation {
    static func activity(for status: String) -> (icon: String, label: String) {
        tool(named: status.lowercased(), running: true)
    }

    static func tool(named name: String, running: Bool) -> (icon: String, label: String) {
        let normalized = name.replacingOccurrences(of: "_", with: " ").lowercased()
        if normalized.hasPrefix("web search:") {
            let query = name.split(separator: ":", maxSplits: 1).last.map(String.init)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "the web"
            let summary = String(query.prefix(72))
            let isSource = query.lowercased().hasPrefix("http://") || query.lowercased().hasPrefix("https://")
            if isSource { return ("link", running ? "Checking source" : "Source: \(summary)") }
            return ("link", running ? "Searching: \(summary)" : "Searched: \(summary)")
        }
        if normalized.contains("web search") { return ("link", running ? "Searching the web" : "Web search") }
        if normalized.contains("system context") { return ("clock", running ? "Checking system context" : "System context") }
        if normalized.contains("clipboard") { return ("doc.on.clipboard", running ? "Reading clipboard" : "Clipboard") }
        if normalized.contains("open url") { return ("safari", running ? "Opening website" : "Opened website") }
        if normalized.contains("open app") { return ("app", running ? "Opening application" : "Opened application") }
        if normalized.contains("copy text") { return ("doc.on.doc", running ? "Copying text" : "Copied text") }
        if normalized.contains("synthesizing") { return ("sparkles", "Synthesizing answer") }
        return ("sparkles", running ? "Thinking" : normalized.capitalized)
    }
}

private struct AIFormattedText: View {
    let content: String

    var body: some View {
        if let attributed = try? AttributedString(
            markdown: content,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            Text(attributed)
        } else {
            Text(content)
        }
    }
}

private struct QuickAIComposer: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let onSubmit: () -> Void

    func makeNSView(context: Context) -> QuickAITextView {
        let view = QuickAITextView()
        view.placeholder = placeholder
        view.onSubmit = onSubmit
        view.delegate = context.coordinator
        DispatchQueue.main.async {
            view.window?.makeFirstResponder(view.textView)
        }
        return view
    }

    func updateNSView(_ nsView: QuickAITextView, context: Context) {
        if nsView.textView.string != text { nsView.textView.string = text }
        nsView.placeholder = placeholder
        nsView.onSubmit = onSubmit
        nsView.delegate = context.coordinator
    }

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        init(text: Binding<String>) { self.text = text }
        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? NSTextView else { return }
            text.wrappedValue = view.string
        }
    }
}

private final class QuickAITextView: NSScrollView {
    fileprivate var placeholder: String = "" { didSet { textView.needsDisplay = true } }
    fileprivate var onSubmit: (() -> Void)?
    fileprivate var textView: QuickAITextViewContent { textViewContent }
    fileprivate var delegate: NSTextViewDelegate? {
        get { textViewContent.delegate }
        set { textViewContent.delegate = newValue }
    }

    private let textViewContent = QuickAITextViewContent()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        drawsBackground = false
        borderType = .noBorder
        hasVerticalScroller = true
        verticalScroller?.controlSize = .small
        scrollerStyle = .overlay
        documentView = textViewContent
        textViewContent.isEditable = true
        textViewContent.isSelectable = true
        textViewContent.isRichText = false
        textViewContent.importsGraphics = false
        textViewContent.drawsBackground = false
        textViewContent.isVerticallyResizable = true
        textViewContent.isHorizontallyResizable = false
        textViewContent.textContainerInset = NSSize(width: 2, height: 8)
        textViewContent.textContainer?.widthTracksTextView = true
        textViewContent.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textViewContent.placeholderRef = { [weak self] in self?.placeholder ?? "" }
        textViewContent.submitAction = { [weak self] in self?.onSubmit?() }
        textViewContent.font = NSFont.systemFont(ofSize: 21, weight: .regular)
        textViewContent.textColor = .white
        textViewContent.insertionPointColor = .white
        textViewContent.isAutomaticTextCompletionEnabled = false
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

private final class QuickAITextViewContent: NSTextView {
    var placeholderRef: (() -> String)?
    var submitAction: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 48:
            interpretKeyEvents([event])
        case 36:
            if event.modifierFlags.contains(.shift) {
                super.keyDown(with: event)
            } else {
                submitAction?()
            }
        default:
            super.keyDown(with: event)
        }
    }

    override func insertTab(_ sender: Any?) {
        insertText("\t", replacementRange: selectedRange())
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty, let placeholder = placeholderRef?(), placeholder.isEmpty == false else { return }
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font ?? NSFont.systemFont(ofSize: 21),
            .foregroundColor: NSColor.white.withAlphaComponent(0.34)
        ]
        placeholder.draw(in: NSRect(x: 4, y: 10, width: bounds.width - 8, height: 24), withAttributes: attrs)
    }
}
