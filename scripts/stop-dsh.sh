#!/bin/bash
# DSH 服务停止脚本（通用发行版）
# - 只停"自己启动"的服务（以 ~/.dsh/.web-app.<port>.flag 归属标记为准）
# - 按"当前监听端口的进程"停止（不依赖记录 PID，避免错位）
# - 幂等：无标记或已无监听时直接退出 0
# - 竞态兜底：关窗时服务可能还在启动中（尚未监听），最多再等 10 秒
# 环境变量：DSH_PORT，默认 3080
PORT="${DSH_PORT:-3080}"
FLAG="$HOME/.dsh/.web-app-$PORT.flag"
PIDF="$HOME/.dsh/.web-app-$PORT.pid"

listener() { /usr/sbin/lsof -nP -iTCP:$PORT -sTCP:LISTEN -t 2>/dev/null | head -1; }

# 没有归属标记 = 不是我们启动的，绝不误杀
[ -f "$FLAG" ] || exit 0
rm -f "$FLAG" "$PIDF"

stop_listener() {
  local pid="$1"
  [ -n "$pid" ] || return 0
  kill -TERM "$pid" 2>/dev/null
  for i in $(seq 1 5); do
    /usr/sbin/lsof -nP -iTCP:$PORT -sTCP:LISTEN >/dev/null 2>&1 || return 0
    sleep 1
  done
  kill -KILL "$pid" 2>/dev/null
  return 0
}

# 常规路径：已有监听进程 → 直接停（实测 TERM 后端口即刻释放，秒停）
L0=$(listener)
if [ -n "$L0" ]; then
  stop_listener "$L0"
else
  # 竞态兜底：只有"停止时服务尚未监听"才等待（启动中的竞态），最多 10 秒
  for i in $(seq 1 10); do
    L=$(listener)
    [ -n "$L" ] && { stop_listener "$L"; break; }
    sleep 1
  done
fi
exit 0
