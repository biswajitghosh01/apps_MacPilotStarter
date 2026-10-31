import Foundation
import AppKit
import Darwin

// MARK: - Application inventory models

struct ApplicationBundleFingerprint: Equatable, Sendable {
    let device: UInt64
    let inode: UInt64
    let modifiedSeconds: Int64
    let modifiedNanoseconds: Int64
    let infoDevice: UInt64
    let infoInode: UInt64
    let infoSize: Int64
    let infoModifiedSeconds: Int64
    let infoModifiedNanoseconds: Int64
    let executableDevice: UInt64
    let executableInode: UInt64
    let executableSize: Int64
    let executableModifiedSeconds: Int64
    let executableModifiedNanoseconds: Int64

    static func read(from bundleURL: URL) throws -> ApplicationBundleFingerprint {
        let standardized = bundleURL.standardizedFileURL
        let infoURL = standardized.appendingPathComponent("Contents/Info.plist")

        var bundleInfo = stat()
        guard standardized.path.withCString({ lstat($0, &bundleInfo) }) == 0,
              (bundleInfo.st_mode & S_IFMT) == S_IFDIR else {
            throw ApplicationManagerError.applicationUnavailable(standardized.lastPathComponent)
        }

        let contentsURL = standardized.appendingPathComponent("Contents", isDirectory: true)
        var contentsInfo = stat()
        guard contentsURL.path.withCString({ lstat($0, &contentsInfo) }) == 0,
              (contentsInfo.st_mode & S_IFMT) == S_IFDIR,
              contentsInfo.st_dev == bundleInfo.st_dev else {
            throw ApplicationManagerError.invalidApplicationBundle(standardized.lastPathComponent)
        }

        var plistInfo = stat()
        guard infoURL.path.withCString({ lstat($0, &plistInfo) }) == 0,
              (plistInfo.st_mode & S_IFMT) == S_IFREG,
              plistInfo.st_dev == bundleInfo.st_dev else {
            throw ApplicationManagerError.invalidApplicationBundle(standardized.lastPathComponent)
        }

        guard let bundle = Bundle(url: standardized),
              let executableName = bundle.infoDictionary?["CFBundleExecutable"] as? String,
              !executableName.isEmpty,
              !executableName.contains("/"),
              executableName != ".",
              executableName != ".." else {
            throw ApplicationManagerError.invalidApplicationBundle(standardized.lastPathComponent)
        }
        let macOSContentsURL = contentsURL.appendingPathComponent("MacOS", isDirectory: true)
        let executableURL = macOSContentsURL.appendingPathComponent(executableName, isDirectory: false)
        var macOSContentsInfo = stat()
        var executableInfo = stat()
        guard macOSContentsURL.path.withCString({ lstat($0, &macOSContentsInfo) }) == 0,
              (macOSContentsInfo.st_mode & S_IFMT) == S_IFDIR,
              macOSContentsInfo.st_dev == bundleInfo.st_dev,
              executableURL.path.withCString({ lstat($0, &executableInfo) }) == 0,
              (executableInfo.st_mode & S_IFMT) == S_IFREG,
              executableInfo.st_dev == bundleInfo.st_dev else {
            throw ApplicationManagerError.invalidApplicationBundle(standardized.lastPathComponent)
        }

        let bundleModified = bundleInfo.st_mtimespec
        let plistModified = plistInfo.st_mtimespec
        let executableModified = executableInfo.st_mtimespec
        return ApplicationBundleFingerprint(
            device: UInt64(bundleInfo.st_dev),
            inode: UInt64(bundleInfo.st_ino),
            modifiedSeconds: Int64(bundleModified.tv_sec),
            modifiedNanoseconds: Int64(bundleModified.tv_nsec),
            infoDevice: UInt64(plistInfo.st_dev),
            infoInode: UInt64(plistInfo.st_ino),
            infoSize: Int64(plistInfo.st_size),
            infoModifiedSeconds: Int64(plistModified.tv_sec),
            infoModifiedNanoseconds: Int64(plistModified.tv_nsec),
            executableDevice: UInt64(executableInfo.st_dev),
            executableInode: UInt64(executableInfo.st_ino),
            executableSize: Int64(executableInfo.st_size),
            executableModifiedSeconds: Int64(executableModified.tv_sec),
            executableModifiedNanoseconds: Int64(executableModified.tv_nsec)
        )
    }
}

