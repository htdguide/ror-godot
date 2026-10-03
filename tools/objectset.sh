#!/usr/bin/env bash
# Photographs each group of an object's faces head-on and assembles a sheet per object.
#
#   tools/objectset.sh                            the six objects Port Starling places most
#   tools/objectset.sh --terrain-dir Russia       another terrain
#   tools/objectset.sh --object store08.mesh      one object by name
#
# Use this whenever an object's geometry is in question. The views are not fixed sides: the gate
# groups the faces by the direction their own normals point and stands the camera on each, so a
# tile holds one surface, labelled with the axis it faces. Any bright primary colour in a tile is
# the back of a face that should have been showing its front.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARTIFACTS="$REPO_ROOT/artifacts/objectset"

"$REPO_ROOT/tools/gate.sh" object_photoset "$@" | grep -E 'HARNESS_GATE_RESULT' || true

command -v ffmpeg >/dev/null || { echo "objectset.sh: ffmpeg not installed" >&2; exit 2; }
[[ -d "$ARTIFACTS" ]] || { echo "objectset.sh: no views were captured" >&2; exit 1; }

sheets=0
for dir in "$ARTIFACTS"/*/; do
    [[ -d "$dir" ]] || continue
    name="$(basename "$dir")"
    list="$(mktemp)"
    count=0
    # Sorted by the group number the gate stamped in the frame, so the sheet reads the same way
    # every time. The `-bare` captures are the stage without the object and are not tiled.
    while IFS= read -r shot; do
        [[ -f "$shot" ]] || continue
        printf "file '%s'\n" "$shot" >> "$list"
        count=$((count + 1))
    done < <(find "$dir" -mindepth 2 -maxdepth 2 -name 'hero_3q.png' \
        -not -path '*-bare/*' | sort -t/ -k2 -V)
    if [[ $count -eq 0 ]]; then
        rm -f "$list"
        continue
    fi
    out="$REPO_ROOT/artifacts/objectset-$name.png"
    ffmpeg -y -loglevel error -f concat -safe 0 -i "$list" \
        -vf "scale=640:-1,tile=3x2:color=0x202020" -frames:v 1 "$out"
    rm -f "$list"
    sheets=$((sheets + 1))
    echo "objectset.sh: $name -> $out"
done
[[ $sheets -eq 0 ]] && { echo "objectset.sh: nothing to assemble" >&2; exit 1; }
echo "objectset.sh: $sheets sheets"
