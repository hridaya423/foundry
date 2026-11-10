import AppKit
import Foundation
import FoundryServices

@MainActor
final class FirefoxConnectorInstaller {
    nonisolated static let extensionID = "firefox-connector@foundry.local"
    private let diagnostics: DiagnosticsService
    private let localState: LocalStateStore
    /// In-panel prompt seam — defaults to decline so modal UI never runs
    /// under tests.
    private let requestPrompt: @MainActor (PanelPromptSpec) async -> PanelPromptResult

    init(
        diagnostics: DiagnosticsService,
        localState: LocalStateStore = .shared,
        requestPrompt: @escaping @MainActor (PanelPromptSpec) async -> PanelPromptResult = { _ in .cancelled }
    ) {
        self.diagnostics = diagnostics
        self.localState = localState
        self.requestPrompt = requestPrompt
    }

    func requestFirefoxConnector() {
        guard localState.get(\.firefoxConnectorPromptShown) == false else { return }
        localState.set(\.firefoxConnectorPromptShown, true)
        Task { @MainActor in
            let prompt = await requestPrompt(PanelPromptSpec(
                title: "Connect Foundry to Firefox?",
                message: """
                    Foundry can connect to your open Firefox tabs. Firefox will open its Add-ons Debugging page \
                    and Finder will show the local connector package for you to load. Foundry only receives tab titles and URLs.
                    """,
                confirmLabel: "Install Connector",
                cancelLabel: "Not Now"
            ))
            guard prompt.confirmed else { return }
            do {
                try install()
                diagnostics.log("Opened Firefox connector for approval")
            } catch {
                diagnostics.log("Could not prepare Firefox connector: \(error.localizedDescription)")
                _ = await requestPrompt(PanelPromptSpec(
                    title: "Couldn't set up the Firefox connector",
                    message: "\(error.localizedDescription) Firefox tabs stay searchable through your other browsers.",
                    confirmLabel: "OK",
                    cancelLabel: nil
                ))
            }
        }
    }

    private func install() throws {
        let hostDirectory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Mozilla/NativeMessagingHosts", isDirectory: true)
        try FileManager.default.createDirectory(at: hostDirectory, withIntermediateDirectories: true)

        guard let executable = Bundle.main.executableURL else { throw InstallerError.executableUnavailable }
        let hostManifest: [String: Any] = [
            "name": "com.hridya.foundry",
            "description": "Foundry Firefox tab connector",
            "path": executable.path,
            "type": "stdio",
            "allowed_extensions": [Self.extensionID]
        ]
        let manifestData = try JSONSerialization.data(withJSONObject: hostManifest, options: [.prettyPrinted, .sortedKeys])
        try? FileManager.default.removeItem(at: hostDirectory.appendingPathComponent("com.honey.foundry.json"))
        try manifestData.write(to: hostDirectory.appendingPathComponent("com.hridya.foundry.json"), options: .atomic)

        guard let manifest = Bundle.packagedResources?.url(forResource: "manifest", withExtension: "json"),
              let background = Bundle.packagedResources?.url(forResource: "background", withExtension: "js") else { throw InstallerError.resourceUnavailable }
        let source = FileManager.default.temporaryDirectory.appendingPathComponent("FoundryFirefoxConnector-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: manifest, to: source.appendingPathComponent("manifest.json"))
        try FileManager.default.copyItem(at: background, to: source.appendingPathComponent("background.js"))
        defer { try? FileManager.default.removeItem(at: source) }
        let xpi = FileManager.default.temporaryDirectory.appendingPathComponent("FoundryFirefoxConnector.xpi")
        try? FileManager.default.removeItem(at: xpi)
        let zip = Process()
        zip.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        zip.arguments = ["-qr", xpi.path, "."]
        zip.currentDirectoryURL = source
        try zip.run()
        zip.waitUntilExit()
        guard zip.terminationStatus == 0 else { throw InstallerError.archiveFailed }
        let openFirefox = Process()
        openFirefox.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        openFirefox.arguments = ["-a", "Firefox", "about:debugging#/runtime/this-firefox"]
        try openFirefox.run()
        NSWorkspace.shared.activateFileViewerSelecting([xpi])
    }
}

private enum InstallerError: LocalizedError {
    case executableUnavailable
    case resourceUnavailable
    case archiveFailed

    var errorDescription: String? {
        switch self {
        case .executableUnavailable: "Foundry executable is unavailable"
        case .resourceUnavailable: "Firefox connector resources are unavailable"
        case .archiveFailed: "Could not package the Firefox connector"
        }
    }
}

enum FirefoxNativeTabsStore {
    static func url(home: URL) -> URL {
        home.appendingPathComponent("Library/Application Support/Foundry/firefox-tabs.json")
    }
}

enum FirefoxNativeHost {
    /// Firefox starts a host with the manifest path and the extension ID; it has no field for extra arguments.
    static func isLaunch(_ arguments: [String]) -> Bool {
        arguments.contains("--firefox-native-host") || arguments.contains(FirefoxConnectorInstaller.extensionID)
    }

    static func run() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        while let message = readMessage() {
            let data = BestEffort.attempt("encode firefox message") {
                try JSONSerialization.data(withJSONObject: message, options: [])
            }
            guard let data else { continue }
            let url = FirefoxNativeTabsStore.url(home: home)
            BestEffort.attempt("prepare firefox tabs store") {
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            }
            BestEffort.attempt("write firefox tabs") {
                try data.write(to: url, options: .atomic)
            }
        }
    }

    private static func readMessage() -> [String: Any]? {
        guard let header = readExactly(4) else { return nil }
        let length = header.enumerated().reduce(UInt32(0)) { result, item in
            result | UInt32(item.element) << UInt32(item.offset * 8)
        }
        guard length > 0, let payload = readExactly(Int(length)) else { return nil }
        let raw = BestEffort.attempt("parse firefox message") {
            try JSONSerialization.jsonObject(with: payload)
        }
        guard let object = raw as? [String: Any] else { return nil }
        return object
    }

    private static func readExactly(_ count: Int) -> Data? {
        var data = Data()
        while data.count < count {
            let chunk = FileHandle.standardInput.readData(ofLength: count - data.count)
            guard chunk.isEmpty == false else { return nil }
            data.append(chunk)
        }
        return data
    }
}
