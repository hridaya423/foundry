import Foundation
import SwiftUI

@MainActor
final class QuickAIState: ObservableObject {
    @Published var quickAIQuery = ""
    @Published var quickAIResponse = ""
    @Published var quickAIStatus = ""
    @Published var isQuickAILoading = false
    @Published var quickAILastFailedPrompt: String?
    @Published var quickAIThreads: [AIChatThread]
    @Published var activeQuickAIThreadID: UUID?

    private let aiProvider: AIProvider
    private let aiChatStore: any AIChatStoring
    private let persistenceWriter: AIChatPersistenceWriter
    private var quickAITask: Task<Void, Never>?
    private var chatPersistenceTask: Task<Void, Never>?
    private var initialLoadTask: Task<AIChatLoadResult, Never>?
    private var initialLoadFinished = false
    private var initialLoadFailed = false
    private var quickAIRequestID: UUID?

    init(aiProvider: AIProvider, chatStore: any AIChatStoring = AIChatStore()) {
        self.aiProvider = aiProvider
        self.aiChatStore = chatStore
        self.persistenceWriter = AIChatPersistenceWriter(store: chatStore)
        self.quickAIThreads = []
        self.activeQuickAIThreadID = nil

        let loadTask = Task { await chatStore.loadResultAsync() }
        initialLoadTask = loadTask
        Task { [weak self] in
            await self?.finishInitialLoad()
        }
    }

    func resetTransientState() {
        quickAIQuery = ""
        quickAIResponse = ""
        quickAIStatus = ""
        isQuickAILoading = false
        quickAILastFailedPrompt = nil
        quickAITask?.cancel()
        quickAITask = nil
        quickAIRequestID = nil
    }

    func startNewThread(initialPrompt: String = "", selectedAIProfileID: UUID?) {
        resetTransientState()
        let prompt = AIProvider.request(from: initialPrompt)?.prompt ?? initialPrompt
        quickAIQuery = prompt
        quickAIResponse = ""
        quickAIStatus = prompt.isEmpty ? "Ask anything" : "Ready"
        isQuickAILoading = false
        quickAILastFailedPrompt = nil
        let thread = AIChatThread(title: prompt.isEmpty ? "New Chat" : prompt, providerProfileID: selectedAIProfileID)
        quickAIThreads.insert(thread, at: 0)
        activeQuickAIThreadID = thread.id
        persistAIThreads()
        if prompt.isEmpty == false {
            Task { await submit() }
        }
    }

    func submit() async {
        let prompt = quickAIQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard prompt.isEmpty == false else {
            quickAIStatus = "Type a question first"
            return
        }
        quickAIQuery = ""
        quickAITask?.cancel()
        quickAIRequestID = nil
        guard let threadID = activeQuickAIThreadID else {
            quickAIStatus = "Start a chat first"
            return
        }
        let requestID = UUID()
        quickAIRequestID = requestID
        quickAITask = Task { [weak self] in
            await self?.performQuickAI(prompt: prompt, threadID: threadID, requestID: requestID)
        }
        await quickAITask?.value
    }

    func retry() {
        guard let prompt = quickAILastFailedPrompt, isQuickAILoading == false else { return }
        quickAILastFailedPrompt = nil
        quickAITask?.cancel()
        guard let threadID = activeQuickAIThreadID else { return }
        let requestID = UUID()
        quickAIRequestID = requestID
        quickAITask = Task { [weak self] in
            await self?.performQuickAI(prompt: prompt, persistUserMessage: false, threadID: threadID, requestID: requestID)
        }
    }

    func selectThread(_ thread: AIChatThread) {
        quickAITask?.cancel()
        quickAITask = nil
        quickAIRequestID = nil
        activeQuickAIThreadID = thread.id
        quickAIQuery = ""
        quickAIResponse = thread.messages.last(where: { $0.role == .assistant })?.content ?? ""
        quickAIStatus = thread.messages.isEmpty ? "Ask anything" : "Loaded"
        quickAILastFailedPrompt = nil
    }

    func shutdown() {
        quickAITask?.cancel()
        quickAITask = nil
        quickAIRequestID = nil
        chatPersistenceTask?.cancel()
        chatPersistenceTask = nil
        if initialLoadFinished == false {
            applyInitialLoad(aiChatStore.loadResult())
        }
        guard initialLoadFailed == false else { return }
        persistenceWriter.schedule(quickAIThreads)
        persistenceWriter.flush()
    }

    private func persistAIThreads() {
        chatPersistenceTask?.cancel()
        let writer = persistenceWriter
        chatPersistenceTask = Task { [weak self, writer] in
            do {
                try await Task.sleep(for: .milliseconds(150))
            } catch {
                return
            }
            guard let self else { return }
            await self.finishInitialLoad()
            guard Task.isCancelled == false, self.initialLoadFailed == false else { return }
            writer.schedule(self.quickAIThreads)
        }
    }

    private func finishInitialLoad() async {
        guard initialLoadFinished == false, let initialLoadTask else { return }
        let loaded = await initialLoadTask.value
        guard initialLoadFinished == false else { return }
        applyInitialLoad(loaded)
    }

