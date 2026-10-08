#!/usr/bin/env bash
# The eight money shots as one sheet: the project's current state, for a person to judge.
#
#   tools/money_shots.sh [extra gate args]
#
# Runs the `money_shots` gate, which places every frame from a feature the terrain declares, then
# tiles the eight captures 4x2 into artifacts/money-shots-sheet.png. Compare sheets across
# commits with `tools/history.sh`, which archives artifacts per commit.
set -uo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARTIFACTS="$REPO_ROOT/artifacts/money_shots"
# A sheet is of one run: frames left by an earlier run on another terrain must not fill in for
# frames this run did not reach.
rm -rf "$ARTIFACTS"
"$REPO_ROOT/tools/gate.sh" money_shots "$@" | grep -E 'HARNESS_GATE_RESULT|money_shots ' | cut -c1-400
command -v ffmpeg >/dev/null || { echo "money_shots.sh: ffmpeg not installed" >&2; exit 1; }
list="$(mktemp)"
count=0
for shot in $(ls -d "$ARTIFACTS"/[1-8]_* 2>/dev/null | sort); do
    png="$shot/hero_3q.png"
    if [[ -f "$png" ]]; then
        printf "file '%s'\n" "$png" >> "$list"
        count=$((count + 1))
    fi
done
[[ $count -eq 0 ]] && { echo "money_shots.sh: no frames were captured" >&2; exit 1; }
out="$REPO_ROOT/artifacts/money-shots-sheet.png"
ffmpeg -y -loglevel error -f concat -safe 0 -i "$list" -vf "scale=960:-1,tile=4x2" -frames:v 1 "$out"
rm -f "$list"
echo "money_shots.sh: $count frames -> $out"
