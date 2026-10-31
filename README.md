# MacPilot

MacPilot is a native SwiftUI macOS utility built around a safety-first design. The current Phase 4 package contains the system overview, read-only storage analysis, individually approved cache/log files moved to macOS Trash, and a constrained Application Manager.

**Important:** The App Manager scans only direct `.app` bundles in a user-selected `/Applications` or `~/Applications` folder. The direct-download build can move one reviewed third-party `.app` bundle to macOS Trash. It does not remove support files, preferences, containers, keychain records, login items, helper tools, services or user documents. The App Store target is inventory-only for application removal. No system app deletion, root escalation or permanent deletion is provided.

## Project structure

```text
MacPilotStarter/
├── bootstrap.sh
├── apply-phase2.sh
├── apply-phase3.sh
├── apply-phase4.sh
├── project.yml
├── README.md
├── MacPilot/
│   ├── App/
│   ├── Engines/
│   ├── Models/
│   ├── Services/
│   ├── Views/
│   └── MacPilot.entitlements
├── Tests/UnitTests/
├── Scripts/
└── Documentation/
```

## License

The starter source is provided under the MIT License in `LICENSE`. Replace the copyright holder placeholder before distributing modified versions.

## Fixing a scheme test-action error

If `xcodebuild test` reports that scheme `MacPilot` is not configured for the test action, regenerate the project after confirming that `project.yml` includes `MacPilotTests` under `schemes > MacPilot > test > targets`:

```yaml
schemes:
  MacPilot:
    test:
      config: Debug
      targets:
        - MacPilotTests
```

Then run:

```bash
xcodegen generate --spec project.yml
xcodebuild -list -project MacPilot.xcodeproj
xcodebuild -project MacPilot.xcodeproj \
  -scheme MacPilot \
  -destination 'platform=macOS' \
  -derivedDataPath build/DerivedData \
  CODE_SIGNING_ALLOWED=NO test
```

The explicit `targets` entry tells XcodeGen which XCTest bundle belongs to the scheme's Test action.

### If Xcode reports that the MacPilot scheme has no Test action

The project spec attaches `MacPilotTests` to the `MacPilot` scheme using XcodeGen's target-level `scheme.testTargets` setting. Regenerate the project after replacing/updating `project.yml`:

```bash
rm -rf MacPilot.xcodeproj
xcodegen generate --spec project.yml
xcodebuild -list -project MacPilot.xcodeproj
grep -n "TestAction" MacPilot.xcodeproj/xcshareddata/xcschemes/MacPilot.xcscheme
./Scripts/test.sh
```

The `rm -rf` command above removes only the generated `MacPilot.xcodeproj` directory, not the Swift source files. Do not run it against any other path. The generated shared scheme should contain a `<TestAction>` and a testable reference for `MacPilotTests`.

## Phase 2 – Storage analysis

The Storage Analyzer remains read-only. The Smart Cleanup module separately scans only descendants of the current user's `Library/Caches` and `Library/Logs` directories. It proposes only old, sufficiently large regular files; it does not open file contents or suggest deleting directories.

Scan reports contain:

- Regular-file and directory counts.
- Total observed logical file size.
- A bounded list of the 20 largest regular files.
- A file-extension breakdown (up to 12 groups).
- Skipped/unreadable item counts and a visible truncation warning when the configured scan-entry cap is reached.

The observed bytes are not represented as guaranteed reclaimable storage. Directory packages are not traversed, symbolic links are skipped, and scans are capped at 50,000 entries to bound resource use. Scanned file paths are shown in-memory for review and are not written to the SQLite audit log.

### Upgrade an existing Phase 1 checkout

The package includes `apply-phase2.sh`. It copies only the Phase 2 source, tests, documentation and icon assets into an existing MacPilot folder, creates a timestamped backup of replaced files, adds the AppIcon build setting and regenerates the Xcode project. It deliberately preserves your existing bundle identifiers and other XcodeGen project settings.

```bash
chmod +x apply-phase2.sh
./apply-phase2.sh "/absolute/path/to/your/MacPilotStarter"
cd "/absolute/path/to/your/MacPilotStarter"
./Scripts/test.sh
./Scripts/build.sh
```

Use the bundle identifier you already selected when running the bootstrap. Do not run the bootstrap with a different bundle identifier over an existing installation unless you intend to create a separate app identity. The helper does not install or run the app and does not perform any filesystem cleanup outside its own project update/backup steps.

### Phase 2 test coverage

The XCTest suite covers the permitted cache root, system/protected path denial, symlink-root denial, read-only behaviour, file-size and extension summaries, symlink-entry exclusion, and scan-entry truncation.

