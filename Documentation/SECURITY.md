# Security Notes – MacPilot

## Implemented controls

- App Sandbox is enabled.
- File access is user-selected read-write because the selected cleanup feature moves approved files to Trash. The open panel is the only path by which a folder is selected.
- Analysis roots: user `Library/Caches`, `Library/Logs`, and `.Trash`. Cleanup roots: user `Library/Caches` and `Library/Logs` only.
- `/System`, `/usr`, `/bin`, `/sbin`, `/private`, `/Library`, `/Applications`, `/Volumes`, and sensitive user Library folders remain blocked.
- Symbolic links in the root path or candidate path are rejected. Symbolic-link entries are skipped. Nested mount points are rejected by comparing device identifiers to the approved Caches/Logs root; package and hidden directories are not traversed.
- Only current-user-owned, non-executable regular files with one hard link are eligible; directories, packages, special files and hidden files are excluded.
- Candidate age is at least 30 days and minimum size is 1 KB. Known database, preferences, lock, credential and certificate formats are excluded. Selected browser and personal-communication cache paths are skipped.
- Scan cap: 20,000 entries and 250 candidates. Cleanup cap: 100 selected files per batch. Incomplete scans disable cleanup.
- The user selects individual files. No default bulk selection occurs. A destructive confirmation explains that exact selected files will be moved to Trash.
- The executor revalidates root containment, symlink status, file type, hard-link count and a `lstat` identity fingerprint inside an `NSFileCoordinator` move accessor.
- The only filesystem mutation is `FileManager.trashItem(at:resultingItemURL:)` for an individually approved file. No folder deletion, permanent deletion, shell command, `sudo`, privileged helper or root escalation exists.
- SQLite audit entries contain event names/counts only and deliberately omit file paths.

## Important limitations

These controls reduce risk but do not prove that a cache/log file is safe to remove for every application. Files may be in use, depend on application-specific behaviour, or be protected by ACLs, TCC or other macOS controls. The app instructs users to close the related app and maintain backups. Failed and changed files are reported; the app does not force access.

The fingerprint and file-coordination checks reduce time-of-check/time-of-use exposure but are not an absolute guarantee against every concurrent filesystem mutation. Do not describe cleanup as risk-free. File restoration is performed by the user through Finder's Trash; the app does not guarantee restore availability.

## App Store and direct distribution

App Sandbox remains enabled for both variants. User-selected read-write access is needed for the explicit Trash workflow and applies to items selected by the user in the open panel. App Review acceptance is not guaranteed; provide review notes describing the constrained roots, item-level selection, age/size rules, revalidation and Trash-only operation. The direct build also remains sandboxed in this milestone.


## Phase 4 – Application Manager

The Application Manager is not a general-purpose recursive uninstaller. It requires the user to choose exactly `/Applications` or `~/Applications` through `NSOpenPanel`; only direct `.app` children are inventoried. The scanner rejects symlink paths and bundle roots, validates the `Contents` directory and `Info.plist` before reading bundle metadata, and excludes Apple bundle IDs (`com.apple.*`) from removal.

The direct-download edition offers a single-bundle Trash operation only. It rechecks that the app is not running, revalidates the allowed root, direct-child relationship, same-volume directory and bundle fingerprint, then uses `NSFileCoordinator` and `FileManager.trashItem`. There is no recursive folder deletion, permanent deletion, `sudo`, privileged helper or automatic removal of associated data. If the selected Applications directory is not writable by the current user, removal is blocked.

The App Store build compiles out the uninstaller and exposes inventory only. The user-selected-folder entitlement is necessary for access to the folder chosen through the standard open panel; it does not grant global filesystem access. App Store review remains discretionary and must be validated against current review requirements.
