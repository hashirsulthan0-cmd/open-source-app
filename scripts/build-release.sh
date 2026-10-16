#!/bin/bash
# Builds a Release copy of NotchFlow for Apple Silicon and Intel, and zips it for
# a GitHub release.
#
# Usage: scripts/build-release.sh
# Output: dist/NotchFlow-<version>.zip
#
# The app is ad-hoc signed (no Apple Developer account), so on first launch macOS
# asks the user to confirm opening it. See "Install" in the README.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# Use the full Xcode even if xcode-select points at the Command Line Tools.
if ! xcodebuild -version >/dev/null 2>&1; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

# ".noindex" keeps Spotlight and Launchpad from finding (and opening) these test copies.
BUILD_DIR="$ROOT/build.noindex/release"
DIST_DIR="$ROOT/dist"
rm -rf "$BUILD_DIR"
mkdir -p "$DIST_DIR"

xcodebuild \
    -project NotchFlow.xcodeproj \
    -target NotchFlow \
    -configuration Release \
    ONLY_ACTIVE_ARCH=NO \
    ARCHS="arm64 x86_64" \
    SYMROOT="$BUILD_DIR" \
    build | grep -E "error:|warning:|BUILD (SUCCEEDED|FAILED)" || true

APP="$BUILD_DIR/Release/NotchFlow.app"
[[ -d "$APP" ]] || { echo "Build failed: $APP not found." >&2; exit 1; }

codesign --verify --deep --strict "$APP"
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Contents/Info.plist")
ZIP="$DIST_DIR/NotchFlow-$VERSION.zip"

rm -f "$ZIP"
# ditto keeps the app bundle's symlinks and signature intact, unlike plain zip.
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"

echo "Architectures: $(lipo -archs "$APP/Contents/MacOS/NotchFlow")"
echo "Created $ZIP ($(du -h "$ZIP" | cut -f1))"
shasum -a 256 "$ZIP"
