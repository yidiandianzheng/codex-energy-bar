#!/bin/zsh
set -euo pipefail
# Isolated temporary JSONL fixtures only; no live Codex logs or preferences.
ROOT_DIR="${0:A:h:h}"
TEST_DIR=$(mktemp -d "${TMPDIR:-/tmp}/codex-energy-project-usage.XXXXXX")
trap 'rm -rf "$TEST_DIR"' EXIT
cp "$ROOT_DIR/Tests/ProjectUsageRegressionTests.swift" "$TEST_DIR/main.swift"
SWIFT_ARGS=(-swift-version 5)
if [[ -n "${CODEX_PET_ENERGY_SDK:-}" ]]; then
    SWIFT_ARGS+=(-sdk "$CODEX_PET_ENERGY_SDK")
fi
swiftc "${SWIFT_ARGS[@]}" \
    -module-cache-path "$TEST_DIR/clang" \
    "$ROOT_DIR/Sources/CodexPetEnergy/EnergyModels.swift" \
    "$ROOT_DIR/Sources/CodexPetEnergy/RateLimitResetCreditsSummary.swift" \
    "$ROOT_DIR/Sources/CodexPetEnergy/QuotaLimitReading.swift" \
    "$ROOT_DIR/Sources/CodexPetEnergy/ProjectUsageMonitor.swift" \
    "$ROOT_DIR/Sources/CodexPetEnergy/ProjectUsageFileCache.swift" \
    "$ROOT_DIR/Sources/CodexPetEnergy/ProjectUsageSessionAccumulator.swift" \
    "$TEST_DIR/main.swift" -o "$TEST_DIR/project-usage-tests"
"$TEST_DIR/project-usage-tests"
