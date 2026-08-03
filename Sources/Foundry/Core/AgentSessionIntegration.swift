import Foundation

struct AgentSessionKey: Codable, Equatable, Hashable, Sendable {
    let provider: AgentProviderKind
    let rawSessionID: String
}

enum AgentSessionOrigin: String, Codable, Hashable, Sendable {
    case managed
    case hook
    case plugin
    case catalog
    case transcript
    case processFallback

    var priority: Int {
        switch self {
        case .managed: 6
        case .hook, .plugin: 5
        case .catalog: 4
        case .transcript: 3
        case .processFallback: 1
        }
    }
}

struct AgentSessionCapabilities: OptionSet, Codable, Equatable, Hashable, Sendable {
    let rawValue: Int

    static let observe = Self(rawValue: 1 << 0)
    static let liveText = Self(rawValue: 1 << 1)
    static let approve = Self(rawValue: 1 << 2)
    static let questions = Self(rawValue: 1 << 3)
    static let reply = Self(rawValue: 1 << 4)
    static let stop = Self(rawValue: 1 << 5)
    static let jumpApplication = Self(rawValue: 1 << 6)
    static let jumpTerminal = Self(rawValue: 1 << 7)
    static let jumpTask = Self(rawValue: 1 << 8)

    init(rawValue: Int) {
        self.rawValue = rawValue
    }

    init(from decoder: Decoder) throws {
        self.init(rawValue: try decoder.singleValueContainer().decode(Int.self))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

enum AgentAttentionReason: String, Codable, Hashable, Sendable {
    case permission
    case question
    case review
    case failure
    case disconnected
}

struct AgentTerminalLocator: Codable, Equatable, Hashable, Sendable {
    let tty: String?
    let processID: Int32?
    let applicationBundleID: String?
    let terminalName: String?
    let remoteHost: String?
}

struct AgentSessionMetadata: Codable, Equatable, Sendable {
    let title: String?
    let workingDirectory: String?
    let project: String?
    let model: String?
    let terminalCommand: String?
    let terminalLocator: AgentTerminalLocator?

    init(
        title: String? = nil,
        workingDirectory: String? = nil,
        project: String? = nil,
        model: String? = nil,
        terminalCommand: String? = nil,
        terminalLocator: AgentTerminalLocator? = nil
    ) {
        self.title = title
        self.workingDirectory = workingDirectory
        self.project = project
        self.model = model
        self.terminalCommand = terminalCommand
        self.terminalLocator = terminalLocator
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        workingDirectory = try container.decodeIfPresent(String.self, forKey: .workingDirectory)
        project = try container.decodeIfPresent(String.self, forKey: .project)
        model = try container.decodeIfPresent(String.self, forKey: .model)
        terminalCommand = try container.decodeIfPresent(String.self, forKey: .terminalCommand)
        terminalLocator = try container.decodeIfPresent(AgentTerminalLocator.self, forKey: .terminalLocator)
    }
}

enum AgentEvent: Codable, Equatable, Sendable {
    case sessionStart(metadata: AgentSessionMetadata?)
    case sessionEnd
    case status(AgentSessionStatus)
    case userPrompt(String)
    case assistantMessage(String)
    case toolActivity(name: String, detail: String?, running: Bool)
    case attention(reason: AgentAttentionReason, prompt: String?)
    case completion(success: Bool)
    case metadata(AgentSessionMetadata)
}

struct AgentEventEnvelope: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let requestID: String
    let provider: AgentProviderKind
    let sessionID: String
    let parentSessionID: String?
    let eventID: String?
    let timestamp: Date?
    let deadline: Date?
    let origin: AgentSessionOrigin
    let capabilities: AgentSessionCapabilities
    let metadata: AgentSessionMetadata?
    let event: AgentEvent

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case requestID
        case provider
        case sessionID
        case parentSessionID
        case eventID
        case timestamp
        case deadline
        case origin
        case capabilities
        case metadata
        case event
    }

