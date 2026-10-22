#!/bin/zsh
set -euo pipefail

ROOT_DIR="${0:A:h:h}"
SOURCE_APP="${CODEX_PET_ENERGY_BUILD_DIR:-$HOME/Library/Caches/CodexPetEnergy}/Codex算力条.app"
INSTALL_DIR="$HOME/Applications"
INSTALLED_APP="$INSTALL_DIR/Codex算力条.app"

"$ROOT_DIR/scripts/build-app.sh" >/dev/null
mkdir -p "$INSTALL_DIR"
pkill -x CodexPetEnergy || true
rm -rf "$INSTALLED_APP"
ditto "$SOURCE_APP" "$INSTALLED_APP"
xattr -cr "$INSTALLED_APP"
codesign --verify --deep --strict "$INSTALLED_APP"
SOURCE_HASH=$(shasum -a 256 "$SOURCE_APP/Contents/MacOS/CodexPetEnergy" | awk '{print $1}')
INSTALL_HASH=$(shasum -a 256 "$INSTALLED_APP/Contents/MacOS/CodexPetEnergy" | awk '{print $1}')
[[ "$SOURCE_HASH" == "$INSTALL_HASH" ]] || { echo "安装版二进制校验失败" >&2; exit 1; }

echo "$INSTALLED_APP"
