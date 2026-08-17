#!/bin/bash
# DSH server stop script (shipped with DSH Desktop Launcher)
# - Only stops servers this launcher started (ownership flag: ~/.dsh/.web-app.<port>.flag)
# - Stops the actual port listener, not a recorded PID (PIDs can drift)
# - Idempotent: exits 0 when there is no flag or no listener
# - Race guard: if the server was still starting when the window closed, waits up to 10s for it
# Environment variable: DSH_PORT (default 3080)
PORT="${DSH_PORT:-3080}"
FLAG="$HOME/.dsh/.web-app-$PORT.flag"
PIDF="$HOME/.dsh/.web-app-$PORT.pid"

listener() { /usr/sbin/lsof -nP -iTCP:$PORT -sTCP:LISTEN -t 2>/dev/null | head -1; }

# No ownership flag = not ours, never kill
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

# Normal path: a listener exists, stop it (measured: port frees instantly after TERM)
L0=$(listener)
if [ -n "$L0" ]; then
  stop_listener "$L0"
else
  # Race guard: only wait when nothing was listening yet (server still booting), 10s max
  for i in $(seq 1 10); do
    L=$(listener)
    [ -n "$L" ] && { stop_listener "$L"; break; }
    sleep 1
  done
fi
exit 0
