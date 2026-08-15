import Foundation
import Darwin

enum SourceRootLocator {
    static let registrationKey = "foundry.sourceRoot"

    struct FileChecks: Sendable {
        let isValid: @Sendable (URL) -> Bool

        static let real = FileChecks { root in
            let fileManager = FileManager.default
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue else { return false }
            let script = root.appendingPathComponent("scripts/build-app.sh")
            guard fileManager.isReadableFile(atPath: script.path), fileManager.isExecutableFile(atPath: script.path) else { return false }
            guard let attributes = try? fileManager.attributesOfItem(atPath: root.path),
                  let ownerID = attributes[.ownerAccountID] as? NSNumber else { return false }
            return ownerID.uint32Value == getuid()
        }
    }

    static func locate(
        packaged: Bool? = nil,
        candidates: [URL]? = nil,
        defaults: UserDefaults? = nil,
        fileChecks: FileChecks = .real,
        fileManager: FileManager = .default
    ) -> URL? {
        let isPackaged = packaged ?? (Bundle.main.bundleURL.pathExtension == "app")
        let defaults = defaults ?? (isPackaged ? .standard : UserDefaults(suiteName: "com.hridya.foundry")!)
        if isPackaged {
            guard let path = defaults.string(forKey: registrationKey) else { return nil }
            return validated(URL(fileURLWithPath: path, isDirectory: true), fileChecks: fileChecks)
        }

        let sourceCandidates = candidates ?? [URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true)]
        guard let root = sourceCandidates.lazy.compactMap({ validated($0, fileChecks: fileChecks) }).first else { return nil }
        defaults.set(root.path, forKey: registrationKey)
        return root
    }

    private static func validated(_ candidate: URL, fileChecks: FileChecks) -> URL? {
        let root = candidate.standardizedFileURL.resolvingSymlinksInPath()
        return fileChecks.isValid(root) ? root : nil
    }
}
