#!/bin/bash
# DSH Desktop Launcher build script
# Output: dist/DSH.app (drag into /Applications or ~/Applications)
# Requires: Xcode Command Line Tools (swiftc). Install with: xcode-select --install
set -e

cd "$(dirname "$0")"

# ---- Prerequisites ----
if ! command -v swiftc >/dev/null 2>&1; then
  echo "❌ swiftc not found. Install Xcode Command Line Tools: xcode-select --install" >&2
  exit 1
fi

APP_NAME="DSH"
BUNDLE_ID="com.dsh.app"
BUILD=build
DIST=dist

rm -rf "$BUILD" "$DIST"
mkdir -p "$BUILD" "$DIST/$APP_NAME.app/Contents/MacOS" "$DIST/$APP_NAME.app/Contents/Resources"

# ---- 1. Compile the Swift app ----
echo "→ Compiling Swift app…"
swiftc -O -framework Cocoa -framework WebKit src/main.swift -o "$BUILD/$APP_NAME"
cp "$BUILD/$APP_NAME" "$DIST/$APP_NAME.app/Contents/MacOS/$APP_NAME"
echo "✅ Compiled"

# ---- 2. Icon: use assets/AppIcon.icns when present, otherwise generate a placeholder ----
if [ -f "assets/AppIcon.icns" ]; then
  cp "assets/AppIcon.icns" "$DIST/$APP_NAME.app/Contents/Resources/AppIcon.icns"
  ICON_FILE="AppIcon"
  echo "✅ Using assets/AppIcon.icns"
else
  echo "→ No icon provided, generating a placeholder (replace with assets/AppIcon.icns)"
  # 1x1 solid PNG → 512px → icns (direct sips conversion, more reliable than iconutil)
  echo 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR4nGP4z8AAAAMBAQDJ/pLvAAAAAElFTkSuQmCC' | base64 -D > "$BUILD/placeholder.png"
  sips -z 512 512 "$BUILD/placeholder.png" --out "$BUILD/icon512.png" >/dev/null 2>&1
  sips -s format icns "$BUILD/icon512.png" --out "$DIST/$APP_NAME.app/Contents/Resources/AppIcon.icns" >/dev/null 2>&1
  ICON_FILE="AppIcon"
  echo "✅ Placeholder icon generated"
fi

# ---- 3. Assemble the bundle ----
cat > "$DIST/$APP_NAME.app/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>$APP_NAME</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleName</key><string>$APP_NAME</string>
  <key>CFBundleDisplayName</key><string>DeepSeek Harness</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleIconFile</key><string>$ICON_FILE</string>
  <key>CFBundleShortVersionString</key><string>1.0.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleLocalizations</key><array><string>en</string><string>zh-Hans</string></array>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
EOF
printf 'APPL????' > "$DIST/$APP_NAME.app/Contents/PkgInfo"

# ---- 3b. Declare zh-Hans localization (lets system-injected menu items
#           like "Emoji & Symbols" / "Close All" follow the app language) ----
mkdir -p "$DIST/$APP_NAME.app/Contents/Resources/zh-Hans.lproj"
printf '' > "$DIST/$APP_NAME.app/Contents/Resources/zh-Hans.lproj/Localizable.strings"

# ---- 4. Sign (ad-hoc, sufficient for local use) ----
codesign --force --sign - "$DIST/$APP_NAME.app" >/dev/null 2>&1
codesign -v "$DIST/$APP_NAME.app" && echo "✅ Signature valid"

echo ""
echo "🎉 Built: $DIST/$APP_NAME.app"
echo "   Next: drag it into Applications, then run bash install.sh to install the scripts"