struct InstalledApplication: Identifiable, Sendable {
    let path: String
    let displayName: String
    let bundleIdentifier: String?
    let version: String
    let byteCount: Int64
    let sizeIsLowerBound: Bool
    let estimatedEntries: Int
    let removalBlockReason: String?
    let fingerprint: ApplicationBundleFingerprint?

    var id: String { path }
    var url: URL { URL(fileURLWithPath: path, isDirectory: true) }
    var formattedSize: String {
        if sizeIsLowerBound && estimatedEntries == 0 { return "Size not estimated (scan budget)" }
        let size = ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file)
        return sizeIsLowerBound ? "At least \(size)" : size
    }
    var canMoveToTrash: Bool { removalBlockReason == nil && fingerprint != nil }
}

struct ApplicationInventoryResult: Sendable {
    let rootPath: String
    let applications: [InstalledApplication]
    let skippedCount: Int
    let wasTruncated: Bool
    let finishedAt: Date
}

enum ApplicationManagerError: LocalizedError {
    case blocked(String)
    case unreadable(String)
    case applicationUnavailable(String)
    case invalidApplicationBundle(String)
    case staleApplication(String)
    case noSelection

    var errorDescription: String? {
        switch self {
        case .blocked(let message), .unreadable(let message): return message
        case .applicationUnavailable(let name): return "\(name) is no longer available. Scan again."
        case .invalidApplicationBundle(let name): return "\(name) is not a valid macOS application bundle."
        case .staleApplication(let name): return "\(name) changed after the preview. Scan again before removing it."
        case .noSelection: return "Select an application first."
        }
    }
}

// MARK: - Application-specific safety policy

/// Allows inventory only in the two standard user-facing Applications folders.
/// System-managed application locations such as /System/Applications are never accepted.
struct ApplicationSafetyPolicy: Sendable {
    private let homeDirectory: URL
    private let systemApplicationsDirectory: URL

    init(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        systemApplicationsDirectory: URL = URL(fileURLWithPath: "/Applications", isDirectory: true)
    ) {
        self.homeDirectory = homeDirectory.standardizedFileURL
        self.systemApplicationsDirectory = systemApplicationsDirectory.standardizedFileURL
    }

    var allowedRoots: [URL] {
        [
            systemApplicationsDirectory,
            homeDirectory.appendingPathComponent("Applications", isDirectory: true)
        ]
    }

    func validateSelectedRoot(_ root: URL) -> ScanDecision {
        guard root.isFileURL else { return .blocked("Choose a local Applications folder.") }
        let standardized = root.standardizedFileURL
        guard allowedRoots.contains(where: { $0.standardizedFileURL.path == standardized.path }) else {
            return .blocked("Choose exactly /Applications or your home folder's Applications directory. System application folders and nested folders are protected.")
        }
        guard !containsSymbolicLinkInPath(standardized) else {
            return .blocked("The selected Applications folder contains a symbolic link and cannot be used.")
        }

        var info = stat()
        guard standardized.path.withCString({ lstat($0, &info) }) == 0,
              (info.st_mode & S_IFMT) == S_IFDIR else {
            return .blocked("The selected Applications folder is unavailable or is not a real directory.")
        }
        return .allowed
    }

