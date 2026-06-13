import AppKit
import Foundation

@MainActor
final class ActionRunner {
    private let diagnostics: DiagnosticsService
    private let rebuildFileIndex: (@Sendable () -> Void)?

    init(diagnostics: DiagnosticsService, rebuildFileIndex: (@Sendable () -> Void)? = nil) {
        self.diagnostics = diagnostics
        self.rebuildFileIndex = rebuildFileIndex
    }

    func perform(_ action: CommandAction) {
        switch action.kind {
        case let .openApp(path, name):
            let configuration = NSWorkspace.OpenConfiguration()
            NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: path), configuration: configuration) { [diagnostics] _, error in
                if let error {
                    diagnostics.log("Failed to launch \(name): \(error.localizedDescription)")
                } else {
                    diagnostics.log("Launched app: \(name)")
                }
            }

        case let .openFile(path):
            let opened = NSWorkspace.shared.open(URL(fileURLWithPath: path))
            diagnostics.log(opened ? "Opened file: \(path)" : "Failed to open file: \(path)")

        case let .openURL(urlString):
            guard let url = URL(string: urlString) else {
                diagnostics.log("Invalid URL: \(urlString)")
                return
            }
            NSWorkspace.shared.open(url)

        case .openConfigFolder:
            let folder = ConfigService.configURL.deletingLastPathComponent()
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            NSWorkspace.shared.open(folder)

        case let .revealInFinder(path):
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
            diagnostics.log("Revealed in Finder: \(path)")

        case let .copyToClipboard(value):
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(value, forType: .string)
            diagnostics.log("Copied to clipboard")

        case .rebuildFileIndex:
            guard let rebuildFileIndex else {
                diagnostics.log("File index rebuild is unavailable")
                return
            }
            diagnostics.log("Requested file index rebuild")
            rebuildFileIndex()

        case let .runProcess(path, arguments):
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: path)
                process.arguments = arguments

                do {
                    try process.run()
                } catch {
                    fputs("[Foundry] Failed to run \(path): \(error.localizedDescription)\n", stderr)
                }
            }

        case .quit:
            NSApp.terminate(nil)

        case let .log(message):
            diagnostics.log(message)
        }
    }
}
