#!/usr/bin/env bash
# Hands the machine to a human: opens a real window and lets the user drive.
#
#   tools/play.sh                        default preset, windowed
#   tools/play.sh --shot diag_grid_wide  start from a named camera preset
#   tools/play.sh --weather golden_dusk  any weather or time-of-day preset
#   tools/play.sh --truck                the hero vehicle on the map Rigs of Rods itself ships
#   tools/play.sh --truck --map <name>   the same vehicle on another Rigs of Rods terrain
#                                        (tools/import_terrain.sh --list says what there is)
#   tools/play.sh --truck --no-terrain   the same vehicle on a bare flat plane
#   tools/play.sh --truck --collision    what the terrain is solid as, drawn over everything: a
#                                        box with nothing in it is geometry that is missing, and
#                                        drawn geometry with no box is something you drive through
#   tools/play.sh --truck --facing       scenery dressed in the object gates' facing paint: a
#                                        face keeps its texture from the front and draws its axis
#                                        in a primary colour from behind, so a wall turned the
#                                        wrong way is bright instead of absent
#
# The window is tracked while it lives and the tracking file is removed on exit, so a
# session can never be forgotten: tools/windows.sh list always tells the truth.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_DIR="$REPO_ROOT"
GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
RESOLUTION="${RESOLUTION:-1600x900}"
TRACK_DIR="$REPO_ROOT/artifacts/windows"

mkdir -p "$TRACK_DIR"
track_file="$TRACK_DIR/play-$$.json"
cleanup() {
    rm -f "$track_file"
    # Never leave the engine running if this script dies.
    [[ -n "${engine_pid:-}" ]] && kill "$engine_pid" 2>/dev/null
}
trap cleanup EXIT INT TERM

# --truck is shorthand: loading the hero vehicle is the common reason to open a window, and a
# vehicle with nowhere to drive is not much of a session, so it brings a world with it. Every
# world is a Rigs of Rods terrain loaded from the files its author shipped. With no --map that
# is the one the game itself ships, which is in the tree as a submodule and therefore present
# on any clone; --map <name> picks another from the library under assets/terrains/.
args=("$@")
want_terrain=0
for i in "${!args[@]}"; do
    if [[ "${args[$i]}" == "--truck" ]]; then
        args[$i]="--vehicle"
        # The hero, wherever this build keeps its vehicles. A build without it opens with none.
        hero="$("$REPO_ROOT/tools/profile.sh" mods)/ChevyS1023"
        if [[ -f "$REPO_ROOT/$hero/S10offroad.truck" ]]; then
            args=("${args[@]:0:$((i+1))}" "$hero:S10offroad.truck" "${args[@]:$((i+1))}")
        else
            echo "play.sh: no hero vehicle at $hero; opening without one (Drive tab lists what there is)"
            unset 'args[i]'
        fi
        want_terrain=1
        break
    fi
done
for i in "${!args[@]}"; do
    if [[ "${args[$i]}" == "--map" ]]; then
        args[$i]="--terrain-dir"
        want_terrain=1
        break
    fi
done
for i in "${!args[@]}"; do
    if [[ "${args[$i]}" == "--no-terrain" ]]; then
        unset 'args[i]'
        want_terrain=0
    fi
done
# Reindexed after the unsets; the `+` form keeps `set -u` quiet when nothing is left, which is
# a production build opened with no hero to open.
args=(${args[@]+"${args[@]}"})
[[ $want_terrain -eq 1 ]] && args+=("--terrain")

printf '{"pid": %d, "purpose": "human session", "started": "%s", "args": "%s"}\n' \
    "$$" "$(date -u +%FT%TZ)" "$*" > "$track_file"

echo "play.sh: opening a $("$REPO_ROOT/tools/profile.sh") window. Close it to end the session."
"$GODOT" --path "$PROJECT_DIR" --resolution "$RESOLUTION" -- --play ${args[@]+"${args[@]}"} &
engine_pid=$!
wait "$engine_pid"
