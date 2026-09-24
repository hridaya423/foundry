import AppKit
import Foundation
import SwiftUI

struct QuickAIHeaderControlsView: View {
    @Bindable var quickAI: QuickAIState
    @FocusState.Binding var inputFocused: Bool
    let onNewChat: () -> Void
    @State private var isShowingThreads = false

    var body: some View {
        HStack(spacing: 8) {
            QuickAIComposer(
                text: $quickAI.quickAIQuery,
                placeholder: quickAI.activeThread?.messages.isEmpty == false ? "Ask follow-up…" : "Ask anything…",
                onSubmit: { Task { await quickAI.submit() } }
            )
            .focused($inputFocused)
            .frame(height: 42)

            if quickAI.isQuickAILoading {
                FoundryIconButton(systemName: "stop.circle.fill", accessibilityLabel: "Stop answering", tint: FoundryTheme.secondaryText) {
                    quickAI.stop()
                }
                .help("Stop (⌘.)")
            }

            Button { isShowingThreads = true } label: {
                 Image(systemName: "text.bubble")
                     .font(.system(size: 15, weight: .medium))
                     .foregroundStyle(FoundryTheme.secondaryText)
                     .frame(width: 30, height: 30)
             }
             .buttonStyle(.plain)
             .pointerCursor()
             .help("Chats")
             .accessibilityLabel("Chats")
             .popover(isPresented: $isShowingThreads, arrowEdge: .bottom) {
                 QuickAIThreadPicker(quickAI: quickAI, onNewChat: {
                     isShowingThreads = false
                     onNewChat()
                 }, isPresented: $isShowingThreads)
             }
        }
    }
}

struct QuickAISurfaceView: View {
    @Bindable var quickAI: QuickAIState
    var onOpenAISettings: (() -> Void)?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                if let active = quickAI.activeThread, active.messages.isEmpty, quickAI.isQuickAILoading == false {
                    QuickAIEmptyState { prompt in
                        quickAI.quickAIQuery = prompt
                        Task { await quickAI.submit() }
                    }
                } else if let active = quickAI.activeThread {
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
                    HStack(spacing: 10) {
                        FoundryActionButton(title: "Retry", systemName: "arrow.clockwise") {
                            quickAI.retry()
                        }
                        if let onOpenAISettings {
                            FoundryActionButton(title: "AI Settings", systemName: "gear") {
                                onOpenAISettings()
                            }
                        }
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
            let event = message.toolEvent ?? .init(name: message.content, result: "")
            QuickAIToolEventRow(name: event.name, isRunning: event.isRunning, result: event.result)
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

                if message.role == .assistant {
                    CopyMessageButton(content: message.content)
                }
            }
        }
    }
}

private struct QuickAIEmptyState: View {
    let ask: (String) -> Void

    private static let suggestions = [
        "Summarize what's on my clipboard",
        "Explain a shell command",
        "Draft a short, friendly reply"
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Ask anything")
                .font(FoundryTheme.body(size: 17, weight: .semibold))
                .foregroundStyle(FoundryTheme.primaryText)
            Text("Answers stream here. Press ⌘N for a new chat, ⌘. to stop.")
                .font(FoundryTheme.body(size: 12, weight: .regular))
                .foregroundStyle(FoundryTheme.mutedText)
            ForEach(Self.suggestions, id: \.self) { suggestion in
                Button { ask(suggestion) } label: {
                    Label(suggestion, systemImage: "sparkles")
                        .font(FoundryTheme.body(size: 13, weight: .medium))
                        .foregroundStyle(FoundryTheme.secondaryText)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(PressableButtonStyle())
                .pointerCursor()
            }
        }
        .padding(.top, 8)
    }
}

private struct CopyMessageButton: View {
    let content: String
    @State private var copied = false

    var body: some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(content, forType: .string)
            copied = true
            Task { try? await Task.sleep(for: .seconds(1.2)); copied = false }
        } label: {
            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(FoundryTheme.faintText)
                .frame(width: 22, height: 22)
        }
        .buttonStyle(.plain)
        .pointerCursor()
        .accessibilityLabel(copied ? "Copied" : "Copy answer")
        .help("Copy answer")
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

struct AIFormattedText: View {
    let content: String

    final class ParsedBox: NSObject {
        let value: AttributedString
        init(_ value: AttributedString) { self.value = value }
    }

    static let parsedCache: NSCache<NSString, ParsedBox> = {
        let cache = NSCache<NSString, ParsedBox>()
        cache.countLimit = 200
        return cache
    }()

    static func releaseCachedMarkdown() {
        parsedCache.removeAllObjects()
    }

    var body: some View {
        if let attributed = Self.attributed(content) {
            Text(attributed)
        } else {
            Text(content)
        }
    }

    private static func attributed(_ content: String) -> AttributedString? {
        let key = content as NSString
        if let cached = parsedCache.object(forKey: key) { return cached.value }
        guard let parsed = try? AttributedString(
            markdown: content,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) else { return nil }
        parsedCache.setObject(ParsedBox(parsed), forKey: key)
        return parsed
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
        textViewContent.textColor = .labelColor
        textViewContent.insertionPointColor = .controlAccentColor
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
            .foregroundColor: NSColor.labelColor.withAlphaComponent(0.34)
        ]
        placeholder.draw(in: NSRect(x: 4, y: 10, width: bounds.width - 8, height: 24), withAttributes: attrs)
    }
}

private struct QuickAIThreadPicker: View {
    @Bindable var quickAI: QuickAIState
    let onNewChat: () -> Void
    @Binding var isPresented: Bool
    @State private var filter = ""

    private var threads: [AIChatThread] {
        let needle = filter.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard needle.isEmpty == false else { return quickAI.quickAIThreads }
        return quickAI.quickAIThreads.filter { $0.title.lowercased().contains(needle) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Search chats…", text: $filter)
                .textFieldStyle(.roundedBorder)
            Button("New Chat") { onNewChat() }
                .keyboardShortcut("n")
            Divider()
            if threads.isEmpty {
                Text(quickAI.quickAIThreads.isEmpty ? "No chats yet" : "No matching chats")
                    .font(FoundryTheme.body(size: 12, weight: .regular))
                    .foregroundStyle(FoundryTheme.faintText)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 10)
            } else {
                List(threads) { thread in
                    Button(thread.title) {
                        quickAI.selectThread(thread)
                        isPresented = false
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.plain)
                .scrollIndicators(.never)
            }
        }
        .padding(10)
        .frame(width: 260, height: 300)
    }
}
