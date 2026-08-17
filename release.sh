#!/bin/bash
# One-command release: builds the universal app, packages the DMG, publishes it.
# Usage: bash release.sh <version>   (e.g. bash release.sh v1.0.9)
set -e
cd "$(dirname "$0")"

VERSION="${1:?usage: bash release.sh <version> (e.g. v1.0.9)}"
TAG="${VERSION#v}"

echo "→ Building the app…"
bash build.sh >/dev/null

echo "→ Building the universal binary…"
swiftc -O -target arm64-apple-macosx13.0 -framework Cocoa -framework WebKit src/main.swift -o build/DSH-arm64 2>/dev/null
swiftc -O -target x86_64-apple-macosx13.0 -framework Cocoa -framework WebKit src/main.swift -o build/DSH-x86_64 2>/dev/null
lipo -create build/DSH-arm64 build/DSH-x86_64 -output dist/DSH.app/Contents/MacOS/DSH
codesign --force --sign - dist/DSH.app >/dev/null 2>&1
codesign -v dist/DSH.app

echo "→ Building the DMG…"
bash make-dmg.sh "$TAG"

DMG="dist/DSH-Desktop-Launcher-${TAG}-macos-universal.dmg"
echo "→ Publishing $VERSION with: $DMG"
/opt/homebrew/bin/gh release create "$VERSION" "$DMG" \
  --title "DSH Desktop Launcher $VERSION" \
  --notes "Download the DMG, open it, and drag DSH.app into Applications — first launch auto-installs the helper scripts." \
  || { /opt/homebrew/bin/gh release create "$VERSION" "$DMG" --title "DSH Desktop Launcher $VERSION" --notes "Download the DMG, open it, and drag DSH.app into Applications — first launch auto-installs the helper scripts."; }

echo "🎉 Done: https://github.com/pixyshu/dsh-desktop-launcher/releases/tag/$VERSION"
