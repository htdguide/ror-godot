#!/usr/bin/env bash
# Builds the Terrain3D addon from the pinned submodule and installs it into the project.
#
#   tools/build_terrain3d.sh            build and install for this machine
#   tools/build_terrain3d.sh --clean    remove the installed addon first
#
# The addon is generated, not committed, exactly like our own GDExtension: the pin is the
# submodule commit in vendor/terrain3d, and everything under game/addons/terrain_3d is
# rebuilt from it. A fresh checkout has no terrain until this is run, and the gates that
# need it skip cleanly rather than failing.
#
# Release binaries are published for every platform, but this project is macOS-only for
# now (docs/PLAN.md), and building only what the dev Mac runs keeps 35 MB of Android, iOS,
# Windows, Linux and WebAssembly binaries out of the tree.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE="$REPO_ROOT/vendor/terrain3d"
ADDON_SOURCE="$SOURCE/project/addons/terrain_3d"
ADDON_TARGET="$REPO_ROOT/game/addons/terrain_3d"
# Godot picks the debug library when the editor or a debug build asks for it, so both
# targets are built: a release-only install fails to load under `--gate`.
TARGETS=("template_debug" "template_release")

if [[ "${1:-}" == "--clean" ]]; then
    rm -rf "$ADDON_TARGET"
    echo "build_terrain3d.sh: removed $ADDON_TARGET"
fi

if [[ ! -f "$SOURCE/SConstruct" ]]; then
    echo "build_terrain3d.sh: vendor/terrain3d is empty. Run:" >&2
    echo "    git submodule update --init --depth 1 vendor/terrain3d" >&2
    exit 2
fi
if [[ ! -f "$SOURCE/godot-cpp/SConstruct" ]]; then
    echo "build_terrain3d.sh: Terrain3D's own godot-cpp is missing. Run:" >&2
    echo "    git -C vendor/terrain3d submodule update --init --depth 1 godot-cpp" >&2
    exit 2
fi

pin="$(git -C "$SOURCE" rev-parse HEAD)"
echo "build_terrain3d.sh: building Terrain3D at $pin"
for target in "${TARGETS[@]}"; do
    ( cd "$SOURCE" && scons "target=$target" -j"$(sysctl -n hw.ncpu)" ) || {
        echo "build_terrain3d.sh: scons failed for $target" >&2
        exit 1
    }
done

mkdir -p "$ADDON_TARGET"
# Everything the addon needs, binaries included. rsync rather than cp so a rebuild replaces
# what changed instead of leaving a stale library behind.
rsync -a --delete "$ADDON_SOURCE/" "$ADDON_TARGET/"
echo "build_terrain3d.sh: installed to ${ADDON_TARGET#"$REPO_ROOT"/}"
find "$ADDON_TARGET/bin" -type f \( -name '*.dylib' -o -name 'libterrain.macos*' \) -print 2>/dev/null | sed 's|^|    |'