    init(
        schemaVersion: Int = Self.currentSchemaVersion,
        requestID: String,
        provider: AgentProviderKind,
        sessionID: String,
        parentSessionID: String? = nil,
        eventID: String? = nil,
        timestamp: Date? = Date(),
        deadline: Date? = nil,
        origin: AgentSessionOrigin = .hook,
        capabilities: AgentSessionCapabilities = [.observe],
        metadata: AgentSessionMetadata? = nil,
        event: AgentEvent
    ) {
        self.schemaVersion = schemaVersion
        self.requestID = requestID
        self.provider = provider
        self.sessionID = sessionID
        self.parentSessionID = parentSessionID
        self.eventID = eventID
        self.timestamp = timestamp
        self.deadline = deadline
        self.origin = origin
        self.capabilities = capabilities
        self.metadata = metadata
        self.event = event
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? Self.currentSchemaVersion
        requestID = try container.decode(String.self, forKey: .requestID)
        provider = try container.decode(AgentProviderKind.self, forKey: .provider)
        sessionID = try container.decode(String.self, forKey: .sessionID)
        parentSessionID = try container.decodeIfPresent(String.self, forKey: .parentSessionID)
        eventID = try container.decodeIfPresent(String.self, forKey: .eventID)
        timestamp = try Self.decodeDate(container, forKey: .timestamp)
        deadline = try Self.decodeDate(container, forKey: .deadline)
        origin = try container.decodeIfPresent(AgentSessionOrigin.self, forKey: .origin) ?? .hook
        capabilities = try container.decodeIfPresent(AgentSessionCapabilities.self, forKey: .capabilities) ?? [.observe]
        metadata = try container.decodeIfPresent(AgentSessionMetadata.self, forKey: .metadata)
        event = try container.decode(AgentEvent.self, forKey: .event)
    }

    private static func decodeDate(_ container: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) throws -> Date? {
        guard container.contains(key) else { return nil }
        if let date = try? container.decode(Date.self, forKey: key) { return date }
        if let seconds = try? container.decode(Double.self, forKey: key) { return Date(timeIntervalSince1970: seconds) }
        if let string = try? container.decode(String.self, forKey: key),
           let date = ISO8601DateFormatter().date(from: string) {
            return date
        }
        throw DecodingError.dataCorruptedError(forKey: key, in: container, debugDescription: "Expected an ISO 8601 date or Unix timestamp")
    }

    func validated(now: Date = Date()) throws -> AgentEventEnvelope {
        guard schemaVersion == Self.currentSchemaVersion else { throw AgentEventValidationError.unsupportedSchema }
        guard requestID.count > 0, requestID.count <= 128 else { throw AgentEventValidationError.invalidRequestID }
        guard sessionID.count > 0, sessionID.count <= 256 else { throw AgentEventValidationError.invalidSessionID }
        if let parentSessionID, parentSessionID.count > 256 { throw AgentEventValidationError.invalidParentSessionID }
        if let eventID, eventID.count > 256 { throw AgentEventValidationError.invalidEventID }
        if let deadline {
            guard deadline >= now, deadline <= now.addingTimeInterval(300) else { throw AgentEventValidationError.invalidDeadline }
        }
        if let timestamp, timestamp > now.addingTimeInterval(300) { throw AgentEventValidationError.invalidTimestamp }
        switch event {
        case let .userPrompt(text), let .assistantMessage(text):
            guard text.count <= 32_768 else { throw AgentEventValidationError.payloadTooLarge }
        case let .toolActivity(name, detail, _):
            guard name.count <= 256, detail?.count ?? 0 <= 8_192 else { throw AgentEventValidationError.payloadTooLarge }
        case let .attention(_, prompt):
            guard prompt?.count ?? 0 <= 8_192 else { throw AgentEventValidationError.payloadTooLarge }
        default:
            break
        }
        return self
    }
}

enum AgentEventValidationError: LocalizedError, Equatable, Sendable {
    case unsupportedSchema
    case invalidRequestID
    case invalidSessionID
    case invalidParentSessionID
    case invalidEventID
    case invalidDeadline
    case invalidTimestamp
    case payloadTooLarge

    var errorDescription: String? {
        switch self {
        case .unsupportedSchema: "Unsupported agent event schema"
        case .invalidRequestID: "Invalid agent request ID"
        case .invalidSessionID: "Invalid agent session ID"
        case .invalidParentSessionID: "Invalid parent session ID"
        case .invalidEventID: "Invalid agent event ID"
        case .invalidDeadline: "Invalid agent event deadline"
        case .invalidTimestamp: "Invalid agent event timestamp"
        case .payloadTooLarge: "Agent event payload is too large"
        }
    }
}

struct AgentEventAck: Codable, Equatable, Sendable {
    let requestID: String?
    let accepted: Bool
    let error: String?

    static func accepted(requestID: String) -> AgentEventAck {
        AgentEventAck(requestID: requestID, accepted: true, error: nil)
    }

    static func rejected(requestID: String? = nil, error: String) -> AgentEventAck {
        AgentEventAck(requestID: requestID, accepted: false, error: error)
    }
}