    func validateBundleContainer(_ bundleURL: URL, under root: URL) -> ScanDecision {
        guard case .allowed = validateSelectedRoot(root) else {
            if case .blocked(let reason) = validateSelectedRoot(root) { return .blocked(reason) }
            return .blocked("The Applications folder is not approved.")
        }

        let bundle = bundleURL.standardizedFileURL
        let rootURL = root.standardizedFileURL
        guard bundle.deletingLastPathComponent().standardizedFileURL.path == rootURL.path,
              bundle.pathExtension.lowercased() == "app",
              !bundle.lastPathComponent.hasPrefix(".") else {
            return .blocked("Only visible .app bundles directly inside the selected Applications folder are inventoried.")
        }
        guard !containsSymbolicLinkInPath(bundle) else {
            return .blocked("Application bundles reached through symbolic links are excluded.")
        }

        var rootInfo = stat()
        var bundleInfo = stat()
        guard rootURL.path.withCString({ lstat($0, &rootInfo) }) == 0,
              bundle.path.withCString({ lstat($0, &bundleInfo) }) == 0,
              (rootInfo.st_mode & S_IFMT) == S_IFDIR,
              (bundleInfo.st_mode & S_IFMT) == S_IFDIR,
              rootInfo.st_dev == bundleInfo.st_dev else {
            return .blocked("The application is not a real directory on the selected Applications volume.")
        }

        // Do not read Bundle metadata until Contents and Info.plist are confirmed to be
        // real, same-volume filesystem entries rather than symlink redirects.
        let contentsURL = bundle.appendingPathComponent("Contents", isDirectory: true)
        let infoURL = contentsURL.appendingPathComponent("Info.plist")
        var contentsInfo = stat()
        var plistInfo = stat()
        guard contentsURL.path.withCString({ lstat($0, &contentsInfo) }) == 0,
              (contentsInfo.st_mode & S_IFMT) == S_IFDIR,
              contentsInfo.st_dev == bundleInfo.st_dev,
              infoURL.path.withCString({ lstat($0, &plistInfo) }) == 0,
              (plistInfo.st_mode & S_IFMT) == S_IFREG,
              plistInfo.st_dev == bundleInfo.st_dev else {
            return .blocked("The application's Contents folder or Info.plist is unavailable or redirected.")
        }
        return .allowed
    }

    func validateBundleForInventory(_ bundleURL: URL, under root: URL, bundleIdentifier: String?) -> ScanDecision {
        let locationDecision = validateBundleContainer(bundleURL, under: root)
        guard case .allowed = locationDecision else { return locationDecision }

        guard let bundleIdentifier, !bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .blocked("The bundle identifier could not be read. This item is inventory-only.")
        }
        if bundleIdentifier.lowercased().hasPrefix("com.apple.") {
            return .blocked("Apple application bundles are protected by MacPilot.")
        }
        return .allowed
    }

    func validateBundleForRemoval(
        _ bundleURL: URL,
        under root: URL,
        bundleIdentifier: String?
    ) -> ScanDecision {
        let inventoryDecision = validateBundleForInventory(bundleURL, under: root, bundleIdentifier: bundleIdentifier)
        guard case .allowed = inventoryDecision else { return inventoryDecision }

        let rootPath = root.standardizedFileURL.path
        guard access(rootPath, W_OK | X_OK) == 0 else {
            return .blocked("macOS does not grant this user permission to move items from the selected folder. MacPilot will not request administrator privileges.")
        }

        let contentsURL = bundleURL.appendingPathComponent("Contents", isDirectory: true)
        let infoURL = contentsURL.appendingPathComponent("Info.plist")
        var contentsInfo = stat()
        var info = stat()
        guard contentsURL.path.withCString({ lstat($0, &contentsInfo) }) == 0,
              (contentsInfo.st_mode & S_IFMT) == S_IFDIR,
              infoURL.path.withCString({ lstat($0, &info) }) == 0,
              (info.st_mode & S_IFMT) == S_IFREG,
              contentsInfo.st_dev == info.st_dev else {
            return .blocked("The application's Contents folder or Info.plist is unavailable or redirected. This bundle cannot be safely identified.")
        }
        guard let currentBundle = Bundle(url: bundleURL),
              currentBundle.bundleIdentifier == bundleIdentifier,
              (currentBundle.infoDictionary?["CFBundlePackageType"] as? String) == "APPL" else {
            return .blocked("The application's bundle metadata changed or is not a standard application bundle.")
        }
        return .allowed
    }

    private func containsSymbolicLinkInPath(_ url: URL) -> Bool {
        var current = URL(fileURLWithPath: "/", isDirectory: true)
        for component in url.pathComponents.dropFirst() {
            current.appendPathComponent(component)
            var info = stat()
            let result = current.path.withCString { lstat($0, &info) }
            if result == 0 && (info.st_mode & S_IFMT) == S_IFLNK { return true }
        }
        return false
    }
}

