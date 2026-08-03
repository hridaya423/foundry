import Darwin
import Foundation

final class AgentEventSocketServer: @unchecked Sendable {
    typealias Handler = @Sendable (AgentEventEnvelope) async -> AgentEventAck

    static var socketURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Foundry/agents.sock")
    }

    private let lock = NSLock()
    private let endpoint: URL
    private var socketDescriptor: Int32 = -1
    private var acceptTask: Task<Void, Never>?
    private var clientTasks: [UUID: Task<Void, Never>] = [:]
    private var generation = 0

    init(socketURL: URL = AgentEventSocketServer.socketURL) {
        endpoint = socketURL
    }

    @discardableResult
    func start(handler: @escaping Handler) -> Bool {
        stop()
        let socketURL = endpoint
        let directory = socketURL.deletingLastPathComponent()

        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        } catch {
            return false
        }

        Self.removeSocket(at: socketURL.path)
        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { return false }

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = Array(socketURL.path.utf8) + [0]
        guard pathBytes.count <= MemoryLayout.size(ofValue: address.sun_path) else {
            close(descriptor)
            return false
        }
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            buffer.copyBytes(from: pathBytes)
        }

        let addressLength = socklen_t(MemoryLayout<sockaddr_un>.size)
        let bound = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                Darwin.bind(descriptor, sockaddrPointer, addressLength)
            }
        }
        guard bound == 0, listen(descriptor, 16) == 0 else {
            close(descriptor)
            Self.removeSocket(at: socketURL.path)
            return false
        }
        chmod(socketURL.path, 0o600)

        let generation = withLock {
            self.generation += 1
            socketDescriptor = descriptor
            return self.generation
        }
        acceptTask = Task.detached(priority: .utility) { [weak self] in
            await self?.acceptLoop(descriptor: descriptor, generation: generation, handler: handler)
        }
        return true
    }

    func stop() {
        let (descriptor, tasks) = withLock { () -> (Int32, [Task<Void, Never>]) in
            let current = socketDescriptor
            socketDescriptor = -1
            generation += 1
            let tasks = Array(clientTasks.values)
            clientTasks.removeAll()
            return (current, tasks)
        }
        acceptTask?.cancel()
        acceptTask = nil
        tasks.forEach { $0.cancel() }
        if descriptor >= 0 { close(descriptor) }
        Self.removeSocket(at: endpoint.path)
    }

    private func acceptLoop(descriptor: Int32, generation: Int, handler: @escaping Handler) async {
        while Task.isCancelled == false {
            guard isCurrent(generation) else { return }
            let client = accept(descriptor, nil, nil)
            guard client >= 0 else {
                if Task.isCancelled { return }
                continue
            }
            let clientID = UUID()
            let task = Task.detached(priority: .utility) { [weak self] in
                defer { self?.removeClient(clientID) }
                let isActive: @Sendable () -> Bool = { [weak self] in
                    self?.isCurrent(generation) == true
                }
                await Self.handle(client: client, handler: handler, isActive: isActive)
            }
            let shouldKeep = withLock { () -> Bool in
                guard self.generation == generation, self.socketDescriptor >= 0 else { return false }
                clientTasks[clientID] = task
                return true
            }
            if shouldKeep == false { task.cancel() }
        }
    }

    private static func handle(client: Int32, handler: @escaping Handler, isActive: @escaping @Sendable () -> Bool) async {
        defer { close(client) }
        var timeout = timeval(tv_sec: 2, tv_usec: 0)
        setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(client, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        let data = readRequest(from: client)
        let ack: AgentEventAck
        if data.isEmpty {
            ack = .rejected(error: "Empty agent event")
        } else if data.count > 1_048_576 {
            ack = .rejected(error: "Agent event exceeds payload limit")
        } else {
            do {
                let envelope = try JSONDecoder().decode(AgentEventEnvelope.self, from: data)
                _ = try envelope.validated()
                guard isActive() else { return }
                ack = await handler(envelope)
            } catch {
                ack = .rejected(error: "Invalid agent event: \(error.localizedDescription)")
            }
        }

        guard let encoded = try? JSONEncoder().encode(ack) else { return }
        writeAll(encoded, to: client)
    }

    private static func readRequest(from client: Int32) -> Data {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 16_384)
        while data.count <= 1_048_576 {
            let count = buffer.withUnsafeMutableBytes { bytes in
                read(client, bytes.baseAddress, bytes.count)
            }
            guard count > 0 else { break }
            data.append(buffer, count: count)
        }
        return data
    }

    private static func writeAll(_ data: Data, to client: Int32) {
        data.withUnsafeBytes { bytes in
            guard let baseAddress = bytes.baseAddress else { return }
            var offset = 0
            while offset < data.count {
                let count = write(client, baseAddress.advanced(by: offset), data.count - offset)
                guard count > 0 else { return }
                offset += count
            }
        }
    }

    private func withLock<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }

    private func isCurrent(_ expectedGeneration: Int) -> Bool {
        withLock { generation == expectedGeneration && socketDescriptor >= 0 }
    }

    private func removeClient(_ id: UUID) {
        _ = withLock { clientTasks.removeValue(forKey: id) }
    }

    private static func removeSocket(at path: String) {
        _ = path.withCString { pointer in
            Darwin.unlink(pointer)
        }
    }
}
