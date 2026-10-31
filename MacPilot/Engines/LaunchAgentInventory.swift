import Foundation

struct LaunchAgentRecord: Identifiable {
    let id: String
    let fileName: String
    let label: String
    let program: String
    let runsAtLoad: Bool
    let keepsAlive: Bool
}

struct LaunchAgentScanResult {
    let records: [LaunchAgentRecord]
    let skippedCount: Int
    let truncated: Bool
}

/// Inventory only. This scanner never loads, unloads, edits, disables or deletes jobs.
struct LaunchAgentInventory {
    static let maximumEntries = 500

    private let fileManager: FileManager
    private let homeDirectory: URL

    init(fileManager: FileManager = .default, homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.fileManager = fileManager
        self.homeDirectory = homeDirectory.standardizedFileURL
    }

    var permittedRoot: URL {
        homeDirectory.appendingPathComponent("Library/LaunchAgents", isDirectory: true).standardizedFileURL
    }

    func scan(_ selectedRoot: URL) throws -> LaunchAgentScanResult {
        let root = selectedRoot.standardizedFileURL
        guard root.path == permittedRoot.path else { throw LaunchAgentInventoryError.unapprovedRoot }

        var rootInfo = stat()
        guard lstat(root.path, &rootInfo) == 0, (rootInfo.st_mode & S_IFMT) == S_IFDIR else {
            throw LaunchAgentInventoryError.invalidRoot
        }

        let urls = try fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .isHiddenKey],
            options: [.skipsHiddenFiles]
        )
        let plistURLs = urls.filter { $0.pathExtension.lowercased() == "plist" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        let truncated = plistURLs.count > Self.maximumEntries
        let boundedURLs = Array(plistURLs.prefix(Self.maximumEntries))
        var records: [LaunchAgentRecord] = []
        var skipped = max(0, plistURLs.count - boundedURLs.count)

        for url in boundedURLs {
            do {
                let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .isHiddenKey])
                guard values.isRegularFile == true, values.isSymbolicLink != true, values.isHidden != true else {
                    skipped += 1
                    continue
                }
                let data = try Data(contentsOf: url, options: [.mappedIfSafe])
                let object = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
                guard let dictionary = object as? [String: Any],
                      let label = dictionary["Label"] as? String, !label.isEmpty else {
                    skipped += 1
                    continue
                }
                let arguments = dictionary["ProgramArguments"] as? [String]
                let program = (dictionary["Program"] as? String) ?? arguments?.first ?? "Not specified"
                let keepsAlive: Bool
                if let value = dictionary["KeepAlive"] as? Bool {
                    keepsAlive = value
                } else {
                    keepsAlive = dictionary["KeepAlive"] is [String: Any]
                }
                records.append(LaunchAgentRecord(
                    id: url.path,
                    fileName: url.lastPathComponent,
                    label: label,
                    program: program,
                    runsAtLoad: dictionary["RunAtLoad"] as? Bool ?? false,
                    keepsAlive: keepsAlive
                ))
            } catch {
                skipped += 1
            }
        }
        return LaunchAgentScanResult(records: records, skippedCount: skipped, truncated: truncated)
    }
}

enum LaunchAgentInventoryError: Error {
    case unapprovedRoot
    case invalidRoot
}
