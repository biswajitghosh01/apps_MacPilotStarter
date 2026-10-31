import Foundation

struct ScanFileEntry: Identifiable, Sendable, Equatable {
    let path: String
    let name: String
    let relativePath: String
    let byteCount: Int64
    let fileType: String
    let modifiedAt: Date?

    var id: String { path }

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file)
    }
}

struct ScanExtensionSummary: Identifiable, Sendable, Equatable {
    let fileType: String
    let fileCount: Int
    let byteCount: Int64

    var id: String { fileType }

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file)
    }
}

struct ScanResult: Sendable {
    let rootPath: String
    let fileCount: Int
    let directoryCount: Int
    let skippedCount: Int
    let totalBytes: Int64
    let largestFiles: [ScanFileEntry]
    let extensionSummaries: [ScanExtensionSummary]
    let wasTruncated: Bool
    let finishedAt: Date

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
    }

    var rootName: String {
        URL(fileURLWithPath: rootPath, isDirectory: true).lastPathComponent
    }
}

enum ScanError: LocalizedError {
    case blocked(String)
    case unreadable(String)

    var errorDescription: String? {
        switch self {
        case .blocked(let reason): return reason
        case .unreadable(let reason): return reason
        }
    }
}

/// Read-only scanner. It reads filesystem metadata only; it never opens file contents,
/// changes metadata, moves items or deletes anything.
struct ReadOnlyScanner {
    let safetyPolicy: SafetyPolicy
    private let maximumEntries: Int
    private let maximumLargestFiles: Int
    private let maximumExtensionGroups: Int

    init(
        safetyPolicy: SafetyPolicy = SafetyPolicy(),
        maximumEntries: Int = 250_000,
        maximumLargestFiles: Int = 20,
        maximumExtensionGroups: Int = 12
    ) {
        self.safetyPolicy = safetyPolicy
        self.maximumEntries = max(1, maximumEntries)
        self.maximumLargestFiles = max(1, maximumLargestFiles)
        self.maximumExtensionGroups = max(1, maximumExtensionGroups)
    }

    func scan(_ root: URL) throws -> ScanResult {
        switch safetyPolicy.validateReadOnlyScanRoot(root) {
        case .allowed:
            break
        case .blocked(let reason):
            throw ScanError.blocked(reason)
        }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw ScanError.unreadable("The selected folder does not exist or is not a directory.")
        }

        let keys: [URLResourceKey] = [
            .isRegularFileKey,
            .isDirectoryKey,
            .isSymbolicLinkKey,
            .fileSizeKey,
            .contentModificationDateKey,
            .nameKey
        ]

        var enumerationErrors = 0
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: keys,
            options: [.skipsPackageDescendants],
            errorHandler: { _, _ in
                enumerationErrors += 1
                return true
            }
        ) else {
            throw ScanError.unreadable("MacPilot could not read this folder. Check its permission and try again.")
        }

        let normalizedRoot = root.standardizedFileURL
        var fileCount = 0
        var directoryCount = 0
        var skippedCount = 0
        var totalBytes: Int64 = 0
        var visitedCount = 0
        var wasTruncated = false
        var largestFiles: [ScanFileEntry] = []
        var extensionTotals: [String: (count: Int, bytes: Int64)] = [:]

        while let item = enumerator.nextObject() as? URL {
            visitedCount += 1
            if visitedCount > maximumEntries {
                skippedCount += 1
                wasTruncated = true
                enumerator.skipDescendants()
                break
            }

            do {
                let values = try item.resourceValues(forKeys: Set(keys))

                // Never follow or report symbolic links as eligible scan entries.
                if values.isSymbolicLink == true {
                    skippedCount += 1
                    enumerator.skipDescendants()
                    continue
                }

                if values.isDirectory == true {
                    directoryCount += 1
                    continue
                }

                guard values.isRegularFile == true else {
                    skippedCount += 1
                    continue
                }

                let size = Int64(max(0, values.fileSize ?? 0))
                let fileName = values.name ?? item.lastPathComponent
                let fileType = Self.normalizedFileType(for: item)
                let relativePath = Self.relativePath(of: item, below: normalizedRoot)
                let entry = ScanFileEntry(
                    path: item.path,
                    name: fileName,
                    relativePath: relativePath,
                    byteCount: size,
                    fileType: fileType,
                    modifiedAt: values.contentModificationDate
                )

                fileCount += 1
                totalBytes += size

                let current = extensionTotals[fileType] ?? (count: 0, bytes: 0)
                extensionTotals[fileType] = (count: current.count + 1, bytes: current.bytes + size)
                insertLargest(entry, into: &largestFiles)
            } catch {
                skippedCount += 1
            }
        }

        skippedCount += enumerationErrors

        let sortedSummaries = extensionTotals
            .map { ScanExtensionSummary(fileType: $0.key, fileCount: $0.value.count, byteCount: $0.value.bytes) }
            .sorted {
                if $0.byteCount == $1.byteCount { return $0.fileType.localizedCaseInsensitiveCompare($1.fileType) == .orderedAscending }
                return $0.byteCount > $1.byteCount
            }

        let summaries: [ScanExtensionSummary]
        if sortedSummaries.count > maximumExtensionGroups {
            let visibleCount = max(0, maximumExtensionGroups - 1)
            let visible = Array(sortedSummaries.prefix(visibleCount))
            let remainder = sortedSummaries.dropFirst(visibleCount)
            let otherCount = remainder.reduce(0) { $0 + $1.fileCount }
            let otherBytes = remainder.reduce(Int64(0)) { $0 + $1.byteCount }
            summaries = visible + [ScanExtensionSummary(fileType: "Other file types", fileCount: otherCount, byteCount: otherBytes)]
        } else {
            summaries = sortedSummaries
        }

        return ScanResult(
            rootPath: normalizedRoot.path,
            fileCount: fileCount,
            directoryCount: directoryCount,
            skippedCount: skippedCount,
            totalBytes: totalBytes,
            largestFiles: largestFiles,
            extensionSummaries: summaries,
            wasTruncated: wasTruncated,
            finishedAt: Date()
        )
    }

    private func insertLargest(_ entry: ScanFileEntry, into entries: inout [ScanFileEntry]) {
        guard maximumLargestFiles > 0 else { return }
        if entries.count < maximumLargestFiles {
            entries.append(entry)
        } else if let smallestIndex = entries.indices.min(by: { entries[$0].byteCount < entries[$1].byteCount }),
                  entry.byteCount > entries[smallestIndex].byteCount {
            entries[smallestIndex] = entry
        }
        entries.sort { $0.byteCount > $1.byteCount }
    }

    private static func normalizedFileType(for url: URL) -> String {
        let ext = url.pathExtension.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return ext.isEmpty ? "No extension" : ".\(ext)"
    }

    private static func relativePath(of url: URL, below root: URL) -> String {
        let rootPath = root.path.hasSuffix("/") ? root.path : root.path + "/"
        let itemPath = url.standardizedFileURL.path
        guard itemPath.hasPrefix(rootPath) else { return url.lastPathComponent }
        return String(itemPath.dropFirst(rootPath.count))
    }
}
