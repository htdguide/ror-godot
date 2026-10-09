#!/usr/bin/env bash
# An exported build of the game, from this checkout, for a platform this machine does not run.
#
#   tools/release.sh windows        release/ror-godot-windows-<sha>.zip
#   tools/release.sh macos          release/ror-godot-macos-<sha>.zip, an ad-hoc signed .app
#
# What goes in the zip is two kinds of thing. The pack Godot exports holds everything the project
# reads through `res://`: scripts, shaders, the HDRIs. Everything this project reads by absolute
# path — Rigs of Rods' base content under vendor/rigs-of-rods/resources, the loading picture, the
# mods/ and maps/ folders a person fills — sits beside the executable as plain files, because an
# exported build's root is the folder beside its executable (`SourceScan.repo_root`). A shipped
# build is the production build whatever checkout made it (`BuildProfile`).
#
# Needs: Godot 4.7.2 with its export templates installed, mingw-w64 (`brew install mingw-w64`)
# for the solver's DLL, and Terrain3D's Windows binaries from its own release under
# addons/terrain_3d/bin (`tools/build_terrain3d.sh --windows` fetches them).
set -uo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
PLATFORM="${1:-}"
case "$PLATFORM" in windows|macos) ;; *) sed -n '2,16p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 2 ;; esac

SHA="$(git -C "$REPO_ROOT" rev-parse --short HEAD)"
PROFILE="$("$REPO_ROOT/tools/profile.sh")"
OUT="$REPO_ROOT/release/$PLATFORM"
ZIP="$REPO_ROOT/release/ror-godot-$PLATFORM-$SHA.zip"
TEMPLATES="$HOME/Library/Application Support/Godot/export_templates/4.7.2.stable"

[[ -d "$TEMPLATES" ]] || { echo "release.sh: no export templates at $TEMPLATES" >&2; exit 1; }
[[ "$PROFILE" == "prod" ]] || echo "release.sh: note: this checkout is $PROFILE; the build ships as prod regardless"

# What the game reads beside its executable, laid beside whatever the exporter wrote.
beside_the_executable() {
    mkdir -p "$OUT/vendor/rigs-of-rods" "$OUT/assets/ui" "$OUT/mods" "$OUT/maps"
    rsync -a "$REPO_ROOT/vendor/rigs-of-rods/resources/" "$OUT/vendor/rigs-of-rods/resources/"
    [[ -f "$REPO_ROOT/assets/ui/loading.png" ]] && cp "$REPO_ROOT/assets/ui/loading.png" "$OUT/assets/ui/"
    cp "$REPO_ROOT/mods/README.md" "$OUT/mods/" && cp "$REPO_ROOT/maps/README.md" "$OUT/maps/"
    cp -R "$REPO_ROOT/LICENSES" "$OUT/" && cp "$REPO_ROOT/THIRD_PARTY.md" "$REPO_ROOT/LICENSE"* "$OUT/" 2>/dev/null
    cat > "$OUT/README.txt" <<TXT
ror-godot $SHA, $PLATFORM (production build)

Run $1. Vehicles go in mods/, one unpacked folder per pack; maps go in maps/, one unpacked
folder per terrain. Nothing is bundled. Esc opens the panel: Drive and World list what is in
those folders; Settings is the weather and everything about the scene.

GPL-3.0-or-later; see THIRD_PARTY.md and LICENSES/ for what this build is made of.
TXT
}

if [[ "$PLATFORM" == "macos" ]]; then
    echo "release.sh: building the solver's release library for macOS"
    ( cd "$REPO_ROOT/extension" && scons target=template_release -j"$(sysctl -n hw.ncpu)" ) || exit 1
    [[ -f "$REPO_ROOT/bin/librorbridge.macos.template_release.universal.dylib" ]] || { echo "release.sh: the dylib was not built" >&2; exit 1; }
    rm -rf "$OUT" && mkdir -p "$OUT"
    echo "release.sh: exporting"
    "$GODOT" --path "$REPO_ROOT" --headless --export-release "macOS" "$OUT/ror-godot.app" 2>&1 | grep -iv "^$\|savepack\|^\[" | tail -5
    [[ -d "$OUT/ror-godot.app/Contents/MacOS" ]] || { echo "release.sh: export produced no .app" >&2; exit 1; }
    beside_the_executable "ror-godot.app"
    rm -f "$ZIP"
    ( cd "$REPO_ROOT/release" && zip -qry "$(basename "$ZIP")" macos ) || exit 1
    echo "release.sh: $ZIP ($(du -h "$ZIP" | cut -f1))"
    ls "$OUT"
    exit 0
fi

command -v x86_64-w64-mingw32-g++ >/dev/null || { echo "release.sh: mingw-w64 not installed" >&2; exit 1; }
for dll in libterrain.windows.release.x86_64.dll libterrain.windows.debug.x86_64.dll; do
    [[ -f "$REPO_ROOT/addons/terrain_3d/bin/$dll" ]] || {
        echo "release.sh: no $dll under addons/terrain_3d/bin; run tools/build_terrain3d.sh --windows" >&2; exit 1; }
done
echo "release.sh: building the solver for Windows"
( cd "$REPO_ROOT/extension" && scons platform=windows arch=x86_64 use_mingw=yes target=template_release -j"$(sysctl -n hw.ncpu)" ) || exit 1
[[ -f "$REPO_ROOT/bin/librorbridge.windows.template_release.x86_64.dll" ]] || { echo "release.sh: the DLL was not built" >&2; exit 1; }

rm -rf "$OUT" && mkdir -p "$OUT"
echo "release.sh: exporting"
"$GODOT" --path "$REPO_ROOT" --headless --export-release "Windows Desktop" "$OUT/ror-godot.exe" 2>&1 | grep -v "^$" | tail -5
[[ -f "$OUT/ror-godot.exe" && -f "$OUT/ror-godot.pck" ]] || { echo "release.sh: export produced no exe and pck" >&2; exit 1; }

beside_the_executable "ror-godot.exe"

rm -f "$ZIP"
( cd "$REPO_ROOT/release" && zip -qr "$(basename "$ZIP")" windows ) || exit 1
echo "release.sh: $ZIP ($(du -h "$ZIP" | cut -f1))"
ls "$OUT"
