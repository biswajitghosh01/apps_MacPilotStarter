import Foundation
import Darwin

struct CleanupRules: Sendable {
    let minimumAgeDays: Int
    let minimumFileSizeBytes: Int64
    let maximumScanEntries: Int
    let maximumCandidates: Int
    let maximumItemsPerBatch: Int

    static let standard = CleanupRules(
        minimumAgeDays: 30,
        minimumFileSizeBytes: 1_024,
        maximumScanEntries: 20_000,
        maximumCandidates: 250,
        maximumItemsPerBatch: 100
    )

    static let excludedExtensions: Set<String> = [
        "db", "sqlite", "sqlite3", "plist", "json", "lock", "pid", "sock",
        "key", "pem", "p12", "pfx", "cer", "crt", "mobileprovision", "alias"
    ]

    func excludesExtension(_ pathExtension: String) -> Bool {
        Self.excludedExtensions.contains(pathExtension.lowercased())
    }

    func excludesPath(_ path: String) -> Bool {
        let sensitiveComponents = [
            "safari", "chrome", "firefox", "bravesoftware", "microsoft edge",
            "com.apple.mail", "outlook", "messages", "photos"
        ]
        return URL(fileURLWithPath: path).pathComponents.contains { component in
            let lower = component.lowercased()
            return sensitiveComponents.contains(where: { lower.contains($0) })
        }
    }
}

struct CleanupFileFingerprint: Equatable, Sendable {
    let device: UInt64
    let inode: UInt64
    let size: Int64
    let modifiedSeconds: Int64
    let modifiedNanoseconds: Int64
    let linkCount: UInt64
    let ownerUserID: UInt32
    let permissionMode: UInt32

    static func read(from url: URL) throws -> CleanupFileFingerprint {
        var info = stat()
        let status = url.standardizedFileURL.path.withCString { lstat($0, &info) }
        guard status == 0 else {
            throw CleanupEngineError.fileUnavailable(url.lastPathComponent)
        }
        guard (info.st_mode & S_IFMT) == S_IFREG else {
            throw CleanupEngineError.notRegularFile(url.lastPathComponent)
        }
        let modified = info.st_mtimespec
        return CleanupFileFingerprint(
            device: UInt64(info.st_dev),
            inode: UInt64(info.st_ino),
            size: Int64(info.st_size),
            modifiedSeconds: Int64(modified.tv_sec),
            modifiedNanoseconds: Int64(modified.tv_nsec),
            linkCount: UInt64(info.st_nlink),
            ownerUserID: UInt32(info.st_uid),
            permissionMode: UInt32(info.st_mode)
        )
    }
}

struct CleanupCandidate: Identifiable, Equatable, Sendable {
    let path: String
    let name: String
    let relativePath: String
    let byteCount: Int64
    let modifiedAt: Date
    let fingerprint: CleanupFileFingerprint

    var id: String { path }

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file)
    }
}

struct CleanupScanResult: Sendable {
    let rootPath: String
    let candidates: [CleanupCandidate]
    let skippedCount: Int
    let visitedCount: Int
    let wasTruncated: Bool
    let finishedAt: Date

    var candidateBytes: Int64 {
        candidates.reduce(0) { $0 + $1.byteCount }
    }

    var formattedCandidateBytes: String {
        ByteCountFormatter.string(fromByteCount: candidateBytes, countStyle: .file)
    }
}

enum CleanupEngineError: LocalizedError {
    case blocked(String)
    case unreadable(String)
    case fileUnavailable(String)
    case notRegularFile(String)
    case staleFile(String)
    case emptySelection
    case batchLimit(Int)

    var errorDescription: String? {
        switch self {
        case .blocked(let message), .unreadable(let message): return message
        case .fileUnavailable(let name): return "\(name) is no longer available. Run a new scan."
        case .notRegularFile(let name): return "\(name) is no longer a regular file and was not moved."
        case .staleFile(let name): return "\(name) changed after the preview and was skipped. Run a new scan."
        case .emptySelection: return "Select at least one file to continue."
        case .batchLimit(let limit): return "A cleanup batch is limited to \(limit) files. Select fewer files and try again."
        }
    }
}

/// Finds conservative cleanup candidates. It reads metadata only and never opens file contents.
struct CleanupCandidateScanner: Sendable {
    let safetyPolicy: SafetyPolicy
    let rules: CleanupRules

    init(safetyPolicy: SafetyPolicy = SafetyPolicy(), rules: CleanupRules = .standard) {
        self.safetyPolicy = safetyPolicy
        self.rules = rules
    }

