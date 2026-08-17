#!/bin/bash
# One-command release: builds the universal app, packages the DMG and the zip, publishes both.
# Usage: bash release.sh <version>   (e.g. bash release.sh v1.0.9)
#
# RELEASE POLICY (per maintainer):
# 1. Every release ships BOTH assets — the DMG for end users and the zip for scripting/automation.
# 2. Do NOT release on every feature/bugfix commit. Batch changes on main and only publish
#    when enough features or bug fixes have accumulated.
# 3. Propose a release (version + changelog + test status) and wait for the maintainer's
#    explicit approval BEFORE running this script.
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

echo "→ Building the zip…"
ditto -c -k --keepParent dist/DSH.app "/tmp/DSH-${TAG}-macos-universal.zip"

DMG="dist/DSH-Desktop-Launcher-${TAG}-macos-universal.dmg"
ZIP="/tmp/DSH-${TAG}-macos-universal.zip"
echo "→ Publishing $VERSION with both assets:"
echo "   $DMG"
echo "   $ZIP"
/opt/homebrew/bin/gh release create "$VERSION" "$DMG" "$ZIP" \
  --title "DSH Desktop Launcher $VERSION" \
  --notes "Two formats:

- **DMG** (recommended): open it, drag DSH.app into Applications — first launch auto-installs the helper scripts
- **ZIP**: same app, for scripting/automation" \
  || { /opt/homebrew/bin/gh release create "$VERSION" "$DMG" "$ZIP" --title "DSH Desktop Launcher $VERSION" --notes "Two formats: DMG (recommended) and ZIP."; }

echo "🎉 Done: https://github.com/pixyshu/dsh-desktop-launcher/releases/tag/$VERSION"
