#!/bin/bash
# DSH Desktop Launcher one-shot installer
# 0) Checks Node.js (required by the dsh runtime)
# 1) Installs @deepseek-ai/dsh globally when missing
# 2) Installs the start/stop scripts into ~/.dsh
# 3) Builds dist/DSH.app and copies it to ~/Applications/DSH.app
set -e
cd "$(dirname "$0")"

# ---- 0. Node check (present + version >=22.19) ----
if ! command -v node >/dev/null 2>&1; then
  echo "❌ Node.js not found (need >=22.19)."
  echo "   Install it one of these ways:"
  echo "   A. Official installer: https://nodejs.org → download the macOS Installer (.pkg) → double-click"
  echo "   B. Homebrew: brew install node"
  echo "   C. Version manager: npm i -g n && n lts (upgrade an existing install)"
  echo "   Then re-run this script."
  exit 1
fi
if ! node -e 'const [a,b]=process.versions.node.split(".").map(Number);process.exit(a>22||(a===22&&b>=19)?0:1)' 2>/dev/null; then
  echo "❌ Node.js too old (need >=22.19, found $(node -v))."
  echo "   Upgrade: reinstall from https://nodejs.org, or brew upgrade node, or npm i -g n && n lts"
  exit 1
fi
echo "✅ Node.js $(node -v) OK"

# ---- 1. dsh check and auto-install ----
if command -v dsh >/dev/null 2>&1; then
  echo "✅ dsh found: $(command -v dsh)"
elif command -v npm >/dev/null 2>&1; then
  echo "→ dsh not found, installing @deepseek-ai/dsh globally…"
  if npm i -g @deepseek-ai/dsh >/dev/null 2>&1; then
    echo "✅ dsh installed"
  else
    echo "⚠️ Auto-install failed. Run manually: npm i -g @deepseek-ai/dsh"
    echo "   or set DSH_BIN=/path/to/dsh (the start script also falls back to npx, slower on first run)"
  fi
else
  echo "⚠️ dsh not found and no npm: the start script will try the npx fallback (requires npx)."
fi

echo "→ Installing scripts to ~/.dsh …"
mkdir -p "$HOME/.dsh"
cp scripts/start-dsh.sh "$HOME/.dsh/start-dsh.sh"
cp scripts/stop-dsh.sh  "$HOME/.dsh/stop-dsh.sh"
chmod +x "$HOME/.dsh/start-dsh.sh" "$HOME/.dsh/stop-dsh.sh"
echo "✅ Scripts installed"

if [ ! -d "dist/DSH.app" ]; then
  echo "→ Building the app…"
  bash build.sh
fi

echo "→ Copying app to ~/Applications …"
mkdir -p "$HOME/Applications"
rm -rf "$HOME/Applications/DSH.app"
cp -R "dist/DSH.app" "$HOME/Applications/DSH.app"
codesign --force --sign - "$HOME/Applications/DSH.app" >/dev/null 2>&1
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$HOME/Applications/DSH.app" >/dev/null 2>&1

echo ""
echo "🎉 Done!"
echo "   1. Open ~/Applications in Finder and drag DSH to your Dock"
echo "   2. Click the DSH icon: the server starts and the window opens"
echo "   3. Close the window (red button): the server stops"
echo "   Logs: ~/.dsh/web-app-3080.log · ~/.dsh/dsh-app-debug.log"
