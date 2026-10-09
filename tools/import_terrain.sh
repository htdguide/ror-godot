#!/usr/bin/env bash
# Puts a Rigs of Rods terrain into this checkout's terrain library.
#
#   tools/import_terrain.sh <archive.zip>     unpack an archive into the maps library
#   tools/import_terrain.sh <directory>       copy an unpacked terrain in
#   tools/import_terrain.sh --list            what the library holds
#
# A terrain is a directory with a .terrn2 in it. Nothing is converted and nothing is
# registered: the library is the filesystem, so a terrain is playable the moment it is here.
#
# Terrain content is not committed — the repository's mods carry varied and often unstated
# licensing — so this is a local step, like fetching a vehicle.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIBRARY="$REPO_ROOT/$("$REPO_ROOT/tools/profile.sh" maps)"
GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"

list_terrains() {
    if [[ ! -x "$GODOT" ]]; then
        echo "import_terrain.sh: Godot not found at $GODOT (override with GODOT=...)" >&2
        ls -1 "$LIBRARY" 2>/dev/null
        return 0
    fi
    "$GODOT" --headless --path "$REPO_ROOT" --script res://harness/dev/list_terrains.gd 2>/dev/null \
        | grep -v "^Godot Engine"
}

if [[ $# -lt 1 || "$1" == "--help" || "$1" == "-h" ]]; then
    sed -n '2,12p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
    exit 0
fi

if [[ "$1" == "--list" ]]; then
    list_terrains
    exit 0
fi

source_path="$1"
if [[ ! -e "$source_path" ]]; then
    echo "import_terrain.sh: no such file or directory: $source_path" >&2
    exit 2
fi

name="$(basename "$source_path")"
name="${name%.zip}"
name="${name%.ZIP}"
destination="$LIBRARY/$name"

if [[ -e "$destination" ]]; then
    echo "import_terrain.sh: $destination already exists; remove it first" >&2
    exit 2
fi

mkdir -p "$destination"
if [[ -d "$source_path" ]]; then
    cp -R "$source_path"/ "$destination"/
else
    unzip -q -o "$source_path" -d "$destination" || {
        echo "import_terrain.sh: could not unpack $source_path" >&2
        rm -rf "$destination"
        exit 2
    }
fi

# Archives from the repository sometimes wrap everything in one directory. A terrain is
# wherever its .terrn2 is, so if that turned up one level down, that level is the terrain.
terrn2="$(find "$destination" -maxdepth 2 -iname '*.terrn2' -print -quit)"
if [[ -z "$terrn2" ]]; then
    echo "import_terrain.sh: no .terrn2 in $source_path — that is not a terrain" >&2
    rm -rf "$destination"
    exit 2
fi
inner="$(dirname "$terrn2")"
if [[ "$inner" != "$destination" ]]; then
    mv "$inner"/* "$destination"/ && rmdir "$inner" 2>/dev/null
fi

echo "import_terrain.sh: $name is in the library"
echo "  tools/play.sh --truck --map $name"
