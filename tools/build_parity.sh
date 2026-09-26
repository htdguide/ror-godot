#!/usr/bin/env bash
# Builds the upstream parity oracle: Rigs of Rods' own physics, compiled on its own.
#
#   tools/build_parity.sh
#
# The oracle exists to answer one question no gate of ours can: are our force laws the same
# arithmetic as upstream's, or only the same shape? It is built from the pinned submodule
# every time, never from a copy, so it cannot drift from what it claims to be.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
UPSTREAM="$REPO_ROOT/vendor/rigs-of-rods/source"
PARITY="$REPO_ROOT/tools/parity"
BUILD="$REPO_ROOT/build/parity"
BINARY="$BUILD/upstream_oracle"

if [[ ! -d "$UPSTREAM/main/physics" ]]; then
    echo "build_parity.sh: vendor/rigs-of-rods is empty. Run:" >&2
    echo "    git submodule update --init --depth 1 vendor/rigs-of-rods" >&2
    exit 2
fi

mkdir -p "$BUILD"
python3 "$PARITY/extract.py" "$UPSTREAM" "$BUILD/upstream_generated.cpp" || exit 1

# -ffp-contract=off so the compiler does not fuse multiply-adds. A fused multiply-add is more
# accurate than the two operations it replaces, which is exactly wrong here: the oracle has to
# reproduce upstream's arithmetic, not improve on it.
clang++ -std=c++17 -O2 -ffp-contract=off \
    -I"$PARITY/shim" -I"$UPSTREAM/main/physics" \
    "$PARITY/oracle.cpp" "$BUILD/upstream_generated.cpp" \
    -o "$BINARY" || { echo "build_parity.sh: compile failed" >&2; exit 1; }

echo "build_parity.sh: built ${BINARY#"$REPO_ROOT"/}"
printf '%s\n' "$(git -C "$REPO_ROOT/vendor/rigs-of-rods" rev-parse HEAD)" > "$BUILD/upstream.pin"
