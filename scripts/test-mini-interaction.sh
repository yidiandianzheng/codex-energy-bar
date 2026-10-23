#!/bin/zsh
set -euo pipefail
ROOT_DIR="${0:A:h:h}"
cd "$ROOT_DIR"
SDK="${CODEX_PET_ENERGY_SDK:-$(xcrun --show-sdk-path)}"
TEST_ROOT=$(mktemp -d -t compute-ring-mini-interaction)
trap 'rm -rf "$TEST_ROOT"' EXIT
SOURCES=(Sources/CodexPetEnergy/*.swift)
SOURCES=(${SOURCES:#Sources/CodexPetEnergy/main.swift})
swiftc -parse-as-library -sdk "$SDK" -module-cache-path "$TEST_ROOT/cache" "${SOURCES[@]}" Tests/MiniLayoutSnapshots.swift -o "$TEST_ROOT/MiniInteraction"
if (( $# )); then
    "$TEST_ROOT/MiniInteraction" "$@"
else
    "$TEST_ROOT/MiniInteraction" --interaction-only
fi
