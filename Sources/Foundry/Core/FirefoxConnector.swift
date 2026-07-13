import AppKit
import Foundation

@MainActor
final class FirefoxConnectorInstaller {
    static let extensionID = "firefox-connector@foundry.local"
    private let diagnostics: DiagnosticsService

    init(diagnostics: DiagnosticsService) {
        self.diagnostics = diagnostics
    }

    func configureMainBrowser() {
        let installed = BrowserSource.allCases.filter { $0.isInstalled }
        guard installed.isEmpty == false else { return }

        if let saved = UserDefaults.standard.string(forKey: "foundry.mainBrowser"),
           let browser = BrowserSource(rawValue: saved),
           installed.contains(browser) {
            if browser == .firefox { requestFirefoxConnector() }
            return
        }

        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 260, height: 26), pullsDown: false)
        popup.addItems(withTitles: installed.map(\.displayName))
        if let target = URL(string: "https://example.com"),
           let defaultName = NSWorkspace.shared.urlForApplication(toOpen: target)?.lastPathComponent,
           let defaultIndex = installed.firstIndex(where: { "\($0.applicationName).app" == defaultName }) {
            popup.selectItem(at: defaultIndex)
        }

        let alert = NSAlert()
        alert.messageText = "What is your main browser?"
        alert.informativeText = "Foundry will use this choice for browser-specific setup. Other installed browsers remain searchable without connector setup."
        alert.accessoryView = popup
        alert.addButton(withTitle: "Continue")
        alert.addButton(withTitle: "Not Now")

        guard alert.runModal() == .alertFirstButtonReturn,
              let selected = installed[safe: popup.indexOfSelectedItem] else { return }
        UserDefaults.standard.set(selected.rawValue, forKey: "foundry.mainBrowser")
        if selected == .firefox { requestFirefoxConnector() }
    }

    private func requestFirefoxConnector() {
        guard UserDefaults.standard.bool(forKey: "foundry.firefox.connector.promptShown") == false else { return }

        let alert = NSAlert()
        alert.messageText = "Connect Foundry to Firefox?"
        alert.informativeText = "Foundry can connect to your open Firefox tabs. Firefox will open its Add-ons Debugging page and Finder will show the local connector package for you to load. Foundry only receives tab titles and URLs."
        alert.addButton(withTitle: "Install Connector")
        alert.addButton(withTitle: "Not Now")
        UserDefaults.standard.set(true, forKey: "foundry.firefox.connector.promptShown")

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            try install()
            diagnostics.log("Opened Firefox connector for approval")
        } catch {
            diagnostics.log("Could not prepare Firefox connector: \(error.localizedDescription)")
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
            "args": ["--firefox-native-host"],
            "type": "stdio",
            "allowed_extensions": [Self.extensionID]
        ]
        let manifestData = try JSONSerialization.data(withJSONObject: hostManifest, options: [.prettyPrinted, .sortedKeys])
        try? FileManager.default.removeItem(at: hostDirectory.appendingPathComponent("com.honey.foundry.json"))
        try manifestData.write(to: hostDirectory.appendingPathComponent("com.hridya.foundry.json"), options: .atomic)

        guard let manifest = Bundle.module.url(forResource: "manifest", withExtension: "json"),
              let background = Bundle.module.url(forResource: "background", withExtension: "js") else { throw InstallerError.resourceUnavailable }
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

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
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
    static func run() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        while let message = readMessage() {
            guard let data = try? JSONSerialization.data(withJSONObject: message, options: []) else { continue }
            let url = FirefoxNativeTabsStore.url(home: home)
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: url, options: .atomic)
        }
    }

    private static func readMessage() -> [String: Any]? {
        guard let header = readExactly(4) else { return nil }
        let length = header.enumerated().reduce(UInt32(0)) { result, item in
            result | UInt32(item.element) << UInt32(item.offset * 8)
        }
        guard length > 0, let payload = readExactly(Int(length)), let object = try? JSONSerialization.jsonObject(with: payload) as? [String: Any] else { return nil }
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