    func scan(_ root: URL, now: Date = Date()) throws -> CleanupScanResult {
        guard case .allowed = safetyPolicy.validateCleanupRoot(root) else {
            if case .blocked(let reason) = safetyPolicy.validateCleanupRoot(root) {
                throw CleanupEngineError.blocked(reason)
            }
            throw CleanupEngineError.blocked("This cleanup location is not approved.")
        }

        let rootURL = root.standardizedFileURL
        let rootPath = rootURL.path
        let cutoff = now.addingTimeInterval(-Double(max(1, rules.minimumAgeDays)) * 24 * 60 * 60)
        let keys: [URLResourceKey] = [
            .isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey,
            .isHiddenKey, .isPackageKey, .fileSizeKey,
            .contentModificationDateKey, .nameKey
        ]

        var skipped = 0
        var visited = 0
        var truncated = false
        var candidates: [CleanupCandidate] = []

        guard let enumerator = FileManager.default.enumerator(
            at: rootURL,
            includingPropertiesForKeys: keys,
            options: [.skipsPackageDescendants],
            errorHandler: { _, _ in
                skipped += 1
                return true
            }
        ) else {
            throw CleanupEngineError.unreadable("MacPilot could not read this folder. Check the selected folder permission and try again.")
        }

        while let item = enumerator.nextObject() as? URL {
            visited += 1
            if visited > rules.maximumScanEntries {
                truncated = true
                skipped += 1
                enumerator.skipDescendants()
                break
            }

            do {
                let values = try item.resourceValues(forKeys: Set(keys))
                if values.isSymbolicLink == true {
                    skipped += 1
                    enumerator.skipDescendants()
                    continue
                }
                if values.isDirectory == true {
                    if values.isHidden == true || values.isPackage == true || item.lastPathComponent.hasPrefix(".") {
                        skipped += 1
                        enumerator.skipDescendants()
                    }
                    continue
                }
                guard values.isRegularFile == true,
                      values.isHidden != true,
                      values.isPackage != true else {
                    skipped += 1
                    continue
                }

                let fileName = values.name ?? item.lastPathComponent
                guard !fileName.hasPrefix(".") else {
                    skipped += 1
                    continue
                }

                let extensionName = item.pathExtension.lowercased()
                guard !rules.excludesExtension(extensionName) else {
                    skipped += 1
                    continue
                }

                // Avoid caches/logs associated with browser profiles and personal communications.
                guard !rules.excludesPath(item.path) else {
                    skipped += 1
                    continue
                }

                let bytes = Int64(max(0, values.fileSize ?? 0))
                guard bytes >= rules.minimumFileSizeBytes,
                      let modifiedAt = values.contentModificationDate,
                      modifiedAt <= cutoff else {
                    continue
                }

                guard case .allowed = safetyPolicy.validateCleanupTarget(item, under: rootURL) else {
                    skipped += 1
                    enumerator.skipDescendants()
                    continue
                }
                let fingerprint = try CleanupFileFingerprint.read(from: item)
                guard fingerprint.linkCount == 1 else {
                    skipped += 1
                    continue
                }

                let relativePath = Self.relativePath(of: item, below: rootURL)
                candidates.append(CleanupCandidate(
                    path: item.standardizedFileURL.path,
                    name: fileName,
                    relativePath: relativePath,
                    byteCount: bytes,
                    modifiedAt: modifiedAt,
                    fingerprint: fingerprint
                ))

                if candidates.count >= rules.maximumCandidates {
                    truncated = true
                    break
                }
            } catch {
                skipped += 1
            }
        }

        candidates.sort {
            if $0.byteCount == $1.byteCount {
                return $0.relativePath.localizedCaseInsensitiveCompare($1.relativePath) == .orderedAscending
            }
            return $0.byteCount > $1.byteCount
        }

        return CleanupScanResult(
            rootPath: rootPath,
            candidates: candidates,
            skippedCount: skipped,
            visitedCount: visited,
            wasTruncated: truncated,
            finishedAt: now
        )
    }

    private static func relativePath(of url: URL, below root: URL) -> String {
        let prefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
        let path = url.standardizedFileURL.path
        guard path.hasPrefix(prefix) else { return url.lastPathComponent }
        return String(path.dropFirst(prefix.count))
    }
}

protocol TrashMoving: Sendable {
    func moveToTrash(_ url: URL) throws
}

struct FileManagerTrashMover: TrashMoving {
    func moveToTrash(_ url: URL) throws {
        // Passing nil is intentional: MacPilot does not persist filesystem paths in its audit log.
        try FileManager.default.trashItem(at: url, resultingItemURL: nil)
    }
}

enum CleanupItemStatus: String, Sendable {
    case moved
    case skipped
    case failed
}

struct CleanupItemOutcome: Identifiable, Sendable {
    let id: String
    let name: String
    let byteCount: Int64
    let status: CleanupItemStatus
    let detail: String
}

struct CleanupExecutionReport: Sendable {
    let outcomes: [CleanupItemOutcome]

    var movedCount: Int { outcomes.filter { $0.status == .moved }.count }
    var skippedCount: Int { outcomes.filter { $0.status == .skipped }.count }
    var failedCount: Int { outcomes.filter { $0.status == .failed }.count }
    var movedBytes: Int64 { outcomes.filter { $0.status == .moved }.reduce(0) { $0 + $1.byteCount } }
    var formattedMovedBytes: String {
        ByteCountFormatter.string(fromByteCount: movedBytes, countStyle: .file)
    }
}

