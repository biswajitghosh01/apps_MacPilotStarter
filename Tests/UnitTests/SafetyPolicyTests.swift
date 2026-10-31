import XCTest
@testable import MacPilot

final class SafetyPolicyTests: XCTestCase {
    private var testHome: URL!
    private var policy: SafetyPolicy!

    override func setUpWithError() throws {
        try super.setUpWithError()
        // Keep the synthetic home under the current user's home directory instead of
        // FileManager.temporaryDirectory. The production policy intentionally checks
        // every path component for symlinks; macOS temporary paths may include system
        // symlink aliases such as /var. Using a home-based fixture tests the intended
        // allowlist behaviour without weakening that production guard.
        testHome = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("MacPilotSafetyTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: testHome, withIntermediateDirectories: true)
        policy = SafetyPolicy(homeDirectory: testHome)
        for root in policy.permittedScanRoots {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        }
    }

    override func tearDownWithError() throws {
        if let testHome { try? FileManager.default.removeItem(at: testHome) }
        try super.tearDownWithError()
    }

    func testAllowsOnlyApprovedUserCacheRoot() {
        let caches = testHome.appendingPathComponent("Library/Caches", isDirectory: true)
        XCTAssertEqual(policy.validateReadOnlyScanRoot(caches), .allowed)
    }

    func testBlocksSystemRoot() {
        guard case .blocked = policy.validateReadOnlyScanRoot(URL(fileURLWithPath: "/System", isDirectory: true)) else {
            return XCTFail("Expected /System to be blocked")
        }
    }

    func testBlocksUnapprovedUserLibraryFolder() {
        let preferences = testHome.appendingPathComponent("Library/Preferences", isDirectory: true)
        guard case .blocked = policy.validateReadOnlyScanRoot(preferences) else {
            return XCTFail("Expected Preferences to be blocked")
        }
    }

    func testBlocksFolderOutsideAllowlist() {
        let documents = testHome.appendingPathComponent("Documents", isDirectory: true)
        try? FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
        guard case .blocked = policy.validateReadOnlyScanRoot(documents) else {
            return XCTFail("Expected Documents to be blocked")
        }
    }

    func testBlocksSymlinkInsideAllowedRoot() throws {
        let caches = testHome.appendingPathComponent("Library/Caches", isDirectory: true)
        let outside = testHome.appendingPathComponent("Outside", isDirectory: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        let link = caches.appendingPathComponent("redirect", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)

        guard case .blocked = policy.validateReadOnlyScanRoot(link) else {
            return XCTFail("Expected symlink path to be blocked")
        }
    }

    func testScannerReadsMetadataWithoutChangingFiles() throws {
        let caches = testHome.appendingPathComponent("Library/Caches", isDirectory: true)
        let sample = caches.appendingPathComponent("sample.cache")
        let bytes = Data(repeating: 0x41, count: 4096)
        try bytes.write(to: sample)

        let result = try ReadOnlyScanner(safetyPolicy: policy).scan(caches)
        XCTAssertGreaterThanOrEqual(result.fileCount, 1)
        XCTAssertGreaterThanOrEqual(result.totalBytes, 4096)
        XCTAssertTrue(FileManager.default.fileExists(atPath: sample.path), "Read-only scan must not remove files")
        XCTAssertEqual(try Data(contentsOf: sample), bytes, "Read-only scan must not change file contents")
    }

    func testScannerReportsLargestFilesAndExtensionBreakdown() throws {
        let caches = testHome.appendingPathComponent("Library/Caches", isDirectory: true)
        let small = caches.appendingPathComponent("small.tmp")
        let large = caches.appendingPathComponent("large.log")
        try Data(repeating: 0x01, count: 128).write(to: small)
        try Data(repeating: 0x02, count: 2048).write(to: large)

        let result = try ReadOnlyScanner(safetyPolicy: policy).scan(caches)

        XCTAssertEqual(result.fileCount, 2)
        XCTAssertEqual(result.largestFiles.first?.name, "large.log")
        XCTAssertEqual(result.largestFiles.first?.byteCount, 2048)
        XCTAssertTrue(result.extensionSummaries.contains { $0.fileType == ".log" && $0.fileCount == 1 })
        XCTAssertTrue(result.extensionSummaries.contains { $0.fileType == ".tmp" && $0.fileCount == 1 })
    }

    func testScannerDoesNotFollowSymlinkEntries() throws {
        let caches = testHome.appendingPathComponent("Library/Caches", isDirectory: true)
        let outside = testHome.appendingPathComponent("Outside", isDirectory: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        let outsideFile = outside.appendingPathComponent("must-not-count.dat")
        try Data(repeating: 0x03, count: 8192).write(to: outsideFile)
        let link = caches.appendingPathComponent("redirect", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)

        let result = try ReadOnlyScanner(safetyPolicy: policy).scan(caches)

        XCTAssertEqual(result.fileCount, 0)
        XCTAssertEqual(result.totalBytes, 0)
        XCTAssertGreaterThanOrEqual(result.skippedCount, 1)
    }

    func testScannerMarksResultWhenEntryLimitIsReached() throws {
        let caches = testHome.appendingPathComponent("Library/Caches", isDirectory: true)
        try Data(repeating: 0x01, count: 16).write(to: caches.appendingPathComponent("one.tmp"))
        try Data(repeating: 0x02, count: 32).write(to: caches.appendingPathComponent("two.tmp"))

        let result = try ReadOnlyScanner(safetyPolicy: policy, maximumEntries: 1).scan(caches)

        XCTAssertTrue(result.wasTruncated)
    }
    func testCleanupAllowsCachesAndLogsButBlocksTrash() {
        let caches = testHome.appendingPathComponent("Library/Caches", isDirectory: true)
        let logs = testHome.appendingPathComponent("Library/Logs", isDirectory: true)
        let trash = testHome.appendingPathComponent(".Trash", isDirectory: true)
        XCTAssertEqual(policy.validateCleanupRoot(caches), .allowed)
        XCTAssertEqual(policy.validateCleanupRoot(logs), .allowed)
        guard case .blocked = policy.validateCleanupRoot(trash) else {
            return XCTFail("Trash must never be a cleanup source")
        }
    }

    func testCleanupScannerReturnsOnlyOldEligibleFiles() throws {
        let caches = testHome.appendingPathComponent("Library/Caches", isDirectory: true)
        let oldCache = caches.appendingPathComponent("old.cache")
        let recentCache = caches.appendingPathComponent("recent.cache")
        let oldDatabase = caches.appendingPathComponent("old.sqlite")
        try Data(repeating: 0x11, count: 4096).write(to: oldCache)
        try Data(repeating: 0x22, count: 4096).write(to: recentCache)
        try Data(repeating: 0x33, count: 4096).write(to: oldDatabase)

        let now = Date()
        let oldDate = now.addingTimeInterval(-60 * 24 * 60 * 60)
        try FileManager.default.setAttributes([.modificationDate: oldDate], ofItemAtPath: oldCache.path)
        try FileManager.default.setAttributes([.modificationDate: oldDate], ofItemAtPath: oldDatabase.path)

        let result = try CleanupCandidateScanner(safetyPolicy: policy).scan(caches, now: now)
        XCTAssertEqual(result.candidates.map(\.name), ["old.cache"])
        XCTAssertEqual(result.candidates.first?.byteCount, 4096)
        XCTAssertTrue(FileManager.default.fileExists(atPath: oldCache.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: recentCache.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: oldDatabase.path))
    }

    func testCleanupExecutorSkipsFileChangedAfterPreview() throws {
        let caches = testHome.appendingPathComponent("Library/Caches", isDirectory: true)
        let file = caches.appendingPathComponent("old.cache")
        try Data(repeating: 0x41, count: 4096).write(to: file)
        let oldDate = Date().addingTimeInterval(-60 * 24 * 60 * 60)
        try FileManager.default.setAttributes([.modificationDate: oldDate], ofItemAtPath: file.path)

        let scan = try CleanupCandidateScanner(safetyPolicy: policy).scan(caches)
        let candidate = try XCTUnwrap(scan.candidates.first)
        try Data(repeating: 0x42, count: 4096).write(to: file)

        let mover = RecordingTrashMover()
        let report = try CleanupExecutor(safetyPolicy: policy, trashMover: mover).execute([candidate], under: caches)

        XCTAssertEqual(report.movedCount, 0)
        XCTAssertEqual(report.skippedCount, 1)
        XCTAssertTrue(mover.movedPaths.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
    }

    func testCleanupExecutorMovesOnlyExplicitlySelectedCandidate() throws {
        let caches = testHome.appendingPathComponent("Library/Caches", isDirectory: true)
        let first = caches.appendingPathComponent("first.cache")
        let second = caches.appendingPathComponent("second.cache")
        try Data(repeating: 0x51, count: 2048).write(to: first)
        try Data(repeating: 0x52, count: 3072).write(to: second)
        let oldDate = Date().addingTimeInterval(-60 * 24 * 60 * 60)
        try FileManager.default.setAttributes([.modificationDate: oldDate], ofItemAtPath: first.path)
        try FileManager.default.setAttributes([.modificationDate: oldDate], ofItemAtPath: second.path)

        let scan = try CleanupCandidateScanner(safetyPolicy: policy).scan(caches)
        let explicitlySelected = try XCTUnwrap(scan.candidates.first(where: { $0.name == "first.cache" }))
        let mover = RecordingTrashMover()
        let report = try CleanupExecutor(safetyPolicy: policy, trashMover: mover).execute([explicitlySelected], under: caches)

        XCTAssertEqual(report.movedCount, 1)
        XCTAssertEqual(mover.movedPaths, [first.path])
        XCTAssertTrue(FileManager.default.fileExists(atPath: first.path), "The test mover records calls but does not alter fixture files")
        XCTAssertTrue(FileManager.default.fileExists(atPath: second.path), "Unselected items must remain untouched")
    }

    func testCleanupExecutorRejectsFileOutsideSelectedRoot() throws {
        let caches = testHome.appendingPathComponent("Library/Caches", isDirectory: true)
        let outside = testHome.appendingPathComponent("outside.cache")
        try Data(repeating: 0x61, count: 4096).write(to: outside)
        let date = Date().addingTimeInterval(-60 * 24 * 60 * 60)
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: outside.path)
        let fingerprint = try CleanupFileFingerprint.read(from: outside)
        let candidate = CleanupCandidate(
            path: outside.path, name: outside.lastPathComponent, relativePath: "../outside.cache",
            byteCount: fingerprint.size, modifiedAt: date, fingerprint: fingerprint
        )
        let mover = RecordingTrashMover()
        let report = try CleanupExecutor(safetyPolicy: policy, trashMover: mover).execute([candidate], under: caches)
        XCTAssertEqual(report.skippedCount, 1)
        XCTAssertTrue(mover.movedPaths.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: outside.path))
    }

    func testCleanupExecutorEnforcesBatchLimit() throws {
        let caches = testHome.appendingPathComponent("Library/Caches", isDirectory: true)
        let first = caches.appendingPathComponent("one.cache")
        let second = caches.appendingPathComponent("two.cache")
        try Data(repeating: 0x71, count: 2048).write(to: first)
        try Data(repeating: 0x72, count: 2048).write(to: second)
        let oldDate = Date().addingTimeInterval(-60 * 24 * 60 * 60)
        try FileManager.default.setAttributes([.modificationDate: oldDate], ofItemAtPath: first.path)
        try FileManager.default.setAttributes([.modificationDate: oldDate], ofItemAtPath: second.path)
        let rules = CleanupRules(minimumAgeDays: 30, minimumFileSizeBytes: 1024, maximumScanEntries: 200, maximumCandidates: 20, maximumItemsPerBatch: 1)
        let scan = try CleanupCandidateScanner(safetyPolicy: policy, rules: rules).scan(caches)
        let mover = RecordingTrashMover()
        XCTAssertThrowsError(try CleanupExecutor(safetyPolicy: policy, rules: rules, trashMover: mover).execute(scan.candidates, under: caches))
        XCTAssertTrue(mover.movedPaths.isEmpty)
    }

    func testCleanupScannerSkipsExecutableFiles() throws {
        let caches = testHome.appendingPathComponent("Library/Caches", isDirectory: true)
        let executable = caches.appendingPathComponent("old-tool")
        try Data(repeating: 0x91, count: 4096).write(to: executable)
        let oldDate = Date().addingTimeInterval(-60 * 24 * 60 * 60)
        try FileManager.default.setAttributes([.modificationDate: oldDate, .posixPermissions: 0o755], ofItemAtPath: executable.path)

        let result = try CleanupCandidateScanner(safetyPolicy: policy).scan(caches)
        XCTAssertTrue(result.candidates.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: executable.path))
    }

    func testCleanupScannerSkipsHardLinkedFiles() throws {
        let caches = testHome.appendingPathComponent("Library/Caches", isDirectory: true)
        let file = caches.appendingPathComponent("linked.cache")
        let secondName = caches.appendingPathComponent("linked-copy.cache")
        try Data(repeating: 0x81, count: 4096).write(to: file)
        try FileManager.default.linkItem(at: file, to: secondName)
        let oldDate = Date().addingTimeInterval(-60 * 24 * 60 * 60)
        try FileManager.default.setAttributes([.modificationDate: oldDate], ofItemAtPath: file.path)

        let result = try CleanupCandidateScanner(safetyPolicy: policy).scan(caches)
        XCTAssertTrue(result.candidates.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: secondName.path))
    }

}


private final class RecordingTrashMover: TrashMoving, @unchecked Sendable {
    private(set) var movedPaths: [String] = []

    func moveToTrash(_ url: URL) throws {
        movedPaths.append(url.path)
    }
}
