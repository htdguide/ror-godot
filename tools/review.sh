#!/usr/bin/env bash
# Hands the map's objects to a person, one at a time, and writes down what they say.
#
#   tools/review.sh                     Port Starling, everything not yet judged
#   tools/review.sh --map lapaz         another map
#   tools/review.sh --map lapaz --again offer the ones already judged as well
#
# Drag to turn the object over, wheel to come closer, R to reset the view, B to paint the back
# of every face. P passes, F fails, left and right arrows move without settling anything.
#
# Why a person: three classes of content show a back face from outside while being exactly right
# — a single-card road sign, two parallel facades with no end walls, a shell with no roof — and
# nothing in a file separates them from a wall that is genuinely turned round. The measurement
# gates count and report; this is where the question gets an answer.
#
# Verdicts go to harness/reference/object_review.json, keyed by mesh file, and an object that has
# one is not offered again.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
RESOLUTION="${RESOLUTION:-1600x900}"

args=()
for token in "$@"; do
    if [[ "$token" == "--map" ]]; then
        args+=("--terrain-dir")
    else
        args+=("$token")
    fi
done

echo "review.sh: opening a window. Close it to end the session."
"$GODOT" --path "$REPO_ROOT" --resolution "$RESOLUTION" -- --review ${args[@]+"${args[@]}"}
