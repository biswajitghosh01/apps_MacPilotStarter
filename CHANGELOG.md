# Changelog

## Unreleased – Debloat inventory

- Replaced the Debloat placeholder with a read-only inventory of the current user's LaunchAgents plist metadata.
- Restricted scanning to direct children of `~/Library/LaunchAgents`; rejected other and symlink roots.
- Added a 500-file cap, malformed-file handling and unit tests for root restrictions and non-modification.
- No unload, disable, edit or delete controls are provided.


## Unreleased – Performance telemetry

- Added five-second, read-only system load-average sampling and VM memory page estimates.
- Added a live Performance screen with measurement caveats and manual refresh.
- Added unit tests for load normalization and safe percentage formatting.


## Unreleased – Build configuration hardening

- Corrected the App Store target to use a bundle identifier distinct from the direct-download target.
- Preserved the existing direct-build identifier; both identifiers remain placeholders until replaced with developer-owned registered IDs.
- Documented the required XcodeGen regeneration step after project-spec changes.


## 0.4.0 – Phase 4: Application Manager

- Added a read-only inventory of direct `.app` bundles in a user-selected `/Applications` or `~/Applications` folder.
- Added bundle metadata, bounded package-size estimates and inventory truncation reporting.
- Protected `com.apple.*` bundle identifiers, system application locations, nested application folders, symbolic-link bundles and redirected bundle metadata paths.
- Added direct-build-only single-app removal to macOS Trash with app-running checks, bundle fingerprint revalidation and coordinated file movement.
- Kept application support files, preferences, containers, keychain records, helpers, login items and user documents untouched.
- Kept the App Store edition inventory-only for app removal.
- Added seven application-manager tests.


## 0.3.0 – Phase 3: Reversible Smart Cleanup

- Added a separate cleanup candidate scanner for user Caches and Logs only.
- Added conservative 30-day age and 1 KB minimum-size rules, current-user ownership and non-executable checks, excluded file types and sensitive path markers.
- Added bounded scans (20,000 entries / 250 candidates) and 100-file cleanup batches.
- Added per-item selection, destructive confirmation, path and file-identity revalidation, and NSFileCoordinator move coordination.
- Added Trash-only execution through FileManager.trashItem; no permanent or recursive deletion path exists.
- Changed user-selected file entitlement to read-write for the explicitly selected folder.
- Added cleanup activity reporting and count-only audit events.
- Added seven cleanup policy and executor tests.

## 0.2.1 – Phase 2.1 test-fixture correction

- Fixed Phase 2 test fixtures to create the synthetic home under the current user's home directory.
- Preserved the strict production symlink-path rejection policy; no production cleanup permissions were broadened by the fixture fix.

## 0.2.0 – Phase 2: Storage Analysis

- Added a dedicated Storage Analyzer screen with startup-volume capacity information.
- Expanded read-only scanning to report file counts, folder counts, observed bytes, file-type breakdowns and the largest files.
- Added explicit scan truncation reporting and bounded largest-file result storage.
- Kept analysis within approved user Caches, Logs and Trash roots.
- Added tests for largest-file ranking, extension summaries, symlink exclusion and scan limits.
- Added the MacPilot propeller app icon and AppIcon asset catalog.

## 0.1.2 – Scheme correction

- Attached the XCTest target to the MacPilot scheme's Test action.

## 0.1.0 – Phase 1 foundation

- Native SwiftUI application shell and first-launch notice for direct builds.
- System overview and basic storage metadata.
- Fail-closed scan-root policy and read-only scanner.
- Local SQLite audit event store.
- Separate App Store target and shared XCTest scheme.
