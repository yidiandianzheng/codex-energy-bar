#!/bin/zsh
set -euo pipefail
ROOT_DIR="${0:A:h:h}"
cd "$ROOT_DIR"
SDK="${CODEX_PET_ENERGY_SDK:-$(xcrun --show-sdk-path)}"
FIXTURE_DIR="${1:-$ROOT_DIR/.build/dashboard-layout-snapshots}"
TEST_ROOT=$(mktemp -d -t compute-ring-dashboard-demo)
trap 'rm -rf "$TEST_ROOT"' EXIT
APP="$TEST_ROOT/DashboardDemo.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Resources/AppLogo.png "$APP/Contents/Resources/AppLogo.png"
# 演示包沿用发布的版本信息，让快照里的标题栏显示真实版本、构建号和构建日期。
cp Resources/Info.plist "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier local.compute-ring.dashboard-demo" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleExecutable DashboardDemo" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Delete :CFBundleBuildDate" "$APP/Contents/Info.plist" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :CFBundleBuildDate string ${CODEX_PET_ENERGY_BUILD_DATE:-$(TZ=Asia/Shanghai date +%Y-%m-%d)}" "$APP/Contents/Info.plist"
SOURCES=(Sources/CodexPetEnergy/*.swift)
SOURCES=(${SOURCES:#Sources/CodexPetEnergy/main.swift})
swiftc -parse-as-library -sdk "$SDK" -module-cache-path "$TEST_ROOT/cache" "${SOURCES[@]}" Tests/DashboardSnapshots.swift -o "$APP/Contents/MacOS/DashboardDemo"
"$APP/Contents/MacOS/DashboardDemo" "$FIXTURE_DIR" "${@:2}"
