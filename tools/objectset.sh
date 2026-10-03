#!/usr/bin/env bash
# Photographs a terrain's own objects from every side and assembles a sheet per object.
#
#   tools/objectset.sh                            the six objects Port Starling places most
#   tools/objectset.sh --terrain-dir Russia       another terrain
#   tools/objectset.sh --object store08.mesh      one object by name
#
# Use this whenever an object's geometry is in question. A building is a model like any other
# and one angle hides as much of it as it hides of a truck: every building in this library was
# drawn inside out for a day, and from outside a wall was simply absent.
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
    # In the order the gate photographs them, so the sheet reads the same way every time.
    for view in front back left right top three_quarter; do
        shot="$dir$view/hero_3q.png"
        [[ -f "$shot" ]] || continue
        printf "file '%s'\n" "$shot" >> "$list"
        count=$((count + 1))
    done
    if [[ $count -eq 0 ]]; then
        rm -f "$list"
        continue
    fi
    out="$REPO_ROOT/artifacts/objectset-$name.png"
    ffmpeg -y -loglevel error -f concat -safe 0 -i "$list" \
        -vf "scale=640:-1,tile=3x2" -frames:v 1 "$out"
    rm -f "$list"
    sheets=$((sheets + 1))
    echo "objectset.sh: $name -> $out"
done
[[ $sheets -eq 0 ]] && { echo "objectset.sh: nothing to assemble" >&2; exit 1; }
echo "objectset.sh: $sheets sheets"
