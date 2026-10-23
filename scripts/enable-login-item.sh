#!/bin/zsh
set -euo pipefail

ROOT_DIR="${0:A:h:h}"
APP_PATH="${1:-$HOME/Applications/算力环.app}"
APP_PATH="${APP_PATH:A}"
EXECUTABLE="$APP_PATH/Contents/MacOS/CodexPetEnergy"
PLIST="$HOME/Library/LaunchAgents/com.local.codex-pet-energy.plist"
DOMAIN="gui/$(id -u)"

if [[ ! -x "$EXECUTABLE" ]]; then
  echo "找不到已构建的应用：$APP_PATH" >&2
  exit 1
fi

mkdir -p "${PLIST:h}"
rm -f "$PLIST"
plutil -create xml1 "$PLIST"
plutil -insert Label -string "com.local.codex-pet-energy" "$PLIST"
plutil -insert ProgramArguments -json "[\"$EXECUTABLE\"]" "$PLIST"
plutil -insert RunAtLoad -bool true "$PLIST"
plutil -insert KeepAlive -bool false "$PLIST"

launchctl bootout "$DOMAIN" "$PLIST" 2>/dev/null || true
launchctl bootstrap "$DOMAIN" "$PLIST"
echo "已开启登录自动启动。"