// MARK: - Read-only application scanner

struct ApplicationInventoryScanner: Sendable {
    let policy: ApplicationSafetyPolicy
    let maximumApplications: Int
    let maximumEntriesPerBundle: Int
    let maximumTotalSizeEntries: Int

    init(
        policy: ApplicationSafetyPolicy = ApplicationSafetyPolicy(),
        maximumApplications: Int = 500,
        maximumEntriesPerBundle: Int = 5_000,
        maximumTotalSizeEntries: Int = 100_000
    ) {
        self.policy = policy
        self.maximumApplications = maximumApplications
        self.maximumEntriesPerBundle = maximumEntriesPerBundle
        self.maximumTotalSizeEntries = maximumTotalSizeEntries
    }

    func scan(_ root: URL, now: Date = Date()) throws -> ApplicationInventoryResult {
        guard case .allowed = policy.validateSelectedRoot(root) else {
            if case .blocked(let reason) = policy.validateSelectedRoot(root) {
                throw ApplicationManagerError.blocked(reason)
            }
            throw ApplicationManagerError.blocked("The selected Applications folder is not approved.")
        }

        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey, .isHiddenKey, .isPackageKey]
        let children: [URL]
        do {
            children = try FileManager.default.contentsOfDirectory(
                at: root.standardizedFileURL,
                includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles]
            )
        } catch {
            throw ApplicationManagerError.unreadable("MacPilot could not read the selected folder. Check the folder permission and try again.")
        }

        var applications: [InstalledApplication] = []
        var skipped = 0
        var truncated = false
        var remainingSizeEntries = max(0, maximumTotalSizeEntries)

        for child in children.sorted(by: { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }) {
            guard child.pathExtension.lowercased() == "app" else { continue }
            if applications.count >= maximumApplications {
                truncated = true
                break
            }

            do {
                let values = try child.resourceValues(forKeys: Set(keys))
                guard values.isDirectory == true, values.isSymbolicLink != true,
                      case .allowed = policy.validateBundleContainer(child, under: root) else {
                    skipped += 1
                    continue
                }
                guard let bundle = Bundle(url: child) else {
                    skipped += 1
                    continue
                }

                let info = bundle.infoDictionary ?? [:]
                guard (info["CFBundlePackageType"] as? String) == "APPL" else {
                    skipped += 1
                    continue
                }
                let bundleID = bundle.bundleIdentifier
                let displayName = (info["CFBundleDisplayName"] as? String)
                    ?? (info["CFBundleName"] as? String)
                    ?? child.deletingPathExtension().lastPathComponent
                let version = (info["CFBundleShortVersionString"] as? String)
                    ?? (info["CFBundleVersion"] as? String)
                    ?? "Unknown"

                let decision = policy.validateBundleForRemoval(child, under: root, bundleIdentifier: bundleID)
                let reason: String?
                if case .blocked(let message) = decision { reason = message } else { reason = nil }
                let fingerprint = try? ApplicationBundleFingerprint.read(from: child)
                let perBundleBudget = min(max(0, maximumEntriesPerBundle), remainingSizeEntries)
                let footprint = estimateBundleSize(child, maximumEntries: perBundleBudget)
                remainingSizeEntries = max(0, remainingSizeEntries - footprint.visited)

                applications.append(InstalledApplication(
                    path: child.standardizedFileURL.path,
                    displayName: displayName,
                    bundleIdentifier: bundleID,
                    version: version,
                    byteCount: footprint.bytes,
                    sizeIsLowerBound: footprint.truncated,
                    estimatedEntries: footprint.visited,
                    removalBlockReason: (reason == nil && fingerprint == nil)
                        ? "The application bundle could not be fingerprinted safely."
                        : reason,
                    fingerprint: fingerprint
                ))
            } catch {
                skipped += 1
            }
        }

        return ApplicationInventoryResult(
            rootPath: root.standardizedFileURL.path,
            applications: applications,
            skippedCount: skipped,
            wasTruncated: truncated,
            finishedAt: now
        )
    }

    private func estimateBundleSize(_ bundleURL: URL, maximumEntries: Int) -> (bytes: Int64, visited: Int, truncated: Bool) {
        guard maximumEntries > 0 else { return (0, 0, true) }
        let keys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey]
        guard let enumerator = FileManager.default.enumerator(at: bundleURL, includingPropertiesForKeys: keys) else {
            return (0, 0, true)
        }

        var bytes: Int64 = 0
        var visited = 0
        var truncated = false
        while let item = enumerator.nextObject() as? URL {
            visited += 1
            if visited > maximumEntries {
                truncated = true
                enumerator.skipDescendants()
                break
            }
            do {
                let values = try item.resourceValues(forKeys: Set(keys))
                if values.isSymbolicLink == true {
                    enumerator.skipDescendants()
                    continue
                }
                if values.isRegularFile == true {
                    bytes += Int64(max(0, values.fileSize ?? 0))
                }
            } catch {
                // A size estimate is informational. An unreadable entry makes it a lower bound.
                truncated = true
            }
        }
        return (bytes, visited, truncated)
    }
}

