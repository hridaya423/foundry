import Foundation

final class FileSearchProvider: CommandProvider, @unchecked Sendable {
    let id = "foundry.files"

    private let index: FileIndex
    private let diagnostics: DiagnosticsService
    private let indexingStatus: IndexingStatusStore

    init(diagnostics: DiagnosticsService, indexingStatus: IndexingStatusStore) {
        self.diagnostics = diagnostics
        self.indexingStatus = indexingStatus
        self.index = FileIndex()

        Task.detached(priority: .utility) { [index, diagnostics, indexingStatus, id] in
            await index.reset()
            indexingStatus.setStatus("indexing files", for: id)

            let span = diagnostics.startSpan("files.load")
            var total = 0
            let scanner = FileScanner()

            await scanner.scan { chunk in
                guard Task.isCancelled == false else { return false }
                total += chunk.count
                await index.append(chunk)
                indexingStatus.setStatus("indexing files: \(total)", for: id)
                await Task.yield()

                return true
            }

            diagnostics.endSpan(span)
            diagnostics.log("Loaded \(total) indexed files")
            indexingStatus.setStatus("\(total) files", for: id)
        }
    }

    func results(matching query: String) async -> [CommandResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return [] }

        let matches = await index.search(trimmed, limit: 8)
        guard Task.isCancelled == false else { return [] }

        return matches.map { match in
            CommandResult(
                id: "file.\(match.record.identity)",
                title: match.record.name,
                subtitle: match.record.displayLocation,
                icon: CommandIcon(fallback: match.record.fallbackIcon, filePath: match.record.path),
                score: match.score,
                primaryAction: CommandAction(
                    id: "file.\(match.record.identity).open",
                    title: "Open",
                    kind: .openFile(path: match.record.path)
                ),
                secondaryActions: []
            )
        }
    }
}

actor FileIndex {
    private var records: [FileRecord] = []

    func reset() {
        records.removeAll(keepingCapacity: true)
    }

    func append(_ newRecords: [FileRecord]) {
        records.append(contentsOf: newRecords)
    }

    func search(_ query: String, limit: Int) -> [FileMatch] {
        let normalizedQuery = SearchScoring.normalize(query)
        guard normalizedQuery.isEmpty == false, limit > 0 else { return [] }

        let allowFuzzy = normalizedQuery.count >= 3
        var topCandidates: [FileMatch] = []
        topCandidates.reserveCapacity(limit)

        for record in records {
            guard Task.isCancelled == false else { return [] }
            guard let score = SearchScoring.score(
                normalizedQuery: normalizedQuery,
                candidates: record.normalizedSearchCandidates,
                allowFuzzy: allowFuzzy
            ) else { continue }

            insertTopCandidate(FileMatch(record: record, score: score - 8), into: &topCandidates, limit: limit)
        }

        guard Task.isCancelled == false else { return [] }

        return topCandidates.sorted { lhs, rhs in
            if lhs.score == rhs.score {
                return lhs.record.name.localizedCaseInsensitiveCompare(rhs.record.name) == .orderedAscending
            }
            return lhs.score > rhs.score
        }
    }

    private func insertTopCandidate(_ candidate: FileMatch, into candidates: inout [FileMatch], limit: Int) {
        guard candidates.count == limit else {
            candidates.append(candidate)
            return
        }

        guard let lowestIndex = candidates.indices.min(by: { candidates[$0].score < candidates[$1].score }) else {
            return
        }

        if candidate.score > candidates[lowestIndex].score {
            candidates[lowestIndex] = candidate
        }
    }
}

private struct FileScanner {
    private let chunkSize = 2_000

    func scan(onChunk: ([FileRecord]) async -> Bool) async {
        var chunk: [FileRecord] = []
        chunk.reserveCapacity(chunkSize)
        var seen = Set<String>()
        let roots = fileSearchRoots()
        let priorityRootPaths = Set(roots.dropLast().map { $0.standardizedFileURL.path })

        for root in roots where FileManager.default.fileExists(atPath: root.path) {
            guard Task.isCancelled == false else { return }
            let rootPath = root.standardizedFileURL.path
            let isWholeDiskPass = rootPath == "/"

            guard let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey, .isPackageKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants],
                errorHandler: { _, _ in true }
            ) else { continue }