Phase 3 adds a bounded, separately tested Trash-only workflow. See the section below for its current limits and remaining risks.


## Phase 2.1 test-fixture correction

The Phase 2.1 package uses a unique test-home directory under the current user's home directory. This is intentional: the production `SafetyPolicy` rejects symlinks anywhere in the selected path, while macOS temporary paths can include system symlink aliases. The test fixture is aligned to the policy's intended trusted-home model; the production safety checks are not relaxed.


## Phase 3 – Reversible Smart Cleanup

Phase 3 adds a distinct `CleanupCandidateScanner` and `CleanupExecutor`. The candidate scanner reads metadata only and accepts folders within the current user's `Library/Caches` or `Library/Logs`. It never accepts `.Trash` as a cleanup source.

### Candidate rules

- Modified at least 30 days ago.
- At least 1 KB.
- Current-user-owned, non-executable regular files only; no folders, package descendants, symbolic links, hidden files, special files, nested mount points or files with multiple hard links.
- Excludes database, SQLite, preference, JSON, lock, PID, socket, key, certificate and provisioning-profile extensions.
- Skips selected browser and personal-communication cache path markers.
- Maximum 20,000 enumerated entries and 250 candidates per scan. Incomplete scans disable cleanup.
- Maximum 100 individually selected files per cleanup batch. No default selection is made.

### Cleanup execution

The user selects files individually and confirms a destructive action in a separate confirmation dialog. Before each move, MacPilot validates root containment, symlink status, file type, hard-link count and a filesystem identity fingerprint. It coordinates the operation through `NSFileCoordinator` and calls `FileManager.trashItem` for the exact file. Changed, inaccessible or policy-blocked items are skipped or reported. The app has no permanent-delete or recursive-folder-delete code path.

The App Sandbox entitlement changes from user-selected read-only to user-selected read-write so the app can move files in a folder the user explicitly selects. This does not provide general access to the user's home directory. App Store review remains subject to Apple's review process; the feature and entitlement should be explained in review notes and revalidated against current requirements before submission.

Audit records store event names and counts, not filesystem paths. Recovery is through Finder's Trash; the app does not provide a guaranteed restore facility. Keep backups and close the application associated with the selected cache/log files before cleaning.

### Phase 3 tests

The suite retains the nine Phase 2 tests and adds coverage for cleanup root restrictions, old-file eligibility, stale-file revalidation, explicit-selection-only execution, outside-root rejection, per-batch caps, hard-link exclusion and executable-file exclusion. A test double verifies that the executor invokes the Trash mover only for selected and still-valid paths; an actual Trash move should be tested manually in a disposable macOS test account or VM.

### Upgrade an existing Phase 2 project

The package includes `apply-phase3.sh`. It backs up all replaced source, entitlement, test and documentation files, copies the Phase 3 cleanup engine and UI, updates the file-access entitlement to user-selected read-write (required for the explicit Trash workflow), advances the version, and regenerates the Xcode project. It preserves existing bundle identifiers and shared scheme declarations.

```bash
chmod +x apply-phase3.sh
./apply-phase3.sh "/absolute/path/to/your/MacPilotStarter"
cd "/absolute/path/to/your/MacPilotStarter"
./Scripts/test.sh
./Scripts/build.sh
```

Review the generated backup directory and the updated `MacPilot/MacPilot.entitlements` before testing. The selected-folder read-write entitlement does not grant global disk access; the user must choose the folder through the standard macOS open panel.

### Manual cleanup verification (disposable test account or VM)

1. Create a test folder beneath the test user's `~/Library/Caches` and place non-sensitive dummy files in it.
2. Set one dummy file's modification date to more than 30 days ago and keep another recent.
3. In Smart Cleanup, select the test folder and run the candidate scan.
4. Confirm that only the old, eligible file is offered and that no files change during scanning.
5. Select exactly one dummy file, review the confirmation dialog, and move it to Trash.
6. Confirm that the selected file appears in Finder's Trash and that unselected/recent files remain in place.
7. Restore the dummy file from Finder's Trash, then repeat with permission denied, changed-file and symlink scenarios.

Do not use real application data for initial manual cleanup testing. The XCTest mover is a test double and intentionally does not alter fixture files; actual Trash integration must be verified manually in an isolated test account or virtual machine.


## Phase 4 – Application Manager

Phase 4 adds a constrained application inventory and a direct-build-only, single-application move-to-Trash workflow.

### Inventory scope

