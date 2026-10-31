#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if [[ ! -d MacPilot.xcodeproj ]]; then
  echo "MacPilot.xcodeproj not found. Run ./bootstrap.sh first." >&2
  exit 1
fi

HOST_ARCH="$(uname -m)"
case "$HOST_ARCH" in
  arm64) DESTINATION='platform=macOS,arch=arm64' ;;
  x86_64) DESTINATION='platform=macOS,arch=x86_64' ;;
  *) echo "Unsupported host architecture: $HOST_ARCH" >&2; exit 1 ;;
esac

xcodebuild -project MacPilot.xcodeproj \
  -scheme MacPilot \
  -destination "$DESTINATION" \
  -derivedDataPath build/DerivedData \
  CODE_SIGNING_ALLOWED=NO build
