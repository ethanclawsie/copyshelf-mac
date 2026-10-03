#!/usr/bin/env bash
# Builds a universal (Apple Silicon + Intel), ad-hoc signed CopyShelf.app into ./dist.
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
for arch in arm64 x86_64; do
  swift build -c release --arch "$arch" --product CopyShelf -Xswiftc -Osize >/dev/null
done

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

lipo -create \
  .build/arm64-apple-macosx/release/CopyShelf \
  .build/x86_64-apple-macosx/release/CopyShelf \
  -output "$APP/Contents/MacOS/CopyShelf"
strip -x "$APP/Contents/MacOS/CopyShelf"

sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD/" Resources/Info.plist > "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
printf 'APPL????' > "$APP/Contents/PkgInfo"

# Ad-hoc signature (free; no Apple Developer account). Required to run on Apple Silicon.
codesign --force --sign - --timestamp=none "$APP"
codesign --verify --strict "$APP"

echo "✓ $APP ($(du -sh "$APP" | cut -f1 | xargs), $(lipo -archs "$APP/Contents/MacOS/CopyShelf"))"
