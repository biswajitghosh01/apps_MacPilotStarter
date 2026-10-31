#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUNDLE_ID="com.example.macpilot"
SKIP_BUILD=0
SKIP_TESTS=0

usage() {
  cat <<'USAGE'
MacPilot bootstrap

Usage:
  ./bootstrap.sh [--bundle-id com.company.macpilot] [--skip-build] [--skip-tests]

Options:
  --bundle-id ID   Set the app bundle identifier (reverse-DNS format).
  --skip-build     Generate the Xcode project without building it.
  --skip-tests     Skip XCTest after a successful build.
  -h, --help       Show this help.

The script does not run cleanup operations or modify system files.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --bundle-id)
      [[ $# -ge 2 ]] || { echo "Missing value for --bundle-id" >&2; exit 2; }
      BUNDLE_ID="$2"
      shift 2
      ;;
    --skip-build) SKIP_BUILD=1; shift ;;
    --skip-tests) SKIP_TESTS=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage; exit 2 ;;
  esac
done

if [[ ! "$BUNDLE_ID" =~ ^[A-Za-z0-9][A-Za-z0-9-]*(\.[A-Za-z0-9][A-Za-z0-9-]*)+$ ]]; then
  echo "Invalid bundle identifier: $BUNDLE_ID" >&2
  echo "Use reverse-DNS notation, e.g. com.yourcompany.macpilot" >&2
  exit 2
fi

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "MacPilot must be bootstrapped on macOS with Xcode installed." >&2
  exit 1
fi

if ! command -v xcodebuild >/dev/null 2>&1 || ! command -v xcode-select >/dev/null 2>&1; then
  echo "Xcode command-line tools were not found. Install Xcode from the Mac App Store," >&2
  echo "open Xcode once, then run: xcode-select --install" >&2
  exit 1
fi

if ! xcodebuild -version >/dev/null 2>&1; then
  echo "Xcode is installed but not fully configured. Open Xcode and accept its license." >&2
  exit 1
fi

if ! command -v xcodegen >/dev/null 2>&1; then
  if command -v brew >/dev/null 2>&1; then
    printf "XcodeGen is required. Install it with Homebrew now? [y/N] "
    read -r answer
    case "$answer" in
      y|Y|yes|YES) brew install xcodegen ;;
      *) echo "Install XcodeGen with 'brew install xcodegen', then rerun this script." >&2; exit 1 ;;
    esac
  else
    echo "XcodeGen is required. Install Homebrew, then run: brew install xcodegen" >&2
    echo "See https://github.com/yonaskolb/XcodeGen for other installation options." >&2
    exit 1
  fi
fi

cd "$ROOT_DIR"

# Keep the checked-in project spec generic. Generate a temporary same-directory copy
# so relative source paths remain rooted at the project and repeated runs are safe.
if [[ ! -f "$ROOT_DIR/project.yml" ]]; then
  echo "project.yml is missing from $ROOT_DIR" >&2
  exit 1
fi
SPEC_FILE="$ROOT_DIR/.project.generated.yml"
cp "$ROOT_DIR/project.yml" "$SPEC_FILE"
trap 'rm -f "$SPEC_FILE"' EXIT
if command -v perl >/dev/null 2>&1; then
  perl -0pi -e "s/com\\.example\\.macpilot\\.tests/$BUNDLE_ID.tests/g; s/com\\.example\\.macpilot/$BUNDLE_ID/g" "$SPEC_FILE"
else
  echo "Perl is required to update the bundle identifier." >&2
  exit 1
fi

echo "==> Generating MacPilot.xcodeproj"
xcodegen generate --spec "$SPEC_FILE"

echo "==> Xcode project generated"
echo "    Bundle ID: $BUNDLE_ID"
echo "    Deployment target: macOS 13.0"
echo "    Architectures: Xcode standard macOS architectures (Apple Silicon and Intel where supported)"

if [[ "$SKIP_BUILD" -eq 1 ]]; then
  echo "Skipping build as requested. Open MacPilot.xcodeproj in Xcode."
  exit 0
fi

echo "==> Building MacPilot"
xcodebuild -project MacPilot.xcodeproj -scheme MacPilot -destination 'platform=macOS' -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO build

if [[ "$SKIP_TESTS" -eq 0 ]]; then
  echo "==> Running safety tests"
  xcodebuild -project MacPilot.xcodeproj -scheme MacPilot -destination 'platform=macOS' -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO test
else
  echo "Skipping tests as requested."
fi

echo
echo "MacPilot starter is ready. Open it with: open MacPilot.xcodeproj"
echo "No cleanup or deletion operation was performed."
