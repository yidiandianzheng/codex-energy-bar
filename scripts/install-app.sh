#!/bin/zsh
set -euo pipefail

ROOT_DIR="${0:A:h:h}"
SOURCE_APP="${CODEX_PET_ENERGY_BUILD_DIR:-$HOME/Library/Caches/CodexPetEnergy}/算力环.app"
INSTALL_DIR="$HOME/Applications"
INSTALLED_APP="$INSTALL_DIR/算力环.app"

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

LEGACY_APP="$INSTALL_DIR/Ai算力监控.app"
if [[ -d "$LEGACY_APP" ]]; then
  echo "提示：检测到旧名应用 $LEGACY_APP。新版已安装为 $INSTALLED_APP；请手动删除旧应用，并重新执行 scripts/enable-login-item.sh 更新登录自启动。" >&2
fi

echo "$INSTALLED_APP"
