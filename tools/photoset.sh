#!/usr/bin/env bash
# Photographs the vehicle from every side and assembles the set into one sheet.
#
#   tools/photoset.sh            the hero vehicle
#
# Use this whenever model geometry is in question. A single view hides too much: this
# project has had a door that looked open, a tailgate that looked missing and panels that
# looked transparent, each obvious from a view nobody was taking.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARTIFACTS="$REPO_ROOT/artifacts/photoset"

"$REPO_ROOT/tools/gate.sh" vehicle_photoset "$@" | grep -E 'HARNESS_GATE_RESULT' || true

command -v ffmpeg >/dev/null || { echo "photoset.sh: ffmpeg not installed" >&2; exit 2; }
# Views are labelled in-frame by the gate itself, because ffmpeg's drawtext filter is
# absent from some builds, including this one.
list="$(mktemp)"
count=0
for view in front back left right top bottom three_quarter interior; do
    shot="$ARTIFACTS/$view/hero_3q.png"
    if [[ -f "$shot" ]]; then
        printf "file '%s'\n" "$shot" >> "$list"
        count=$((count + 1))
    fi
done
[[ $count -eq 0 ]] && { echo "photoset.sh: no views were captured" >&2; exit 1; }

out="$REPO_ROOT/artifacts/photoset-sheet.png"
ffmpeg -y -loglevel error -f concat -safe 0 -i "$list" \
    -vf "scale=960:-1,tile=4x2" -frames:v 1 "$out"
rm -f "$list"
echo "photoset.sh: $count views -> $out"
