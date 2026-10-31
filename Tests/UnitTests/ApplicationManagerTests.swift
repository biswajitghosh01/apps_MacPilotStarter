import XCTest
@testable import MacPilot

final class ApplicationManagerTests: XCTestCase {
    private var testHome: URL!
    private var applicationsRoot: URL!
    private var systemAppsRoot: URL!
    private var policy: ApplicationSafetyPolicy!

    override func setUpWithError() throws {
        try super.setUpWithError()
        testHome = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("MacPilotApplicationTests-\(UUID().uuidString)", isDirectory: true)
        applicationsRoot = testHome.appendingPathComponent("Applications", isDirectory: true)
        systemAppsRoot = testHome.appendingPathComponent("SystemApplicationsFixture", isDirectory: true)
        try FileManager.default.createDirectory(at: applicationsRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: systemAppsRoot, withIntermediateDirectories: true)
        policy = ApplicationSafetyPolicy(
            homeDirectory: testHome,
            systemApplicationsDirectory: systemAppsRoot
        )
    }

    override func tearDownWithError() throws {
        if let testHome { try? FileManager.default.removeItem(at: testHome) }
        try super.tearDownWithError()
    }

    func testAllowsOnlyExactApplicationsRoots() {
        XCTAssertEqual(policy.validateSelectedRoot(applicationsRoot), .allowed)
        XCTAssertEqual(policy.validateSelectedRoot(systemAppsRoot), .allowed)

        let nested = applicationsRoot.appendingPathComponent("Utilities", isDirectory: true)
        try? FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        guard case .blocked = policy.validateSelectedRoot(nested) else {
            return XCTFail("Nested application folders must not be accepted as scan roots")
        }

        let systemLocation = URL(fileURLWithPath: "/System/Applications", isDirectory: true)
        guard case .blocked = ApplicationSafetyPolicy(homeDirectory: testHome).validateSelectedRoot(systemLocation) else {
            return XCTFail("System Applications must remain protected")
        }
    }

