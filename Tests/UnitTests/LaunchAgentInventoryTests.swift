import XCTest
@testable import MacPilot

final class LaunchAgentInventoryTests: XCTestCase {
    private var home: URL!
    private var root: URL!
    private var scanner: LaunchAgentInventory!

    override func setUpWithError() throws {
        try super.setUpWithError()
        home = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("MacPilotLaunchAgentTests-\(UUID().uuidString)", isDirectory: true)
        root = home.appendingPathComponent("Library/LaunchAgents", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        scanner = LaunchAgentInventory(homeDirectory: home)
    }

    override func tearDownWithError() throws {
        if let home { try? FileManager.default.removeItem(at: home) }
        try super.tearDownWithError()
    }

    func testReadsOnlyPlistMetadataWithoutChangingFile() throws {
        let url = root.appendingPathComponent("com.example.test.plist")
        let source = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict>
          <key>Label</key><string>com.example.test</string>
          <key>ProgramArguments</key><array><string>/usr/bin/true</string></array>
          <key>RunAtLoad</key><true/><key>KeepAlive</key><false/>
        </dict></plist>
        """
        try source.data(using: .utf8)!.write(to: url)
        let original = try Data(contentsOf: url)
        let result = try scanner.scan(root)
        XCTAssertEqual(result.records.count, 1)
        XCTAssertEqual(result.records.first?.label, "com.example.test")
        XCTAssertEqual(result.records.first?.program, "/usr/bin/true")
        XCTAssertTrue(result.records.first?.runsAtLoad == true)
        XCTAssertFalse(result.records.first?.keepsAlive == true)
        XCTAssertEqual(try Data(contentsOf: url), original, "Inventory must not modify plist files")
    }

    func testRejectsAnyFolderOutsideUserLaunchAgents() {
        let outside = home.appendingPathComponent("Library/Preferences", isDirectory: true)
        XCTAssertThrowsError(try scanner.scan(outside))
    }

    func testSkipsMalformedPlist() throws {
        let url = root.appendingPathComponent("broken.plist")
        try Data("not a plist".utf8).write(to: url)
        let result = try scanner.scan(root)
        XCTAssertTrue(result.records.isEmpty)
        XCTAssertEqual(result.skippedCount, 1)
    }

    func testRejectsSymlinkRoot() throws {
        let outside = home.appendingPathComponent("Outside", isDirectory: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        let link = home.appendingPathComponent("Library/LaunchAgentsLink", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
        XCTAssertThrowsError(try scanner.scan(link))
    }
}
