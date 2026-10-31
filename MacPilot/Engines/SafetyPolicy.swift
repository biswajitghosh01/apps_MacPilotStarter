import Foundation
import Darwin

enum ScanDecision: Equatable {
    case allowed
    case blocked(String)
}

/// Central path policy shared by the read-only analyser and cleanup engine.
/// Cleanup is deliberately narrower than analysis: only user Caches and Logs are eligible.
struct SafetyPolicy: Sendable {
    private let homeDirectory: URL

    init(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.homeDirectory = homeDirectory.standardizedFileURL
    }

    var cachesRoot: URL {
        homeDirectory.appendingPathComponent("Library/Caches", isDirectory: true)
    }

    var logsRoot: URL {
        homeDirectory.appendingPathComponent("Library/Logs", isDirectory: true)
    }

    var permittedScanRoots: [URL] {
        [cachesRoot, logsRoot]
    }

    var protectedPathsForDisplay: [String] {
        [
            "/System", "/usr", "/bin", "/sbin", "/private", "/Library",
            "/System/Applications", "/Applications/Utilities and nested application folders",
            "Apple application bundles (com.apple.*)", "~/Library/Keychains", "~/Library/Preferences",
            "~/Library/Containers", "~/Library/Group Containers", "~/.Trash"
        ]
    }

    func validateReadOnlyScanRoot(_ url: URL) -> ScanDecision {
        guard url.isFileURL else { return .blocked("Only local folders can be scanned.") }

        let target = url.standardizedFileURL.path
        guard !target.isEmpty, target != "/" else {
            return .blocked("The filesystem root is protected.")
        }

        if containsSymbolicLinkInPath(url.standardizedFileURL) {
            return .blocked("Folders containing symbolic links are not scanned.")
        }

        let permitted = permittedScanRoots.contains {
            isSameOrDescendant(target, of: $0.standardizedFileURL.path)
        }
        guard permitted else {
            return .blocked("Storage analysis is limited to the user's Caches and Logs folders. Trash is not a scan location.")
        }

        let protectedAbsoluteRoots = ["/System", "/usr", "/bin", "/sbin", "/private", "/Library", "/Applications", "/Volumes"]
        if protectedAbsoluteRoots.contains(where: { isSameOrDescendant(target, of: $0) }) {
            return .blocked("This location is protected by MacPilot's safety policy.")
        }

        let protectedHomeRoots = [
            homeDirectory.appendingPathComponent("Library/Keychains").path,
            homeDirectory.appendingPathComponent("Library/Preferences").path,
            homeDirectory.appendingPathComponent("Library/Containers").path,
            homeDirectory.appendingPathComponent("Library/Group Containers").path
        ]
        if protectedHomeRoots.contains(where: { isSameOrDescendant(target, of: $0) }) {
            return .blocked("This user data location is protected by MacPilot's safety policy.")
        }

        return .allowed
    }

    /// The cleanup root must be within Caches or Logs. Trash is never a cleanup source.
    func validateCleanupRoot(_ url: URL) -> ScanDecision {
        guard case .allowed = validateReadOnlyScanRoot(url) else {
            if case .blocked(let reason) = validateReadOnlyScanRoot(url) { return .blocked(reason) }
            return .blocked("This cleanup location is not approved.")
        }

        let target = url.standardizedFileURL.path
        guard let approvedBase = cleanupBase(for: target) else {
            return .blocked("Cleanup is limited to user-level Caches and Logs. Trash and all other locations are excluded.")
        }

        var info = stat()
        let status = target.withCString { lstat($0, &info) }
        guard status == 0, (info.st_mode & S_IFMT) == S_IFDIR else {
            return .blocked("The cleanup root is unavailable or is not a real directory.")
        }
        guard let baseDevice = deviceNumber(at: approvedBase), info.st_dev == baseDevice else {
            return .blocked("Mounted volumes or redirected folders beneath Caches or Logs are excluded.")
        }
        let rootValues = try? url.resourceValues(forKeys: [.isPackageKey])
        if rootValues?.isPackage == true {
            return .blocked("Application packages and bundle folders are not cleanup roots.")
        }
        return .allowed
    }

    /// Validates a single file immediately before a cleanup operation.
    func validateCleanupTarget(_ fileURL: URL, under rootURL: URL) -> ScanDecision {
        guard case .allowed = validateCleanupRoot(rootURL) else {
            if case .blocked(let reason) = validateCleanupRoot(rootURL) { return .blocked(reason) }
            return .blocked("The cleanup root is not approved.")
        }

        guard fileURL.isFileURL else { return .blocked("Only local files can be moved to Trash.") }
        let rootPath = rootURL.standardizedFileURL.path
        let filePath = fileURL.standardizedFileURL.path
        guard filePath != rootPath, isSameOrDescendant(filePath, of: rootPath) else {
            return .blocked("The file is outside the selected cleanup folder.")
        }
        guard !containsSymbolicLinkInPath(fileURL.standardizedFileURL) else {
            return .blocked("Files reached through symbolic links are not eligible for cleanup.")
        }

        var rootInfo = stat()
        let rootStatus = rootPath.withCString { lstat($0, &rootInfo) }
        var info = stat()
        let status = filePath.withCString { lstat($0, &info) }
        guard rootStatus == 0, status == 0, (info.st_mode & S_IFMT) == S_IFREG else {
            return .blocked("Only existing regular files can be moved to Trash. Folders and special files are excluded.")
        }
        guard info.st_dev == rootInfo.st_dev else {
            return .blocked("Files on a mounted volume beneath the selected folder are excluded.")
        }
        guard info.st_uid == getuid() else {
            return .blocked("Files not owned by the current user are excluded.")
        }
        guard (info.st_mode & 0o111) == 0 else {
            return .blocked("Executable files are excluded from cleanup.")
        }
        guard info.st_nlink == 1 else {
            return .blocked("Files with multiple hard links are excluded.")
        }
        return .allowed
    }

    func isSameOrDescendant(_ candidate: String, of root: String) -> Bool {
        let normalizedRoot = root.hasSuffix("/") ? String(root.dropLast()) : root
        return candidate == normalizedRoot || candidate.hasPrefix(normalizedRoot + "/")
    }

    private func cleanupBase(for candidatePath: String) -> URL? {
        [cachesRoot, logsRoot].first {
            isSameOrDescendant(candidatePath, of: $0.standardizedFileURL.path)
        }
    }

    private func deviceNumber(at url: URL) -> dev_t? {
        var info = stat()
        let status = url.standardizedFileURL.path.withCString { lstat($0, &info) }
        guard status == 0, (info.st_mode & S_IFMT) == S_IFDIR else { return nil }
        return info.st_dev
    }

    private func containsSymbolicLinkInPath(_ url: URL) -> Bool {
        var current = URL(fileURLWithPath: "/", isDirectory: true)
        for component in url.pathComponents.dropFirst() {
            current.appendPathComponent(component)
            var info = stat()
            let result = current.path.withCString { lstat($0, &info) }
            if result == 0 && (info.st_mode & S_IFMT) == S_IFLNK {
                return true
            }
        }
        return false
    }
}