    func testScannerFindsOnlyTopLevelApplicationBundles() throws {
        _ = try makeApp(named: "Sample.app", bundleID: "com.example.sample", under: applicationsRoot)
        let nested = applicationsRoot.appendingPathComponent("Group", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        _ = try makeApp(named: "Nested.app", bundleID: "com.example.nested", under: nested)

        let result = try ApplicationInventoryScanner(policy: policy).scan(applicationsRoot)
        XCTAssertEqual(result.applications.map(\.displayName), ["Sample"])
        XCTAssertEqual(result.applications.first?.bundleIdentifier, "com.example.sample")
    }

    func testAppleBundleIsInventoryOnly() throws {
        _ = try makeApp(named: "AppleTool.app", bundleID: "com.apple.example", under: applicationsRoot)
        let result = try ApplicationInventoryScanner(policy: policy).scan(applicationsRoot)
        let app = try XCTUnwrap(result.applications.first)
        XCTAssertFalse(app.canMoveToTrash)
        XCTAssertTrue(app.removalBlockReason?.contains("Apple") == true)
    }

    func testScannerSkipsApplicationSymlink() throws {
        let real = try makeApp(named: "Real.app", bundleID: "com.example.real", under: applicationsRoot)
        let link = applicationsRoot.appendingPathComponent("Linked.app", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)

        let result = try ApplicationInventoryScanner(policy: policy).scan(applicationsRoot)
        XCTAssertEqual(result.applications.count, 1)
        XCTAssertEqual(result.applications.first?.displayName, "Real")
        XCTAssertGreaterThanOrEqual(result.skippedCount, 1)
    }

    func testScannerSkipsBundleWithRedirectedContentsDirectory() throws {
        let outsideContents = testHome.appendingPathComponent("OutsideContents", isDirectory: true)
        try FileManager.default.createDirectory(at: outsideContents, withIntermediateDirectories: true)
        let info: [String: Any] = [
            "CFBundleIdentifier": "com.vendor.redirected",
            "CFBundleName": "Redirected",
            "CFBundlePackageType": "APPL",
            "CFBundleExecutable": "fixture-executable",
            "CFBundleVersion": "1"
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try data.write(to: outsideContents.appendingPathComponent("Info.plist"))

        let maliciousBundle = applicationsRoot.appendingPathComponent("Redirected.app", isDirectory: true)
        try FileManager.default.createDirectory(at: maliciousBundle, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: maliciousBundle.appendingPathComponent("Contents", isDirectory: true),
            withDestinationURL: outsideContents
        )

        let result = try ApplicationInventoryScanner(policy: policy).scan(applicationsRoot)
        XCTAssertTrue(result.applications.isEmpty)
        XCTAssertGreaterThanOrEqual(result.skippedCount, 1)
    }

    func testUninstallerMovesOnlyExplicitlySelectedBundleToTrashMover() throws {
        let first = try makeApp(named: "First.app", bundleID: "com.vendor.first", under: applicationsRoot)
        let second = try makeApp(named: "Second.app", bundleID: "com.vendor.second", under: applicationsRoot)
        let result = try ApplicationInventoryScanner(policy: policy).scan(applicationsRoot)
        let selected = try XCTUnwrap(result.applications.first { $0.path == first.path })
        let mover = RecordingApplicationTrashMover()

        try ApplicationUninstaller(policy: policy, trashMover: mover).moveToTrash(selected, under: applicationsRoot)

        XCTAssertEqual(mover.movedPaths, [first.path])
        XCTAssertTrue(FileManager.default.fileExists(atPath: first.path), "The test mover records the request and does not alter the fixture")
        XCTAssertTrue(FileManager.default.fileExists(atPath: second.path), "Unselected applications must remain untouched")
    }

    func testUninstallerRejectsApplicationChangedAfterPreview() throws {
        let appURL = try makeApp(named: "Changing.app", bundleID: "com.vendor.changing", under: applicationsRoot)
        let result = try ApplicationInventoryScanner(policy: policy).scan(applicationsRoot)
        let selected = try XCTUnwrap(result.applications.first)

        let infoURL = appURL.appendingPathComponent("Contents/Info.plist")
        let replacement: [String: Any] = [
            "CFBundleIdentifier": "com.vendor.changing",
            "CFBundleName": "Changing",
            "CFBundlePackageType": "APPL",
            "CFBundleExecutable": "fixture-executable",
            "CFBundleInfoDictionaryVersion": "6.0",
            "CFBundleVersion": "2"
        ]
        try PropertyListSerialization.data(fromPropertyList: replacement, format: .xml, options: 0).write(to: infoURL, options: .atomic)

        let mover = RecordingApplicationTrashMover()
        XCTAssertThrowsError(try ApplicationUninstaller(policy: policy, trashMover: mover).moveToTrash(selected, under: applicationsRoot))
        XCTAssertTrue(mover.movedPaths.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: appURL.path))
    }

    func testUninstallerRejectsBundleOutsideSelectedRoot() throws {
        let outsideRoot = testHome.appendingPathComponent("Outside", isDirectory: true)
        try FileManager.default.createDirectory(at: outsideRoot, withIntermediateDirectories: true)
        let outsideApp = try makeApp(named: "Outside.app", bundleID: "com.vendor.outside", under: outsideRoot)
        let info = try ApplicationBundleFingerprint.read(from: outsideApp)
        let record = InstalledApplication(
            path: outsideApp.path,
            displayName: "Outside",
            bundleIdentifier: "com.vendor.outside",
            version: "1",
            byteCount: 0,
            sizeIsLowerBound: false,
            estimatedEntries: 0,
            removalBlockReason: nil,
            fingerprint: info
        )
        let mover = RecordingApplicationTrashMover()

        XCTAssertThrowsError(try ApplicationUninstaller(policy: policy, trashMover: mover).moveToTrash(record, under: applicationsRoot))
        XCTAssertTrue(mover.movedPaths.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: outsideApp.path))
    }

    private func makeApp(named name: String, bundleID: String, under root: URL) throws -> URL {
        let appURL = root.appendingPathComponent(name, isDirectory: true)
        let contents = appURL.appendingPathComponent("Contents", isDirectory: true)
        let macOS = contents.appendingPathComponent("MacOS", isDirectory: true)
        try FileManager.default.createDirectory(at: macOS, withIntermediateDirectories: true)
        let info: [String: Any] = [
            "CFBundleIdentifier": bundleID,
            "CFBundleName": name.replacingOccurrences(of: ".app", with: ""),
            "CFBundleDisplayName": name.replacingOccurrences(of: ".app", with: ""),
            "CFBundlePackageType": "APPL",
            "CFBundleExecutable": "fixture-executable",
            "CFBundleInfoDictionaryVersion": "6.0",
            "CFBundleVersion": "1",
            "CFBundleShortVersionString": "1.0"
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try data.write(to: contents.appendingPathComponent("Info.plist"))
        try Data([0x01, 0x02, 0x03]).write(to: macOS.appendingPathComponent("fixture-executable"))
        return appURL
    }
}

private final class RecordingApplicationTrashMover: TrashMoving, @unchecked Sendable {
    private(set) var movedPaths: [String] = []

    func moveToTrash(_ url: URL) throws {
        movedPaths.append(url.standardizedFileURL.path)
    }
}
