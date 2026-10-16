#!/bin/bash
# Builds MediaRemoteAdapter.framework from ThirdParty/mediaremote-adapter and copies
# its Perl launcher, for NotchFlow's optional "Universal media support".
#
# Usage: build-mediaremote-adapter.sh FRAMEWORKS_DIR RESOURCES_DIR [SIGN_IDENTITY]
# Xcode runs this as a build phase; it can also be run by hand.
set -euo pipefail

FRAMEWORKS_DIR="$1"
RESOURCES_DIR="$2"
SIGN_IDENTITY="${3:--}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/ThirdParty/mediaremote-adapter"
NAME="MediaRemoteAdapter"
FRAMEWORK="$FRAMEWORKS_DIR/$NAME.framework"
BINARY="$FRAMEWORK/Versions/A/$NAME"

# Skip the rebuild when nothing in the adapter changed since the last build.
if [[ -f "$BINARY" ]] && [[ -z "$(find "$SRC/src" "$SRC/include" -newer "$BINARY" -print -quit)" ]]; then
    echo "MediaRemoteAdapter is up to date."
else
    echo "Building MediaRemoteAdapter.framework…"
    rm -rf "$FRAMEWORK"
    mkdir -p "$FRAMEWORK/Versions/A/Resources"

    # Same sources and flags as the project's own CMakeLists.txt.
    xcrun clang \
        -dynamiclib -fobjc-arc -fvisibility=default \
        -arch arm64 -arch x86_64 -mmacosx-version-min=14.0 \
        -I "$SRC/include" -I "$SRC/src" \
        "$SRC"/src/adapter/*.m "$SRC"/src/private/MediaRemote.m "$SRC"/src/utility/*.m \
        -framework Foundation -framework AppKit -framework UniformTypeIdentifiers \
        -install_name "@rpath/$NAME.framework/Versions/A/$NAME" \
        -o "$BINARY"

    cat > "$FRAMEWORK/Versions/A/Resources/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>$NAME</string>
    <key>CFBundleIdentifier</key><string>com.vandenbe.$NAME</string>
    <key>CFBundleName</key><string>$NAME</string>
    <key>CFBundlePackageType</key><string>FMWK</string>
    <key>CFBundleShortVersionString</key><string>0.7.7</string>
    <key>CFBundleVersion</key><string>0.7.7</string>
</dict>
</plist>
PLIST

    ln -sfh A "$FRAMEWORK/Versions/Current"
    ln -sfh "Versions/Current/$NAME" "$FRAMEWORK/$NAME"
    ln -sfh "Versions/Current/Resources" "$FRAMEWORK/Resources"
fi

codesign --force --sign "$SIGN_IDENTITY" --timestamp=none "$FRAMEWORK"

mkdir -p "$RESOURCES_DIR"
cp "$SRC/bin/mediaremote-adapter.pl" "$RESOURCES_DIR/mediaremote-adapter.pl"
cp "$SRC/LICENSE" "$RESOURCES_DIR/MediaRemoteAdapter-LICENSE.txt"
