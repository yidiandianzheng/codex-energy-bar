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
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict><key>CFBundleIdentifier</key><string>local.compute-ring.dashboard-demo</string><key>CFBundleExecutable</key><string>DashboardDemo</string><key>CFBundlePackageType</key><string>APPL</string></dict></plist>
PLIST
SOURCES=(Sources/CodexPetEnergy/*.swift)
SOURCES=(${SOURCES:#Sources/CodexPetEnergy/main.swift})
swiftc -parse-as-library -sdk "$SDK" -module-cache-path "$TEST_ROOT/cache" "${SOURCES[@]}" Tests/DashboardSnapshots.swift -o "$APP/Contents/MacOS/DashboardDemo"
"$APP/Contents/MacOS/DashboardDemo" "$FIXTURE_DIR" "${@:2}"
