#!/usr/bin/env bash
# Photographs the test park from every named place and assembles the set into one sheet.
#
#   tools/park_shots.sh                         noon
#   tools/park_shots.sh --weather golden_dusk   any weather preset
#
# Use this whenever a segment of the park changes. The views are numbered so
# that a person looking at the sheet can point at one, and they are named after the anchors in
# config/park_cfg.gd, so moving a feature moves the view that frames it.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARTIFACTS="$REPO_ROOT/artifacts/park"

"$REPO_ROOT/tools/gate.sh" park_photoset "$@" | grep -E 'HARNESS_GATE_RESULT' || true

command -v ffmpeg >/dev/null || { echo "park_shots.sh: ffmpeg not installed" >&2; exit 2; }
list="$(mktemp)"
count=0
for view in 1_spawn 2_patches 3_ramps 4_dips 5_washboard 6_rocks 7_crash_yard 8_skid_pad; do
    shot="$ARTIFACTS/$view/hero_3q.png"
    if [[ -f "$shot" ]]; then
        printf "file '%s'\n" "$shot" >> "$list"
        count=$((count + 1))
    fi
done
[[ $count -eq 0 ]] && { echo "park_shots.sh: no views were captured" >&2; exit 1; }

out="$REPO_ROOT/artifacts/park-sheet.png"
ffmpeg -y -loglevel error -f concat -safe 0 -i "$list" \
    -vf "scale=960:-1,tile=4x2" -frames:v 1 "$out"
rm -f "$list"
echo "park_shots.sh: $count views -> $out"
