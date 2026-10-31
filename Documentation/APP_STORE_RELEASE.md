# Mac App Store Release Checklist

This starter is not release-ready. Complete and verify all items before submission.

- [ ] Choose and verify a final product name and trademark clearance.
- [ ] Register a Bundle ID controlled by the developer.
- [ ] Join the Apple Developer Program.
- [ ] Use the separate `MacPilotAppStore` target / `MacPilot-AppStore` scheme.
- [ ] Keep the launch-time disclaimer acceptance gate out of the App Store target; Apple's review guidelines prohibit a license screen at launch for Mac App Store apps.
- [ ] Keep App Sandbox enabled and justify each entitlement.
- [ ] Confirm every advertised feature works within the sandbox and public APIs.
- [ ] Remove placeholder screens and unfinished claims.
- [ ] Complete privacy policy, privacy nutrition labels and support URL.
- [ ] Prepare icons, screenshots, description, keywords, category and age rating.
- [ ] Test on supported macOS versions and Apple Silicon/Intel configurations where applicable.
- [ ] Run XCTest and UI testing; include permission-denied and recovery cases.
- [ ] Configure the Apple Developer Team and signing for `MacPilot-AppStore`.
- [ ] Archive and validate in Xcode; upload using Xcode/Transporter.
- [ ] Provide App Review notes describing the user-selected read-write entitlement, folder selection, Caches/Logs-only cleanup allowlist, individual item selection, 30-day/1 KB candidate rules, per-file revalidation, Trash-only movement, and known limitations.
- [ ] Test a release candidate through TestFlight where applicable.
- [ ] Submit through App Store Connect; approval is at Apple's discretion.

Official links:
- https://developer.apple.com/app-store/review/guidelines/
- https://developer.apple.com/app-store-connect/
- https://developer.apple.com/documentation/security/app-sandbox


## Phase 4 App Manager limitation

The `APP_STORE_EDITION` compiles application removal out; the App Store build supports inventory only and directs users to Finder for uninstall. The direct-download build uses a user-selected standard Applications folder and a single-item Trash move. This separation avoids promising that App Store review will permit third-party app removal. Recheck the current App Review Guidelines and sandbox entitlements before submission.

Apple's current Mac App Store-specific guideline 2.4.5(i) requires appropriate sandboxing and appropriate macOS APIs when modifying data stored by other apps. Guideline 2.5.2 also restricts access outside the app's designated container area, subject to the system's documented user-selected-file access mechanisms. The App Store edition therefore compiles third-party app removal out and exposes inventory only. The remaining user-selected cleanup functionality still requires a feature-by-feature App Review assessment; do not assume approval from successful local sandbox tests.


## App Store policy assessment before submission

The cleanup feature uses the standard user-selected folder panel, the App Sandbox user-selected read-write entitlement, coordinated file operations, and `FileManager.trashItem`. This is the intended least-privilege design, but it is not a guarantee of App Review approval: cache and log files can be data created by other apps, so the feature must be clearly disclosed and justified under guideline 2.4.5(i) and sandbox rules. Include explicit review notes and a reproducible review flow. If review feedback indicates that cross-app cache cleanup is not acceptable, ship the App Store edition with read-only analysis and retain cleanup only in the separately distributed direct edition.
