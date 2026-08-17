#!/bin/bash
# DSH Desktop Launcher 一键安装
# 0) 检查 Node.js（dsh 运行时必需）
# 1) 没有 dsh 则自动全局安装 @deepseek-ai/dsh
# 2) 安装启动/停止脚本到 ~/.dsh
# 3) 构建 dist/DSH.app 并复制到 ~/Applications/DSH.app
set -e
cd "$(dirname "$0")"

# ---- 0. Node 检查 ----
if ! command -v node >/dev/null 2>&1; then
  echo "❌ 未找到 Node.js（需要 >=22.19，dsh 运行时必需）。"
  echo "   安装方式：官网 https://nodejs.org 下载，或 brew install node"
  exit 1
fi

# ---- 1. dsh 检查与自动安装 ----
if command -v dsh >/dev/null 2>&1; then
  echo "✅ dsh 已存在：$(command -v dsh)"
elif command -v npm >/dev/null 2>&1; then
  echo "→ 未找到 dsh，自动安装 @deepseek-ai/dsh（全局）…"
  if npm i -g @deepseek-ai/dsh >/dev/null 2>&1; then
    echo "✅ dsh 安装完成"
  else
    echo "⚠️ 自动安装失败。可手动执行：npm i -g @deepseek-ai/dsh"
    echo "   或设置环境变量 DSH_BIN=/path/to/dsh（启动脚本仍会尝试 npx 兜底，首次启动较慢）"
  fi
else
  echo "⚠️ 未找到 dsh 且没有 npm：启动时脚本会尝试 npx 兜底（需 npx 可用）。"
fi

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
