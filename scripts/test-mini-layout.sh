#!/bin/zsh
set -euo pipefail
ROOT_DIR="${0:A:h:h}"
cd "$ROOT_DIR"
SDK="${CODEX_PET_ENERGY_SDK:-$(xcrun --show-sdk-path)}"
FIXTURE_DIR="${1:-$ROOT_DIR/.build/mini-layout-snapshots}"
TEST_BINARY=$(mktemp -t codex-mini-layout)
MODULE_CACHE=$(mktemp -d -t codex-mini-layout-clang)
trap 'rm -f "$TEST_BINARY"; rm -rf "$MODULE_CACHE"' EXIT
SOURCES=(Sources/CodexPetEnergy/*.swift)
SOURCES=(${SOURCES:#Sources/CodexPetEnergy/main.swift})
swiftc -parse-as-library -sdk "$SDK" -module-cache-path "$MODULE_CACHE" "${SOURCES[@]}" Tests/MiniLayoutSnapshots.swift -o "$TEST_BINARY"
"$TEST_BINARY" "$FIXTURE_DIR"
