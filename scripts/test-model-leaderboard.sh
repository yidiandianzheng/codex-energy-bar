#!/bin/zsh
# 模型榜引擎回归（ModelLeaderboardEngine）
# 纯 Foundation 逻辑，默认 SDK 即可；沙箱内需 --disable-sandbox。
set -euo pipefail
ROOT_DIR="${0:A:h:h}"
TEST_DIR=$(mktemp -d "${TMPDIR:-/tmp}/codex-energy-leaderboard.XXXXXX")
MODULE_CACHE=$(mktemp -d "${TMPDIR:-/tmp}/codex-energy-leaderboard-clang.XXXXXX")
trap 'rm -rf "$TEST_DIR" "$MODULE_CACHE"' EXIT
cp "$ROOT_DIR/Tests/ModelLeaderboardTests.swift" "$TEST_DIR/main.swift"
SWIFT_ARGS=(-swift-version 5)
if [[ -n "${CODEX_PET_ENERGY_SDK:-}" ]]; then
    SWIFT_ARGS+=(-sdk "$CODEX_PET_ENERGY_SDK")
fi
swiftc "${SWIFT_ARGS[@]}" \
    -module-cache-path "$MODULE_CACHE" \
    "$ROOT_DIR/Sources/CodexPetEnergy/ModelLeaderboardModels.swift" \
    "$ROOT_DIR/Sources/CodexPetEnergy/ModelLeaderboardEngine.swift" \
    "$ROOT_DIR/Sources/CodexPetEnergy/ModelLeaderboardClient.swift" \
    "$TEST_DIR/main.swift" -o "$TEST_DIR/leaderboard-tests"
"$TEST_DIR/leaderboard-tests"
