#!/bin/bash
# DSH 服务启动脚本（通用发行版）
# 行为：目标端口未占用时才启动 `dsh web` 并等待就绪；已占用则复用。
# 归属标记 ~/.dsh/.web-app.<port>.flag —— 只有带标记的服务，关窗时才会被停止，
# 绝不误杀其他来源（终端/ChatGPT 等）启动的服务。
#
# 环境变量：
#   DSH_PORT  监听端口，默认 3080
#   DSH_BIN   dsh 命令（或完整路径），默认自动解析
#   DSH_NODE  node 可执行文件路径，默认自动解析
PORT="${DSH_PORT:-3080}"
LOG="$HOME/.dsh/web-app-$PORT.log"
FLAG="$HOME/.dsh/.web-app-$PORT.flag"
PIDF="$HOME/.dsh/.web-app-$PORT.pid"
LEGACY_PIDF="$HOME/.dsh/.web-app.pid"   # 旧版启动器遗留标记，仅在 3080 上接管

listener() { /usr/sbin/lsof -nP -iTCP:$PORT -sTCP:LISTEN -t 2>/dev/null | head -1; }

# ---- 解析 node（DSH_NODE > n 版本管理器 > homebrew/usr-local > PATH）----
node_bin=""
if [ -n "${DSH_NODE:-}" ] && [ -x "$DSH_NODE" ]; then node_bin="$DSH_NODE"; fi
if [ -z "$node_bin" ]; then
  for c in /usr/local/n/versions/node/*/bin/node /opt/homebrew/bin/node /usr/local/bin/node; do
    [ -x "$c" ] && { node_bin="$c"; break; }
  done
fi
[ -z "$node_bin" ] && node_bin="$(command -v node 2>/dev/null)"
if [ -z "$node_bin" ]; then
  echo "未找到 Node.js（>=22.19）。可用 DSH_NODE=/path/to/node 指定。安装：https://nodejs.org" >&2
  exit 1
fi
export PATH="$(dirname "$node_bin"):/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"

# ---- 解析 dsh（DSH_BIN > PATH > npx）----
if [ -n "${DSH_BIN:-}" ]; then DSH_CMD="$DSH_BIN"
elif command -v dsh >/dev/null 2>&1; then DSH_CMD="$(command -v dsh)"
elif command -v npx >/dev/null 2>&1; then DSH_CMD="npx -y @deepseek-ai/dsh"
else
  echo "未找到 dsh 命令。可用 DSH_BIN=/path/to/dsh 指定，或运行：npm i -g @deepseek-ai/dsh" >&2
  exit 1
fi

# ---- 已运行：复用；仅在默认端口接管旧版遗留服务 ----
if [ -n "$(listener)" ]; then
  if [ "$PORT" = "3080" ] && [ -f "$LEGACY_PIDF" ]; then
    rm -f "$LEGACY_PIDF"
    touch "$FLAG"
  fi
  exit 0
fi

# ---- 启动并标记归属 ----
/usr/bin/nohup $DSH_CMD web --port "$PORT" >>"$LOG" 2>&1 &
echo $! > "$PIDF"
touch "$FLAG"

# 等待就绪（最多 60 秒）
for i in $(seq 1 60); do
  [ -n "$(listener)" ] && exit 0
  sleep 1
done
exit 1