            while let url = enumerator.nextObject() as? URL {
                guard Task.isCancelled == false else { return }

                let path = url.standardizedFileURL.path
                if isWholeDiskPass, priorityRootPaths.contains(path) {
                    enumerator.skipDescendants()
                    continue
                }

                if shouldSkip(url: url) {
                    enumerator.skipDescendants()
                    continue
                }

                guard let resourceValues = try? url.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey]) else { continue }
                if resourceValues.isDirectory == true { continue }
                guard resourceValues.isRegularFile == true else { continue }
                guard seen.insert(path).inserted else { continue }

                chunk.append(FileRecord(url: url))
                if chunk.count >= chunkSize {
                    guard await onChunk(chunk) else { return }
                    chunk.removeAll(keepingCapacity: true)
                }
            }
        }

        if chunk.isEmpty == false {
            _ = await onChunk(chunk)
        }
    }

    private func fileSearchRoots() -> [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let candidates = [
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath),
            home.appendingPathComponent("Desktop"),
            home.appendingPathComponent("Documents"),
            home.appendingPathComponent("Downloads"),
            home.appendingPathComponent("Developer"),
            home.appendingPathComponent("Code"),
            home.appendingPathComponent("Projects"),
            URL(fileURLWithPath: "/")
        ]

        var seen = Set<String>()
        return candidates.filter { url in
            let standardized = url.standardizedFileURL.path
            guard FileManager.default.fileExists(atPath: standardized) else { return false }
            return seen.insert(standardized).inserted
        }
    }

    private func shouldSkip(url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        let name = url.lastPathComponent
        let skippedNames: Set<String> = [
            ".git",
            ".svn",
            ".hg",
            ".build",
            ".swiftpm",
            "node_modules",
            "Pods",
            "DerivedData",
            "Library",
            "Cache",
            "Caches",
            "target",
            "dist",
            "build",
            "Build",
            "tmp",
            "temp",
            ".next",
            ".turbo",
            ".cache",
            ".Trash",
            ".Trashes",
            ".Spotlight-V100",
            ".fseventsd",
            "__pycache__"
        ]

        let skippedPathPrefixes = [
            "/dev",
            "/Network",
            "/System/Volumes",
            "/private/tmp",
            "/private/var",
            "/tmp",
            "/var",
            "/Volumes/.timemachine"
        ]

        if skippedNames.contains(name) { return true }
        if skippedPathPrefixes.contains(where: { path == $0 || path.hasPrefix($0 + "/") }) { return true }
        if name.hasSuffix(".app") { return true }
        if name.hasSuffix(".xcarchive") { return true }
        if name.hasSuffix(".framework") { return true }
        if name.hasSuffix(".bundle") { return true }
        if name.hasSuffix(".plugin") { return true }
        return false
    }
}

struct FileRecord: Sendable, Hashable {
    let path: String
    let name: String
    let displayLocation: String
    let fallbackIcon: String
    let normalizedSearchCandidates: [String]

    var identity: String {
        path.replacingOccurrences(of: "/", with: ".")
    }

    init(url: URL) {
        let name = url.lastPathComponent
        let nameWithoutExtension = url.deletingPathExtension().lastPathComponent
        let extensionName = url.pathExtension
        let fallbackIcon = extensionName.isEmpty ? "FI" : String(extensionName.uppercased().prefix(3))

        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let parent = url.deletingLastPathComponent().path
        let displayLocation: String
        if parent == home {
            displayLocation = "~"
        } else if parent.hasPrefix(home + "/") {
            displayLocation = "~" + parent.dropFirst(home.count)
        } else {
            displayLocation = parent
        }

        self.path = url.path
        self.name = name
        self.displayLocation = displayLocation
        self.fallbackIcon = fallbackIcon
        self.normalizedSearchCandidates = [name, nameWithoutExtension, extensionName]
            .map(SearchScoring.normalize)
            .filter { $0.isEmpty == false }
    }
}

struct FileMatch: Sendable, Hashable {
    let record: FileRecord
    let score: Double
}
