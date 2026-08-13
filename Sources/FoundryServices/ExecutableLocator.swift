import Foundation
public struct LocatedExecutable: Equatable, Sendable { public let path: String; public init(path: String) { self.path = path } }
public struct ExecutableLocator: Sendable {
    public typealias FileInfo = @Sendable (String) -> Bool
    private let fileInfo: FileInfo
    public init(fileInfo: @escaping FileInfo = { path in FileManager.default.isExecutableFile(atPath: path) && (try? FileManager.default.attributesOfItem(atPath: path)[.type] as? FileAttributeType) == .typeRegular }) { self.fileInfo = fileInfo }
    public func locate(name: String, candidates: [String], environment: [String: String]) throws -> LocatedExecutable? { for path in candidates where fileInfo(path) { return LocatedExecutable(path: path) }; for directory in (environment["PATH"] ?? "").split(separator: ":", omittingEmptySubsequences: true) { let path = String(directory) + "/" + name; if fileInfo(path) { return LocatedExecutable(path: path) } }; return nil }
}
public struct VersionProbe: Sendable {
    public let run: @Sendable (String, [String]) async throws -> ProcessResult
    public init(run: @escaping @Sendable (String, [String]) async throws -> ProcessResult = { try await ProcessRunner.run(path: $0, arguments: $1) }) { self.run = run }
}
public struct CapabilityAssessor: Sendable {
    let locator: ExecutableLocator; let versionProbe: VersionProbe; private let environment: [String: String]
    public init(locator: ExecutableLocator, versionProbe: VersionProbe, environment: [String: String] = ProcessInfo.processInfo.environment) { self.locator = locator; self.versionProbe = versionProbe; self.environment = environment }
    public func assess(_ requirement: CapabilityRequirement) async throws -> CapabilityState {
        let path = requirement.pathDirectories.isEmpty ? (environment["PATH"] ?? "") : requirement.pathDirectories.joined(separator: ":")
        guard let executable = try locator.locate(name: requirement.executableName, candidates: requirement.explicitPaths, environment: ["PATH": path]) else { return .setupRequired(SetupPlan(commands: [], artifacts: [], mutationScope: "none", cleanupOwnership: "none", disclosure: "missing executable")) }
        if requirement.minimumVersion != nil && requirement.versionArguments.isEmpty { return .unavailable("verification not configured: no version probe arguments") }
        guard requirement.versionArguments.isEmpty == false else { return .ready }
        do {
            let result = try await versionProbe.run(executable.path, requirement.versionArguments)
            guard result.succeeded else { return .unavailable(result.stderr) }
            guard let version = CapabilityRequirement.parseVersion(result.stdout) else { return .unavailable("malformed version output") }
            if let minimum = requirement.minimumVersion, let minimumVersion = CapabilityRequirement.parseVersion(minimum, minimum: true) {
                let width = max(version.count, minimumVersion.count)
                let actual = version + Array(repeating: 0, count: width - version.count)
                let expected = minimumVersion + Array(repeating: 0, count: width - minimumVersion.count)
                if actual.lexicographicallyPrecedes(expected) { return .degraded("version incompatible") }
            }
            return .ready
        } catch { if error is CancellationError || (error as? ProcessRunnerError) == .cancelled { throw error }; return .unavailable(String(describing: error)) }
    }
}
