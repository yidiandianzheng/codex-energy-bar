#!/bin/zsh
set -euo pipefail

ROOT_DIR="${0:A:h:h}"
APP_NAME="算力环"
BUILD_DIR="${CODEX_PET_ENERGY_BUILD_DIR:-$HOME/Library/Caches/CodexPetEnergy}"
APP_DIR="$BUILD_DIR/$APP_NAME.app"

cd "$ROOT_DIR"
BUILD_ARGS=(-c release -j 1 --disable-index-store --build-system native)
# Nested sandbox environments (CI/agent runners) cannot apply SwiftPM's own
# build sandbox; opt out explicitly instead of patching the script per run.
if [[ "${CODEX_PET_ENERGY_DISABLE_SANDBOX:-0}" == "1" ]]; then
    BUILD_ARGS+=(--disable-sandbox)
fi
SDK="${CODEX_PET_ENERGY_SDK:-$(xcrun --show-sdk-path)}"
BUILD_ARGS+=(--sdk "$SDK")
if [[ -n "${CODEX_PET_ENERGY_SWIFT_BUILD_PATH:-}" ]]; then
    BUILD_ARGS+=(--scratch-path "$CODEX_PET_ENERGY_SWIFT_BUILD_PATH")
fi
swift build "${BUILD_ARGS[@]}"
BIN_DIR=$(swift build "${BUILD_ARGS[@]}" --show-bin-path)

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BIN_DIR/CodexPetEnergy" "$APP_DIR/Contents/MacOS/CodexPetEnergy"
cp "$ROOT_DIR/Resources/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
cp "$ROOT_DIR/Resources/AppLogo.png" "$APP_DIR/Contents/Resources/AppLogo.png"
cp "$ROOT_DIR/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"
# 构建日期写进 App 包，标题栏与「关于」用它显示“构建 2026-10-23”。
# 源码里的 Info.plist 不写死日期，方便复现构建；需要指定日期时用 CODEX_PET_ENERGY_BUILD_DATE。
BUILD_DATE="${CODEX_PET_ENERGY_BUILD_DATE:-$(TZ=Asia/Shanghai date +%Y-%m-%d)}"
/usr/libexec/PlistBuddy -c "Delete :CFBundleBuildDate" "$APP_DIR/Contents/Info.plist" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :CFBundleBuildDate string $BUILD_DATE" "$APP_DIR/Contents/Info.plist"
xattr -cr "$APP_DIR"
codesign --force --deep --sign - "$APP_DIR"
xattr -cr "$APP_DIR"
codesign --verify --deep --strict "$APP_DIR"

echo "$APP_DIR"
