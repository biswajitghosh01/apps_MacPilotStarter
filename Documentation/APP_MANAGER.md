# Application Manager – Phase 4

## Current scope

The application inventory screen works only on a user-selected, exact standard root:

- `/Applications`
- `~/Applications`

The user selects the folder through `NSOpenPanel`. MacPilot starts security-scoped access only while validating the selection, scanning the inventory, or performing a confirmed move, and stops access after each operation. It does not persist a security-scoped bookmark, so the folder must be selected again after restarting the app or returning to the App Manager after its selection has been cleared.

Only direct child `.app` bundles are inventoried. The scanner does not recurse into nested application folders, `/System/Applications`, `/Applications/Utilities`, disk images, arbitrary folders, or other mounted volumes. It reads bundle metadata and performs a bounded metadata-only size estimate.

## Removal eligibility

The direct-download edition can offer one app bundle at a time only when all of the following are true:

- The app is a real `.app` directory directly inside the selected allowed root.
- The root and app bundle are on the same filesystem volume.
- The app bundle, `Contents` directory, `Info.plist`, and main executable are real filesystem entries rather than symlink redirects.
- The bundle identifies itself as an `APPL` application.
- The bundle identifier is available and does not begin with `com.apple.`.
- The selected parent directory is writable by the current user.
- The app is not running at the time of the operation.
- The bundle fingerprint captured during inventory still matches at the time of the coordinated move.

If a check fails, the app remains inventory-only or the move is rejected. MacPilot never requests administrator credentials or attempts a privileged operation.

## What is moved

Only the selected `.app` bundle is passed to the shared Trash mover. The operation uses `NSFileCoordinator` and `FileManager.trashItem`. No permanent deletion or recursive cleanup is implemented.

The following are deliberately not modified:

- `~/Library/Application Support`
- `~/Library/Preferences`
- `~/Library/Containers` and Group Containers
- `~/Library/Keychains`
- Login items, launch agents, launch daemons and privileged helpers
- Browser profiles, databases, documents and other user-created data

Some apps provide their own uninstaller; that vendor-supplied uninstaller may be required to remove helpers, services or additional data. The App Manager does not try to infer or remove those components.

## Distribution difference

`MacPilot` (direct build) includes the one-app-to-Trash operation. `MacPilot-AppStore` compiles the removal operation out and is inventory-only. This separation is intentional because Mac App Store software must be sandboxed and Apple applies additional restrictions to software that modifies data belonging to other apps. App Store acceptance is never guaranteed by the implementation.

## Test procedure

Use a disposable macOS test account or VM and create a dummy app under that account's `~/Applications` folder. Verify inventory, metadata, eligibility, confirmation, Trash placement and Finder restoration. Then verify that Apple bundle IDs, symlink bundles, redirected `Contents` folders, nested apps, outside-root records, stale bundles and running apps cannot be removed.

Do not use a production application or your main `/Applications` folder for the first destructive test.