/// Executes individually approved candidates. Every file is revalidated immediately before
/// FileManager moves that exact regular file to macOS Trash. No recursive or permanent delete exists.
struct CleanupExecutor: Sendable {
    let safetyPolicy: SafetyPolicy
    let rules: CleanupRules
    let trashMover: TrashMoving

    init(
        safetyPolicy: SafetyPolicy = SafetyPolicy(),
        rules: CleanupRules = .standard,
        trashMover: TrashMoving = FileManagerTrashMover()
    ) {
        self.safetyPolicy = safetyPolicy
        self.rules = rules
        self.trashMover = trashMover
    }

    func execute(_ selected: [CleanupCandidate], under root: URL, now: Date = Date()) throws -> CleanupExecutionReport {
        guard case .allowed = safetyPolicy.validateCleanupRoot(root) else {
            if case .blocked(let reason) = safetyPolicy.validateCleanupRoot(root) {
                throw CleanupEngineError.blocked(reason)
            }
            throw CleanupEngineError.blocked("This cleanup location is not approved.")
        }
        guard !selected.isEmpty else { throw CleanupEngineError.emptySelection }
        guard selected.count <= rules.maximumItemsPerBatch else {
            throw CleanupEngineError.batchLimit(rules.maximumItemsPerBatch)
        }

        let cutoff = now.addingTimeInterval(-Double(max(1, rules.minimumAgeDays)) * 24 * 60 * 60)
        var outcomes: [CleanupItemOutcome] = []

        for candidate in selected {
            let fileURL = URL(fileURLWithPath: candidate.path, isDirectory: false).standardizedFileURL
            if case .blocked(let reason) = safetyPolicy.validateCleanupTarget(fileURL, under: root) {
                outcomes.append(CleanupItemOutcome(
                    id: candidate.id, name: candidate.name, byteCount: candidate.byteCount,
                    status: .skipped, detail: reason
                ))
                continue
            }

            do {
                // Coordinate the move with other file presenters, then revalidate identity
                // inside the coordinated accessor immediately before invoking the Trash API.
                let coordinator = NSFileCoordinator(filePresenter: nil)
                var coordinationError: NSError?
                var itemResult: Result<Void, Error>?
                coordinator.coordinate(writingItemAt: fileURL, options: .forMoving, error: &coordinationError) { coordinatedURL in
                    do {
                        if case .blocked(let reason) = safetyPolicy.validateCleanupTarget(coordinatedURL, under: root) {
                            throw CleanupEngineError.blocked(reason)
                        }
                        let current = try CleanupFileFingerprint.read(from: coordinatedURL)
                        guard current == candidate.fingerprint,
                              current.linkCount == 1,
                              current.size == candidate.byteCount,
                              current.size >= rules.minimumFileSizeBytes,
                              Date(timeIntervalSince1970: Double(current.modifiedSeconds) + Double(current.modifiedNanoseconds) / 1_000_000_000) <= cutoff,
                              !coordinatedURL.lastPathComponent.hasPrefix("."),
                              !rules.excludesExtension(coordinatedURL.pathExtension),
                              !rules.excludesPath(coordinatedURL.path) else {
                            throw CleanupEngineError.staleFile(candidate.name)
                        }
                        try trashMover.moveToTrash(coordinatedURL)
                        itemResult = .success(())
                    } catch {
                        itemResult = .failure(error)
                    }
                }
                if let coordinationError { throw coordinationError }
                guard let itemResult else {
                    throw CleanupEngineError.unreadable("macOS did not complete the coordinated file operation.")
                }
                switch itemResult {
                case .success:
                    outcomes.append(CleanupItemOutcome(
                        id: candidate.id, name: candidate.name, byteCount: candidate.byteCount,
                        status: .moved, detail: "Moved to macOS Trash."
                    ))
                case .failure(let error):
                    let isSkipped: Bool
                    if let cleanupError = error as? CleanupEngineError {
                        switch cleanupError {
                        case .blocked, .staleFile, .fileUnavailable, .notRegularFile: isSkipped = true
                        default: isSkipped = false
                        }
                    } else {
                        isSkipped = false
                    }
                    outcomes.append(CleanupItemOutcome(
                        id: candidate.id, name: candidate.name, byteCount: candidate.byteCount,
                        status: isSkipped ? .skipped : .failed,
                        detail: error.localizedDescription
                    ))
                }
            } catch {
                outcomes.append(CleanupItemOutcome(
                    id: candidate.id, name: candidate.name, byteCount: candidate.byteCount,
                    status: .failed, detail: error.localizedDescription
                ))
            }
        }

        return CleanupExecutionReport(outcomes: outcomes)
    }
}
