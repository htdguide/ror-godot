#!/usr/bin/env bash
# Photographs the valley from every named place and assembles the set into one sheet.
#
#   tools/valley_shots.sh                       noon
#   tools/valley_shots.sh --weather golden_dusk any weather preset
#
# Use this whenever the terrain, the water or the layout changes. The views are numbered so
# that a person looking at the sheet can point at one, and they are named after the anchors in
# world/valley_one_layout.gd, so moving a feature moves the view that frames it.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARTIFACTS="$REPO_ROOT/artifacts/valley"

"$REPO_ROOT/tools/gate.sh" valley_photoset "$@" | grep -E 'HARNESS_GATE_RESULT' || true

command -v ffmpeg >/dev/null || { echo "valley_shots.sh: ffmpeg not installed" >&2; exit 2; }
list="$(mktemp)"
count=0
for view in 1_spawn 2_ford 3_lake 4_ruts 5_rock_traverse 6_switchback 7_ridge_vista; do
    shot="$ARTIFACTS/$view/hero_3q.png"
    if [[ -f "$shot" ]]; then
        printf "file '%s'\n" "$shot" >> "$list"
        count=$((count + 1))
    fi
done
[[ $count -eq 0 ]] && { echo "valley_shots.sh: no views were captured" >&2; exit 1; }

out="$REPO_ROOT/artifacts/valley-sheet.png"
ffmpeg -y -loglevel error -f concat -safe 0 -i "$list" \
    -vf "scale=960:-1,tile=4x2" -frames:v 1 "$out"
rm -f "$list"
echo "valley_shots.sh: $count views -> $out"
