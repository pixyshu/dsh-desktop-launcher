#!/bin/bash
# DSH server start script (shipped with DSH Desktop Launcher)
# Starts `dsh web` on the given port if nothing is listening, then waits until ready.
# Ownership flag: ~/.dsh/.web-app.<port>.flag — only flagged servers are ever stopped
# on quit, so servers started elsewhere (terminal, ChatGPT, ...) are never killed.
#
# Environment variables:
#   DSH_PORT  listen port (default 3080)
#   DSH_BIN   dsh command or path (default: auto-detect)
#   DSH_NODE  node executable (default: auto-detect)
PORT="${DSH_PORT:-3080}"
LOG="$HOME/.dsh/web-app-$PORT.log"
FLAG="$HOME/.dsh/.web-app-$PORT.flag"
PIDF="$HOME/.dsh/.web-app-$PORT.pid"
LEGACY_PIDF="$HOME/.dsh/.web-app.pid"   # legacy launcher marker; adopted only on 3080

listener() { /usr/sbin/lsof -nP -iTCP:$PORT -sTCP:LISTEN -t 2>/dev/null | head -1; }

# ---- Resolve node (DSH_NODE > n version manager > homebrew/usr-local > PATH) ----
node_bin=""
if [ -n "${DSH_NODE:-}" ] && [ -x "$DSH_NODE" ]; then node_bin="$DSH_NODE"; fi
if [ -z "$node_bin" ]; then
  for c in /usr/local/n/versions/node/*/bin/node /opt/homebrew/bin/node /usr/local/bin/node; do
    [ -x "$c" ] && { node_bin="$c"; break; }
  done
fi
[ -z "$node_bin" ] && node_bin="$(command -v node 2>/dev/null)"
if [ -z "$node_bin" ]; then
  echo "Node.js not found (need >=22.19). Set DSH_NODE=/path/to/node or install from https://nodejs.org" >&2
  exit 1
fi
export PATH="$(dirname "$node_bin"):/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"

# ---- Resolve dsh (DSH_BIN > PATH > npx) ----
if [ -n "${DSH_BIN:-}" ]; then DSH_CMD="$DSH_BIN"
elif command -v dsh >/dev/null 2>&1; then DSH_CMD="$(command -v dsh)"
elif command -v npx >/dev/null 2>&1; then DSH_CMD="npx -y @deepseek-ai/dsh"
else
  echo "dsh not found. Set DSH_BIN=/path/to/dsh or run: npm i -g @deepseek-ai/dsh" >&2
  exit 1
fi

# ---- Already running: reuse; adopt legacy launcher servers on the default port only ----
if [ -n "$(listener)" ]; then
  if [ "$PORT" = "3080" ] && [ -f "$LEGACY_PIDF" ]; then
    rm -f "$LEGACY_PIDF"
    touch "$FLAG"
  fi
  exit 0
fi

# ---- Start and claim ownership ----
/usr/bin/nohup $DSH_CMD web --port "$PORT" >>"$LOG" 2>&1 &
echo $! > "$PIDF"
touch "$FLAG"

# Wait until ready (up to 60s)
for i in $(seq 1 60); do
  [ -n "$(listener)" ] && exit 0
  sleep 1
done
exit 1
