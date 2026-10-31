# Build Targets and Schemes

MacPilot has two application targets that compile the same Swift source tree.

| Scheme | Target | Launch behaviour | Intended use |
|---|---|---|---|
| `MacPilot` | `MacPilot` | Shows first-use risk acknowledgement until accepted | Development and direct-distribution base |
| `MacPilot-AppStore` | `MacPilotAppStore` | Does not gate launch behind a license/acceptance screen | Mac App Store candidate |

The direct target retains the existing placeholder identifier `com.example.macpilot`; the App Store target uses the distinct placeholder identifier `com.example.macpilot.appstore`. Replace both with identifiers registered to the developer before distribution. The direct identifier is intentionally unchanged to avoid breaking an existing direct-build installation. Both targets use App Sandbox and the user-selected read-write file entitlement. This entitlement is used only for files or folders the user explicitly selects through the standard open panel; it does not grant unrestricted filesystem access. The selected folder is constrained again by MacPilot's own cleanup allowlist. Review this entitlement against current App Store requirements before submission.

The App Store target uses a distinct internal product name to avoid build-product collisions; its bundle display name remains MacPilot.

Local App Store variant build check:

```bash
xcodebuild -project MacPilot.xcodeproj \
  -scheme MacPilot-AppStore \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO build
```

This command only verifies compilation. For distribution, set the correct Apple Developer Team and signing assets in Xcode and archive the App Store scheme. Do not disable signing for an App Store submission.


## Phase 4 distribution difference

- `MacPilot` (direct build): supports a single selected third-party `.app` bundle move to macOS Trash after explicit confirmation and revalidation.
- `MacPilot-AppStore`: application inventory only; app removal is compiled out. Users uninstall apps using Finder.
