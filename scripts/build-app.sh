#!/usr/bin/env bash
# Builds an Apple Silicon, ad-hoc signed CopyShelf.app into ./dist.
# Works with just the Xcode Command Line Tools — no Xcode project needed.
#
# Usage: scripts/build-app.sh            (version from ./VERSION)
#        VERSION=0.2.0 scripts/build-app.sh
set -euo pipefail

cd "$(dirname "$0")/.."
VERSION="${VERSION:-$(cat VERSION)}"
BUILD="${BUILD:-$(git rev-list --count HEAD 2>/dev/null || echo 1)}"
APP="dist/CopyShelf.app"

echo "▸ Building CopyShelf $VERSION ($BUILD)"
swift build -c release --arch arm64 --product CopyShelf -Xswiftc -Osize -Xswiftc -gnone -Xlinker -dead_strip >/dev/null

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp .build/arm64-apple-macosx/release/CopyShelf "$APP/Contents/MacOS/CopyShelf"
strip -x "$APP/Contents/MacOS/CopyShelf"

sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD/" Resources/Info.plist > "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
printf 'APPL????' > "$APP/Contents/PkgInfo"

# Ad-hoc signature (free; no Apple Developer account) with a stable designated requirement
# so rebuilding or upgrading the app doesn't break macOS Accessibility permissions.
codesign --force --sign - --requirements '=designated => identifier "com.ethanclawsie.copyshelf"' --timestamp=none "$APP"
codesign --verify --strict "$APP"

echo "✓ $APP ($(du -sh "$APP" | cut -f1 | xargs), $(lipo -archs "$APP/Contents/MacOS/CopyShelf"))"
