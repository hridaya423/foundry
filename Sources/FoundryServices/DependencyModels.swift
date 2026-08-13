import Foundation
import CryptoKit

public enum CapabilityState: Equatable, Sendable { case ready, setupRequired(SetupPlan), unavailable(String), degraded(String) }
public struct ExactCommand: Equatable, Sendable { public let executable: String; public let arguments: [String]; public init(executable: String, arguments: [String]) { self.executable = executable; self.arguments = arguments } }
public struct Artifact: Equatable, Sendable {
    public let origin: String; public let destination: String; public let downloadBytes: Int64?; public let installBytes: Int64?; public let integrityExpectation: String
    public init(origin: String, destination: String, downloadBytes: Int64? = nil, installBytes: Int64? = nil, integrityExpectation: String = "verified") { self.origin = origin; self.destination = destination; self.downloadBytes = downloadBytes; self.installBytes = installBytes; self.integrityExpectation = integrityExpectation }
}
public struct SetupPlan: Equatable, Sendable {
    public let commands: [ExactCommand]; public let artifacts: [Artifact]; public let estimatedDownloadBytes: Int64?; public let estimatedInstallBytes: Int64?; public let mutationScope: String; public let cleanupOwnership: String; public let disclosure: String
    public init(commands: [ExactCommand], artifacts: [Artifact], estimatedDownloadBytes: Int64? = nil, estimatedInstallBytes: Int64? = nil, mutationScope: String, cleanupOwnership: String, disclosure: String) { self.commands = commands; self.artifacts = artifacts; self.estimatedDownloadBytes = estimatedDownloadBytes; self.estimatedInstallBytes = estimatedInstallBytes; self.mutationScope = mutationScope; self.cleanupOwnership = cleanupOwnership; self.disclosure = disclosure }
    public var fingerprint: String {
        var data = Data()
        func put(_ value: String) { var length = UInt64(value.utf8.count).bigEndian; data.append(Data(bytes: &length, count: 8)); data.append(contentsOf: value.utf8) }
        func put(_ value: Int64?) { put(value.map(String.init) ?? "<nil>") }
        put(String(commands.count)); for command in commands { put(command.executable); put(String(command.arguments.count)); command.arguments.forEach(put) }
        put(String(artifacts.count)); for artifact in artifacts { put(artifact.origin); put(artifact.destination); put(artifact.downloadBytes); put(artifact.installBytes); put(artifact.integrityExpectation) }
        put(estimatedDownloadBytes); put(estimatedInstallBytes); put(mutationScope); put(cleanupOwnership); put(disclosure)
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

public enum CapabilityRequirementError: Error, Equatable { case malformedMinimumVersion(String) }
public struct CapabilityRequirement: Equatable, Sendable {
    public let executableName: String; public let explicitPaths: [String]; public let pathDirectories: [String]; public let versionArguments: [String]; public let minimumVersion: String?
    public init(executableName: String, explicitPaths: [String] = [], pathDirectories: [String] = [], versionArguments: [String] = [], minimumVersion: String? = nil) throws {
        if let minimumVersion, Self.parseVersion(minimumVersion, minimum: true) == nil { throw CapabilityRequirementError.malformedMinimumVersion(minimumVersion) }
        self.executableName = executableName; self.explicitPaths = explicitPaths; self.pathDirectories = pathDirectories; self.versionArguments = versionArguments; self.minimumVersion = minimumVersion
    }
    static func parseVersion(_ text: String, minimum: Bool = false) -> [Int]? {
        if text.range(of: #"\b\d{4}-\d{1,2}-\d{1,2}\b"#, options: .regularExpression) != nil { return nil }
        let pattern = minimum ? #"^v?\d+(?:\.\d+){0,2}$"# : #"(?<![A-Za-z0-9.])v?\d+(?:\.\d+){0,2}(?![A-Za-z0-9.])"#
        guard let regex = try? NSRegularExpression(pattern: pattern), let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        let token: Substring
        if let range = Range(match.range, in: text) { token = text[range].drop(while: { $0 == "v" }) } else { return nil }
        let values = token.split(separator: ".").compactMap { Int($0) }
        return values.count == token.filter({ $0 == "." }).count + 1 ? values : nil
    }
}