// MARK: - Explicit app-bundle-to-Trash operation

#if !APP_STORE_EDITION
struct ApplicationUninstaller: Sendable {
    let policy: ApplicationSafetyPolicy
    let trashMover: TrashMoving

    init(policy: ApplicationSafetyPolicy = ApplicationSafetyPolicy(), trashMover: TrashMoving = FileManagerTrashMover()) {
        self.policy = policy
        self.trashMover = trashMover
    }

    /// Moves only the selected top-level .app bundle to macOS Trash. No associated data is removed.
    func moveToTrash(_ application: InstalledApplication, under root: URL) throws {
        let bundleURL = application.url
        guard case .allowed = policy.validateBundleForRemoval(
            bundleURL,
            under: root,
            bundleIdentifier: application.bundleIdentifier
        ) else {
            if case .blocked(let reason) = policy.validateBundleForRemoval(
                bundleURL,
                under: root,
                bundleIdentifier: application.bundleIdentifier
            ) { throw ApplicationManagerError.blocked(reason) }
            throw ApplicationManagerError.blocked("This application is not eligible for removal.")
        }

        guard let expected = application.fingerprint else {
            throw ApplicationManagerError.invalidApplicationBundle(application.displayName)
        }
        let current = try ApplicationBundleFingerprint.read(from: bundleURL)
        guard current == expected else {
            throw ApplicationManagerError.staleApplication(application.displayName)
        }

        if let bundleIdentifier = application.bundleIdentifier,
           NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).contains(where: { !$0.isTerminated }) {
            throw ApplicationManagerError.blocked("\(application.displayName) is currently running. Quit it before moving it to Trash.")
        }

        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        var operationError: Error?
        var didCoordinate = false
        coordinator.coordinate(writingItemAt: bundleURL, options: .forMoving, error: &coordinationError) { coordinatedURL in
            didCoordinate = true
            do {
                guard case .allowed = policy.validateBundleForRemoval(
                    coordinatedURL,
                    under: root,
                    bundleIdentifier: application.bundleIdentifier
                ) else {
                    throw ApplicationManagerError.blocked("The application path changed or is no longer approved.")
                }
                let rechecked = try ApplicationBundleFingerprint.read(from: coordinatedURL)
                guard rechecked == expected else {
                    throw ApplicationManagerError.staleApplication(application.displayName)
                }
                if let bundleIdentifier = application.bundleIdentifier,
                   NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).contains(where: { !$0.isTerminated }) {
                    throw ApplicationManagerError.blocked("\(application.displayName) started running again. Quit it and retry.")
                }
                try trashMover.moveToTrash(coordinatedURL)
            } catch {
                operationError = error
            }
        }

        if let coordinationError { throw coordinationError }
        guard didCoordinate else {
            throw ApplicationManagerError.unreadable("macOS did not complete the coordinated application move.")
        }
        if let operationError { throw operationError }
    }
}
#endif