- The user must explicitly choose exactly `/Applications` or `~/Applications` through a standard macOS open panel.
- Only direct child bundles ending in `.app` are inspected. Nested folders and `/System/Applications` are not scanned.
- The scanner reads bundle metadata (`CFBundleIdentifier`, display name, version) and estimates package size using a bounded metadata walk. Size is marked as a lower bound if the entry cap is hit or entries are inaccessible.
- Symbolic-link bundles, redirected `Contents` folders, invalid bundles, non-`APPL` packages and Apple bundle identifiers (`com.apple.*`) are excluded from removal.
- Removal is disabled if the selected folder is not writable by the current user. MacPilot does not request administrator privileges.

### Removal scope and safeguards

- The direct-download edition supports one selected `.app` bundle at a time.
- The app must not be running. MacPilot checks the running-application registry before and during the coordinated operation.
- The exact bundle path must remain a direct child of the selected standard Applications folder.
- Before the move, MacPilot revalidates path, filesystem volume, bundle identifier, `Contents/Info.plist` structure and a filesystem fingerprint captured during inventory.
- The app bundle is moved with `FileManager.trashItem` through a coordinated file move. There is no permanent-delete or recursive removal path.
- Application Support, Caches, Logs, Preferences, Containers, Group Containers, Keychains, launch agents, privileged helpers and documents are not removed. The UI explains this before confirmation.
- The App Store edition is intentionally inventory-only for application removal. Use Finder to uninstall apps in that edition. App Store acceptance of any file-management capability remains subject to review.
- Security-scoped access is acquired only around root validation, each scan, and the confirmed move, then released. The selected Applications folder must be selected again after app relaunch or when the App Manager screen clears its selection; this build does not persist a security-scoped bookmark.

### Phase 4 test coverage

The application-manager test file covers exact root allowlisting, top-level bundle inventory, Apple bundle protection, symlink bundle exclusion, explicit single-app mover selection, stale bundle rejection and outside-root rejection. Together with the existing Phase 2 and Phase 3 tests, the source package contains 25 XCTest cases. Run the suite on macOS; a Linux source-package validation is not a substitute for Xcode execution.

### Upgrade

The package includes `apply-phase4.sh`. First extract this Phase 4 ZIP into a folder separate from your existing project. The script backs up all files it replaces, copies the Phase 3 and Phase 4 sources/tests/docs, preserves the project's current bundle identifiers and scheme declarations, updates the version to `0.4.0`, and regenerates the project using XcodeGen. It intentionally refuses to use the extracted source package as its own target.

```bash
# Run these commands inside the extracted Phase 4 package folder.
chmod +x apply-phase4.sh
./apply-phase4.sh "/absolute/path/to/your/existing/MacPilotStarter"
cd "/absolute/path/to/your/MacPilotStarter"
./Scripts/test.sh
./Scripts/build.sh
```

### Manual uninstall verification (isolated VM/test account only)

1. Create a disposable third-party test app under a test user's `~/Applications` folder. Do not use a real production app for the first test.
2. Launch MacPilot direct-build edition and choose that `~/Applications` folder through the folder picker.
3. Confirm that the test app appears and its metadata is correct.
4. Select the app and read the confirmation carefully. Confirm that only the `.app` bundle is moved to Trash.
5. Verify the app appears in Finder's Trash and that unrelated apps and all support data remain untouched.
6. Restore the test app from Trash in Finder.
7. Repeat with a bundle ID beginning `com.apple.`, a symlink bundle, a nested app and a currently running app; each must be blocked or excluded.

Do not begin by testing an app from your main `/Applications` folder. Use a disposable test account or VM. App bundle removal is destructive even though it uses Trash, and restoration is not guaranteed in every filesystem condition.


## Phase 4.1 – Build identity correction

The direct and App Store targets must have distinct bundle identifiers. The direct target retains the existing starter identifier `com.example.macpilot`; the App Store target uses `com.example.macpilot.appstore`. Both are placeholders and must be replaced with identifiers registered to the developer before distribution. The direct identifier is intentionally preserved to avoid changing the identity of an existing direct-build installation.

After changing `project.yml`, regenerate the Xcode project before building:

```bash
xcodegen generate --spec project.yml
xcodebuild -list -project MacPilot.xcodeproj
```

Do not submit an archive while either target still uses a `com.example` identifier.


## Phase 5.1 – Read-only Performance telemetry

The Performance screen samples macOS system load averages and VM memory page counters every five seconds. Load average is not CPU utilisation; the interface labels it separately and compares it with logical processor count. Memory figures are estimates and may not match Activity Monitor's memory-pressure display. No process termination, priority changes, privileged commands or system setting changes are performed.

