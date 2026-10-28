#!/bin/zsh
# 账户网格双排名排序回归（AccountRanking）
# 纯 Foundation 逻辑，默认 SDK 即可；沙箱内需 --disable-sandbox。
set -euo pipefail
ROOT_DIR="${0:A:h:h}"
TEST_DIR=$(mktemp -d "${TMPDIR:-/tmp}/codex-energy-ranking.XXXXXX")
MODULE_CACHE=$(mktemp -d "${TMPDIR:-/tmp}/codex-energy-ranking-clang.XXXXXX")
trap 'rm -rf "$TEST_DIR" "$MODULE_CACHE"' EXIT
cp "$ROOT_DIR/Tests/AccountRankingTests.swift" "$TEST_DIR/main.swift"
SWIFT_ARGS=(-swift-version 5)
if [[ -n "${CODEX_PET_ENERGY_SDK:-}" ]]; then
    SWIFT_ARGS+=(-sdk "$CODEX_PET_ENERGY_SDK")
fi
swiftc "${SWIFT_ARGS[@]}" \
    -module-cache-path "$MODULE_CACHE" \
    "$ROOT_DIR/Sources/CodexPetEnergy/AccountRanking.swift" \
    "$TEST_DIR/main.swift" -o "$TEST_DIR/ranking-tests"
"$TEST_DIR/ranking-tests"
