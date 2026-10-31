# MacPilot Architecture

## Current application flow

`SwiftUI View → CleanupCandidateScanner / ReadOnlyScanner → SafetyPolicy → CleanupExecutor → NSFileCoordinator → FileManager.trashItem`

The read-only storage analyser remains separate from the cleanup candidate scanner. The cleanup UI receives candidates, displays each file, and passes only the explicitly selected candidates to `CleanupExecutor`. The executor validates the cleanup root and each target again, coordinates the move, compares a filesystem identity fingerprint with the preview, and delegates the exact file move to `FileManager.trashItem`.

## Module responsibilities

- `App/`: application entry point and first-launch routing.
- `Views/`: SwiftUI presentation and explicit user consent.
- `Models/`: view and domain data types.
- `Services/SystemInfoService`: non-destructive system metadata.
- `Services/AuditLogStore`: local SQLite event log without filesystem paths.
- `Engines/SafetyPolicy`: separate allowlists for analysis roots and cleanup roots, path containment and symlink checks.
- `Engines/ReadOnlyScanner`: read-only metadata enumeration for storage analysis.
- `Engines/CleanupEngine`: conservative candidate scanner, file fingerprint, bounded executor and Trash mover.
- `Tests/UnitTests`: policy, candidate eligibility, stale-file and explicit-selection tests.

## Cleanup rules

Cleanup is limited to descendants of the current user's `~/Library/Caches` and `~/Library/Logs`. It excludes Trash, Downloads, Documents, Applications, system locations and sensitive user Library folders. Candidate files must be owned by the current user, be non-executable regular files with a single hard link, be at least 30 days old, and be at least 1 KB. Hidden files, known database/preference/credential formats and selected browser or personal-communication cache paths are excluded. Folders and package descendants are not cleanup candidates.

A scan is capped at 20,000 entries and 250 candidates; a cleanup batch is capped at 100 files. An incomplete scan disables cleanup. Candidates are transient UI data and are not persisted to the audit database.

## Security boundary and limitations

App Sandbox is enabled. The user chooses the folder through `NSOpenPanel`; the current build uses the user-selected read-write entitlement because cleanup needs write permission to move selected files to Trash. The app does not request Full Disk Access, administrator credentials or root privileges. It does not invoke shell commands, `sudo`, `rm`, or permanent deletion APIs.

The executor revalidates paths, file types, hard-link count and a `lstat` fingerprint inside a coordinated move accessor immediately before calling `FileManager.trashItem`. This reduces race risk but does not make filesystem operations risk-free or provide an absolute security guarantee. A file may be changed by another process or denied by macOS privacy controls; such items are skipped or reported as failed. Restoration is handled through Finder's Trash, not by an in-app restore mechanism.


## Phase 4 – Application Manager

`ApplicationInventoryScanner` inspects a user-selected standard Applications folder. `ApplicationSafetyPolicy` limits roots to `/Applications` and `~/Applications`, validates direct-child `.app` packages and rejects symlink redirects, Apple bundle identifiers, nested application folders and cross-volume app bundles. Package sizing is a bounded metadata estimate and may be reported as a lower bound.

`ApplicationUninstaller` is excluded from `APP_STORE_EDITION`. In the direct build it accepts exactly one `InstalledApplication` record, revalidates its bundle fingerprint, ensures the target is not running, coordinates the move and delegates to the shared Trash mover. Associated app data is intentionally outside this phase.


## Phase 5.1 – Performance telemetry

`PerformanceMonitor` samples the system load average through `getloadavg` and reads VM page counters through `host_statistics64`. The monitor is read-only and does not claim load average is CPU utilisation. Memory in-use and available figures are page-counter estimates; they are not a replacement for macOS Memory Pressure. Sampling is limited to one update every five seconds while the Performance screen is active.


## Phase 5.2 – Login agent inventory

`LaunchAgentInventory` reads direct-child plist metadata only from the current user's `~/Library/LaunchAgents`. It rejects other roots and symlink roots, skips hidden/non-regular files, caps the inventory at 500 plist files, and never loads, unloads, edits, disables or deletes jobs. The screen is an inspection aid, not a recommendation engine: the presence of a login agent does not mean it is unnecessary.