struct AgentStoreUpdate: Sendable {
    let cards: [AgentSessionCard]
    let accepted: Bool
    let error: String?
}

actor AgentSessionStore {
    private var sessions: [AgentSessionKey: AgentSessionCard] = [:]
    private var observedKeys: Set<AgentSessionKey> = []
    private var recentEventIDs: Set<String> = []
    private var recentEventOrder: [String] = []
    private let replayLimit = 2_048

    func reconcileObserved(_ cards: [AgentSessionCard]) -> [AgentSessionCard] {
        let nextObservedKeys = Set(cards.map { key(for: $0) })
        for key in observedKeys.subtracting(nextObservedKeys) {
            if let origin = sessions[key]?.origin, origin == .catalog || origin == .processFallback {
                sessions.removeValue(forKey: key)
            }
        }

        for card in cards {
            let key = key(for: card)
            guard let existing = sessions[key] else {
                var observedCard = card
                observedCard.key = key
                sessions[key] = observedCard
                continue
            }
            guard existing.origin.priority <= card.origin.priority else { continue }
            var observedCard = card
            observedCard.key = key
            if existing.isGeneratedTitle, card.needsTitleGeneration {
                observedCard.title = existing.title
                observedCard.needsTitleGeneration = false
                observedCard.isGeneratedTitle = true
            }
            sessions[key] = observedCard
        }

        observedKeys = nextObservedKeys
        return sortedCards()
    }

    func apply(_ envelope: AgentEventEnvelope) -> AgentStoreUpdate {
        do {
            _ = try envelope.validated()
        } catch {
            return AgentStoreUpdate(cards: sortedCards(), accepted: false, error: error.localizedDescription)
        }

        let replayID = "\(envelope.provider.rawValue):\(envelope.sessionID):\(envelope.eventID ?? envelope.requestID)"
        guard recentEventIDs.insert(replayID).inserted else {
            return AgentStoreUpdate(cards: sortedCards(), accepted: false, error: "Duplicate agent event")
        }
        recentEventOrder.append(replayID)
        if recentEventOrder.count > replayLimit {
            let removed = recentEventOrder.removeFirst()
            recentEventIDs.remove(removed)
        }

        let key = AgentSessionKey(provider: envelope.provider, rawSessionID: envelope.sessionID)
        if let existing = sessions[key],
           let timestamp = envelope.timestamp,
           let updatedAt = existing.updatedAt,
           timestamp < updatedAt {
            return AgentStoreUpdate(cards: sortedCards(), accepted: false, error: "Out-of-order agent event")
        }

        var card = sessions[key] ?? makeCard(for: envelope, key: key)
        let sourceCanReplace = envelope.origin.priority >= card.origin.priority
        if sourceCanReplace {
            card.key = key
            card.origin = envelope.origin
            card.capabilities = envelope.capabilities
            if let parentSessionID = envelope.parentSessionID { card.parentSessionID = parentSessionID }
            if let terminalLocator = envelope.metadata?.terminalLocator { card.terminalLocator = terminalLocator }
        }
        if sourceCanReplace {
            card = apply(envelope.event, to: card, metadata: envelope.metadata, eventDate: envelope.timestamp ?? Date())
        } else {
            card = applyMetadata(envelope.metadata, to: card)
        }
        if case .sessionEnd = envelope.event {
            removeSessionTree(key)
            observedKeys.remove(key)
            return AgentStoreUpdate(cards: sortedCards(), accepted: true, error: nil)
        }
        sessions[key] = card
        observedKeys.remove(key)
        return AgentStoreUpdate(cards: sortedCards(), accepted: true, error: nil)
    }

    func snapshot() -> [AgentSessionCard] {
        sortedCards()
    }

    func updateTitle(_ title: String, for key: AgentSessionKey) {
        guard var card = sessions[key] else { return }
        card.title = title
        card.needsTitleGeneration = false
        card.isGeneratedTitle = true
        sessions[key] = card
    }

    private func key(for card: AgentSessionCard) -> AgentSessionKey {
        if let key = card.key { return key }
        let prefix = "\(card.provider.rawValue.lowercased())."
        let rawID = card.id.hasPrefix(prefix) ? String(card.id.dropFirst(prefix.count)) : card.id
        return AgentSessionKey(provider: card.provider, rawSessionID: rawID)
    }

    private func makeCard(for envelope: AgentEventEnvelope, key: AgentSessionKey) -> AgentSessionCard {
        let metadata = envelope.metadata
        let openTarget: AgentOpenTarget
        if let command = metadata?.terminalCommand {
            openTarget = .terminal(command: command, cwd: metadata?.workingDirectory)
        } else {
            openTarget = .application(name: envelope.provider.rawValue)
        }
        return AgentSessionCard(
            id: displayID(for: key),
            provider: envelope.provider,
            title: bounded(metadata?.title ?? "\(envelope.provider.rawValue) Session", limit: 160),
            subtitle: bounded(metadata?.model ?? metadata?.project ?? "", limit: 240),
            project: boundedOptional(metadata?.project, limit: 160),
            workingDirectory: boundedOptional(metadata?.workingDirectory, limit: 4_096),
            model: boundedOptional(metadata?.model, limit: 160),
            status: .running,
            startedAt: envelope.timestamp,
            updatedAt: envelope.timestamp,
            openTarget: openTarget,
            key: key,
            origin: envelope.origin,
            capabilities: envelope.capabilities,
            parentSessionID: envelope.parentSessionID,
            attentionReason: nil,
            terminalLocator: envelope.metadata?.terminalLocator
        )
    }

    private func apply(_ event: AgentEvent, to card: AgentSessionCard, metadata: AgentSessionMetadata?, eventDate: Date) -> AgentSessionCard {
        var next = card
        switch event {
        case let .sessionStart(eventMetadata):
            next = applyMetadata(eventMetadata ?? metadata, to: next)
            next.status = .running
            next.updatedAt = eventDate
        case .sessionEnd:
            next.updatedAt = eventDate
        case let .status(status):
            next.status = status
            next.updatedAt = eventDate
        case .userPrompt:
            next.status = .working
            next.updatedAt = eventDate
            next.attentionReason = nil
        case .assistantMessage:
            next.status = .reviewReady
            next.updatedAt = eventDate
        case .toolActivity:
            next.status = .working
            next.updatedAt = eventDate
            next.attentionReason = nil
        case let .attention(reason, _):
            next.status = .needsInput
            next.updatedAt = eventDate
            next.attentionReason = reason
        case let .completion(success):
            next.status = success ? .completed : .failed
            next.updatedAt = eventDate
            next.attentionReason = success ? nil : .failure
        case let .metadata(eventMetadata):
            next = applyMetadata(eventMetadata, to: next)
            next.updatedAt = eventDate
        }
        if case .sessionEnd = event { return next }
        return applyMetadata(metadata, to: next)
    }

    private func applyMetadata(_ metadata: AgentSessionMetadata?, to input: AgentSessionCard) -> AgentSessionCard {
        var card = input
        guard let metadata else { return card }
        card.title = bounded(metadata.title ?? card.title, limit: 160)
        card.subtitle = bounded(metadata.model ?? metadata.project ?? card.subtitle, limit: 240)
        card.project = boundedOptional(metadata.project ?? card.project, limit: 160)
        card.workingDirectory = boundedOptional(metadata.workingDirectory ?? card.workingDirectory, limit: 4_096)
        card.model = boundedOptional(metadata.model ?? card.model, limit: 160)
        if let terminalLocator = metadata.terminalLocator { card.terminalLocator = terminalLocator }
        return card
    }

    private func sortedCards() -> [AgentSessionCard] {
        sessions.values.sorted { lhs, rhs in
            if lhs.status.sortPriority != rhs.status.sortPriority { return lhs.status.sortPriority < rhs.status.sortPriority }
            return (lhs.updatedAt ?? lhs.startedAt ?? .distantPast) > (rhs.updatedAt ?? rhs.startedAt ?? .distantPast)
        }
    }

    private func removeSessionTree(_ key: AgentSessionKey) {
        var pending = [key.rawSessionID]
        var removedKeys: Set<AgentSessionKey> = []
        while let parentID = pending.popLast() {
            let candidates = sessions.filter { candidateKey, candidate in
                candidateKey.provider == key.provider && (candidateKey.rawSessionID == parentID || candidate.parentSessionID == parentID)
            }
            for (candidateKey, _) in candidates {
                guard removedKeys.insert(candidateKey).inserted else { continue }
                pending.append(candidateKey.rawSessionID)
                sessions.removeValue(forKey: candidateKey)
            }
        }
    }

    private func displayID(for key: AgentSessionKey) -> String {
        "\(key.provider.rawValue.lowercased()).\(key.rawSessionID)"
    }

    private func bounded(_ value: String, limit: Int) -> String {
        String(value.prefix(limit))
    }

    private func boundedOptional(_ value: String?, limit: Int) -> String? {
        value.map { bounded($0, limit: limit) }
    }
}