    private func applyInitialLoad(_ result: AIChatLoadResult) {
        if case let .loaded(loaded) = result {
            mergeInitialThreads(loaded)
        } else {
            initialLoadFailed = true
        }
        initialLoadFinished = true
        self.initialLoadTask = nil
    }

    private func mergeInitialThreads(_ loaded: [AIChatThread]) {
        let currentIDs = Set(quickAIThreads.map(\.id))
        quickAIThreads += loaded.filter { currentIDs.contains($0.id) == false }
        quickAIThreads.sort { $0.updatedAt > $1.updatedAt }
        if activeQuickAIThreadID == nil {
            activeQuickAIThreadID = quickAIThreads.first?.id
        }
    }

    private func performQuickAI(prompt: String, persistUserMessage: Bool = true, threadID: UUID, requestID: UUID) async {
        guard isCurrentQuickAIRequest(requestID, threadID: threadID) else { return }
        isQuickAILoading = true
        quickAIStatus = "Thinking"
        quickAIResponse = ""
        var didFail = false
        var response = ""
        let clock = ContinuousClock()
        var lastResponsePublication = clock.now
        let priorMessages = quickAIThreads.first(where: { $0.id == threadID })
            .map { Array($0.messages.filter { $0.role == .user || $0.role == .assistant }.suffix(10)) } ?? []
        let conversationContext = AIConversationContext.build(from: priorMessages)
        let profileID = quickAIThreads.first(where: { $0.id == threadID })?.providerProfileID
        if persistUserMessage, let index = quickAIThreads.firstIndex(where: { $0.id == threadID }) {
            quickAIThreads[index].messages.append(AIChatMessage(role: .user, content: prompt))
            quickAIThreads[index].updatedAt = .now
            if quickAIThreads[index].title == "New Chat" {
                quickAIThreads[index].title = prompt.prefix(48).description
            }
            persistAIThreads()
        }

        for await event in aiProvider.stream(prompt: prompt, context: conversationContext, profileID: profileID, sessionID: threadID.uuidString) {
            guard Task.isCancelled == false else {
                guard isCurrentQuickAIRequest(requestID, threadID: threadID) else { return }
                isQuickAILoading = false
                quickAIStatus = "Cancelled"
                quickAILastFailedPrompt = prompt
                return
            }
            guard isCurrentQuickAIRequest(requestID, threadID: threadID) else { return }
            switch event {
            case let .status(status):
                quickAIStatus = status
            case let .textDelta(delta):
                response += delta
                let now = clock.now
                if lastResponsePublication.duration(to: now) >= .milliseconds(33) {
                    quickAIResponse = response
                    lastResponsePublication = now
                }
            case let .toolCallStarted(name):
                quickAIStatus = "Using \(name.replacingOccurrences(of: "_", with: " "))"
                recordToolStarted(name, threadID: threadID)
            case let .toolResult(name, result):
                quickAIStatus = "Finished \(name.replacingOccurrences(of: "_", with: " "))"
                recordToolFinished(name, result: result, threadID: threadID)
            case .completed:
                quickAIStatus = "Done"
            case let .failed(message):
                didFail = true
                quickAILastFailedPrompt = prompt
                quickAIStatus = message
                response = message
                quickAIResponse = message
            }
        }

        guard Task.isCancelled == false else {
            guard isCurrentQuickAIRequest(requestID, threadID: threadID) else { return }
            isQuickAILoading = false
            quickAIStatus = "Cancelled"
            quickAILastFailedPrompt = prompt
            return
        }
        guard isCurrentQuickAIRequest(requestID, threadID: threadID) else { return }
        quickAIResponse = response
        quickAIStatus = didFail ? "Failed" : response.isEmpty ? "No response" : "Done"
        isQuickAILoading = false
        if let index = quickAIThreads.firstIndex(where: { $0.id == threadID }) {
            if response.isEmpty == false, didFail == false {
                quickAIThreads[index].messages.append(AIChatMessage(role: .assistant, content: response))
            }
            quickAIThreads[index].updatedAt = .now
            persistAIThreads()
        }
    }

    private func recordToolStarted(_ name: String, threadID: UUID) {
        guard let index = quickAIThreads.firstIndex(where: { $0.id == threadID }) else { return }
        quickAIThreads[index].messages.append(AIChatMessage(role: .tool, content: "running:\(name)"))
        quickAIThreads[index].updatedAt = .now
        persistAIThreads()
    }

    private func recordToolFinished(_ name: String, result: String, threadID: UUID) {
        guard let threadIndex = quickAIThreads.firstIndex(where: { $0.id == threadID }),
              let messageIndex = quickAIThreads[threadIndex].messages.lastIndex(where: { $0.role == .tool && $0.content == "running:\(name)" }) else { return }
        quickAIThreads[threadIndex].messages[messageIndex].content = "complete:\(name)\n\(String(result.prefix(1800)))"
        quickAIThreads[threadIndex].updatedAt = .now
        persistAIThreads()
    }

    private func isCurrentQuickAIRequest(_ requestID: UUID, threadID: UUID) -> Bool {
        requestID == quickAIRequestID && threadID == activeQuickAIThreadID
    }
}
