#!/bin/zsh
set -euo pipefail

# Regression tests for the extra balance sources (DeepSeek / 豆包 / WorkBuddy / 千问办公).
# Parsing only: no network, no keychain and no WorkBuddy IPC is touched.

ROOT_DIR="${0:A:h:h}"
TEST_DIR=$(mktemp -d "${TMPDIR:-/tmp}/codex-energy-balance.XXXXXX")
trap 'rm -rf "$TEST_DIR"' EXIT

cp "$ROOT_DIR/Tests/BalanceParsingTests.swift" "$TEST_DIR/main.swift"

SWIFT_ARGS=(-swift-version 5)
if [[ -n "${CODEX_PET_ENERGY_SDK:-}" ]]; then
    SWIFT_ARGS+=(-sdk "$CODEX_PET_ENERGY_SDK")
fi

mkdir -p "$TEST_DIR/clang"

swiftc "${SWIFT_ARGS[@]}" \
    -module-cache-path "$TEST_DIR/clang" \
    "$ROOT_DIR/Sources/CodexPetEnergy/BalanceModels.swift" \
    "$ROOT_DIR/Sources/CodexPetEnergy/QuotaLimitReading.swift" \
    "$ROOT_DIR/Sources/CodexPetEnergy/AccountVisibility.swift" \
    "$ROOT_DIR/Sources/CodexPetEnergy/UsageAdvisor.swift" \
    "$ROOT_DIR/Sources/CodexPetEnergy/DeepSeekBalanceClient.swift" \
    "$ROOT_DIR/Sources/CodexPetEnergy/WorkBuddyBalanceClient.swift" \
    "$ROOT_DIR/Sources/CodexPetEnergy/QwenWorkBalanceClient.swift" \
    "$ROOT_DIR/Sources/CodexPetEnergy/DoubaoBalanceClient.swift" \
    "$TEST_DIR/main.swift" \
    -lsqlite3 \
    -o "$TEST_DIR/balance-tests"

"$TEST_DIR/balance-tests"
