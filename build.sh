#!/bin/bash
# DSH Desktop Launcher 构建脚本
# 产出：dist/DSH.app（可拖入 /Applications 或 ~/Applications 使用）
# 依赖：Xcode 命令行工具（swiftc）。缺少时运行：xcode-select --install
set -e

cd "$(dirname "$0")"

# ---- 前置检查 ----
if ! command -v swiftc >/dev/null 2>&1; then
  echo "❌ 未找到 swiftc。请先安装 Xcode 命令行工具：xcode-select --install" >&2
  exit 1
fi

APP_NAME="DSH"
BUNDLE_ID="com.dsh.app"
BUILD=build
DIST=dist

rm -rf "$BUILD" "$DIST"
mkdir -p "$BUILD" "$DIST/$APP_NAME.app/Contents/MacOS" "$DIST/$APP_NAME.app/Contents/Resources"

# ---- 1. 编译 Swift 应用 ----
echo "→ 编译 Swift 应用…"
swiftc -O -framework Cocoa -framework WebKit src/main.swift -o "$BUILD/$APP_NAME"
cp "$BUILD/$APP_NAME" "$DIST/$APP_NAME.app/Contents/MacOS/$APP_NAME"
echo "✅ 编译完成"

# ---- 2. 图标：优先用自备图标，否则生成占位图标 ----
if [ -f "assets/AppIcon.icns" ]; then
  cp "assets/AppIcon.icns" "$DIST/$APP_NAME.app/Contents/Resources/AppIcon.icns"
  ICON_FILE="AppIcon"
  echo "✅ 使用自备图标 assets/AppIcon.icns"
else
  echo "→ 未提供图标，生成占位图标（建议替换为 assets/AppIcon.icns）"
  # 1x1 纯色 PNG → 512px → icns（sips 直转，比 iconutil 更简单可靠）
  echo 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR4nGP4z8AAAAMBAQDJ/pLvAAAAAElFTkSuQmCC' | base64 -D > "$BUILD/placeholder.png"
  sips -z 512 512 "$BUILD/placeholder.png" --out "$BUILD/icon512.png" >/dev/null 2>&1
  sips -s format icns "$BUILD/icon512.png" --out "$DIST/$APP_NAME.app/Contents/Resources/AppIcon.icns" >/dev/null 2>&1
  ICON_FILE="AppIcon"
  echo "✅ 占位图标已生成"
fi

# ---- 3. 组装应用包 ----
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
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
EOF
printf 'APPL????' > "$DIST/$APP_NAME.app/Contents/PkgInfo"

# ---- 4. 签名（ad-hoc，本地使用足够）----
codesign --force --sign - "$DIST/$APP_NAME.app" >/dev/null 2>&1
codesign -v "$DIST/$APP_NAME.app" && echo "✅ 签名有效"

echo ""
echo "🎉 构建完成：$DIST/$APP_NAME.app"
echo "   下一步：把它拖到「应用程序」文件夹，然后运行 bash install.sh 安装配套脚本"
