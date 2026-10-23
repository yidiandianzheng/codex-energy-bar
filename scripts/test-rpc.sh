#!/bin/zsh
set -euo pipefail
ROOT_DIR="${0:A:h:h}"
TEST_DIR=$(mktemp -d "${TMPDIR:-/tmp}/codex-energy-rpc.XXXXXX")
MODULE_CACHE=$(mktemp -d "${TMPDIR:-/tmp}/codex-energy-rpc-clang.XXXXXX")
trap 'rm -rf "$TEST_DIR" "$MODULE_CACHE"' EXIT
cp "$ROOT_DIR/Tests/RPCRegressionTests.swift" "$TEST_DIR/main.swift"
SWIFT_ARGS=(-swift-version 5)
if [[ -n "${CODEX_PET_ENERGY_SDK:-}" ]]; then
    SWIFT_ARGS+=(-sdk "$CODEX_PET_ENERGY_SDK")
fi
swiftc "${SWIFT_ARGS[@]}" \
    -module-cache-path "$MODULE_CACHE" \
    "$ROOT_DIR/Sources/CodexPetEnergy/CodexRateLimitClient.swift" \
    "$ROOT_DIR/Sources/CodexPetEnergy/EnergyModels.swift" \
    "$ROOT_DIR/Sources/CodexPetEnergy/RateLimitResetCreditsSummary.swift" \
    "$ROOT_DIR/Sources/CodexPetEnergy/QuotaLimitReading.swift" \
    "$TEST_DIR/main.swift" -o "$TEST_DIR/rpc-tests"
"$TEST_DIR/rpc-tests"
