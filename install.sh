#!/bin/bash
# DSH Desktop Launcher 一键安装
# 1) 安装启动/停止脚本到 ~/.dsh
# 2) 构建 dist/DSH.app 并复制到 ~/Applications/DSH.app
set -e
cd "$(dirname "$0")"

echo "→ 安装脚本到 ~/.dsh …"
mkdir -p "$HOME/.dsh"
cp scripts/start-dsh.sh "$HOME/.dsh/start-dsh.sh"
cp scripts/stop-dsh.sh  "$HOME/.dsh/stop-dsh.sh"
chmod +x "$HOME/.dsh/start-dsh.sh" "$HOME/.dsh/stop-dsh.sh"
echo "✅ 脚本已安装"

if [ ! -d "dist/DSH.app" ]; then
  echo "→ 构建应用…"
  bash build.sh
fi

echo "→ 复制应用到 ~/Applications …"
mkdir -p "$HOME/Applications"
rm -rf "$HOME/Applications/DSH.app"
cp -R "dist/DSH.app" "$HOME/Applications/DSH.app"
codesign --force --sign - "$HOME/Applications/DSH.app" >/dev/null 2>&1
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$HOME/Applications/DSH.app" >/dev/null 2>&1

echo ""
echo "🎉 安装完成！"
echo "   1. 打开访达 ~/Applications，把 DSH 拖到程序坞"
echo "   2. 双击鲸鱼/图标：服务自动启动 + 窗口打开"
echo "   3. 点红点关窗：服务自动停止"
echo "   日志：~/.dsh/web-app-3080.log · ~/.dsh/dsh-app-debug.log"
