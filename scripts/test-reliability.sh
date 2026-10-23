#!/bin/zsh
set -euo pipefail
ROOT_DIR="${0:A:h:h}"
TEST_DIR=$(mktemp -d "${TMPDIR:-/tmp}/compute-ring-reliability.XXXXXX")
trap 'rm -rf "$TEST_DIR"' EXIT
cp "$ROOT_DIR/Tests/ReliabilityTests.swift" "$TEST_DIR/main.swift"
SWIFT_ARGS=(-swift-version 5 -sdk "${CODEX_PET_ENERGY_SDK:-$(xcrun --show-sdk-path)}")
mkdir -p "$TEST_DIR/clang"
swiftc "${SWIFT_ARGS[@]}" -module-cache-path "$TEST_DIR/clang" \
  "$ROOT_DIR/Sources/CodexPetEnergy/BalanceModels.swift" \
  "$ROOT_DIR/Sources/CodexPetEnergy/QuotaLimitReading.swift" \
  "$ROOT_DIR/Sources/CodexPetEnergy/BalanceConfig.swift" \
  "$ROOT_DIR/Sources/CodexPetEnergy/BalanceMonitor.swift" \
  "$ROOT_DIR/Sources/CodexPetEnergy/DeepSeekBalanceClient.swift" \
  "$ROOT_DIR/Sources/CodexPetEnergy/DoubaoBalanceClient.swift" \
  "$ROOT_DIR/Sources/CodexPetEnergy/WorkBuddyBalanceClient.swift" \
  "$ROOT_DIR/Sources/CodexPetEnergy/ResetRadarSources.swift" \
  "$ROOT_DIR/Sources/CodexPetEnergy/ResetReferenceForecast.swift" \
  "$ROOT_DIR/Sources/CodexPetEnergy/ResetRadarSnapshot.swift" \
  "$ROOT_DIR/Sources/CodexPetEnergy/ResetRadarClient.swift" \
  "$ROOT_DIR/Sources/CodexPetEnergy/ResetRadarSelfTest.swift" \
  "$ROOT_DIR/Sources/CodexPetEnergy/CompactPointerTracking.swift" \
  "$ROOT_DIR/Sources/CodexPetEnergy/CompactActionTarget.swift" \
  "$ROOT_DIR/Sources/CodexPetEnergy/EnergyPanelMode.swift" \
  "$TEST_DIR/main.swift" -lsqlite3 -o "$TEST_DIR/reliability-tests"
"$TEST_DIR/reliability-tests"
