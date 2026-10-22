#!/bin/zsh
set -euo pipefail
ROOT_DIR="${0:A:h:h}"
cd "$ROOT_DIR"
SDK="${CODEX_PET_ENERGY_SDK:-$(xcrun --show-sdk-path)}"
FIXTURE_DIR="${1:-$ROOT_DIR/.build/mini-layout-snapshots}"
TEST_BINARY=$(mktemp -t codex-mini-layout)
trap 'rm -f "$TEST_BINARY"' EXIT
SOURCES=(Sources/CodexPetEnergy/*.swift)
SOURCES=(${SOURCES:#Sources/CodexPetEnergy/main.swift})
swiftc -parse-as-library -sdk "$SDK" "${SOURCES[@]}" Tests/MiniLayoutSnapshots.swift -o "$TEST_BINARY"
"$TEST_BINARY" "$FIXTURE_DIR"
