#!/bin/bash
# Builds a drag-to-install DMG from dist/DSH.app
# Usage: bash make-dmg.sh [version]   (version defaults to 1.0.0)
set -e
cd "$(dirname "$0")"

APP_NAME="DSH"
VERSION="${1:-1.0.0}"
STAGE="build/dmg-staging"
DMG="dist/DSH-Desktop-Launcher-${VERSION}-macos-universal.dmg"

if [ ! -d "dist/$APP_NAME.app" ]; then
  echo "dist/$APP_NAME.app not found — run bash build.sh first" >&2
  exit 1
fi

rm -rf "$STAGE"
mkdir -p "$STAGE"

# Standard drag-to-install layout: the app + an Applications shortcut
cp -R "dist/$APP_NAME.app" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

# Volume icon (from the app icon; best-effort)
if [ -f "dist/$APP_NAME.app/Contents/Resources/AppIcon.icns" ]; then
  cp "dist/$APP_NAME.app/Contents/Resources/AppIcon.icns" "$STAGE/.VolumeIcon.icns"
fi
/usr/bin/SetFile -a C "$STAGE" 2>/dev/null || true

/usr/bin/hdiutil create \
  -volname "DSH Desktop Launcher" \
  -srcfolder "$STAGE" \
  -ov \
  -format UDZO \
  "$DMG" >/dev/null

rm -rf "$STAGE"
echo "✅ DMG built: $DMG"
