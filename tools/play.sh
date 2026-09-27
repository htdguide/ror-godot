#!/usr/bin/env bash
# Hands the machine to a human: opens a real window and lets the user drive.
#
#   tools/play.sh                        default preset, windowed
#   tools/play.sh --shot diag_grid_wide  start from a named camera preset
#   tools/play.sh --weather golden_dusk  any weather or time-of-day preset
#   tools/play.sh --truck                the hero vehicle in the test park, to drive
#   tools/play.sh --truck --valley       the same vehicle on Valley One instead
#   tools/play.sh --truck --map <name>   the same vehicle on a Rigs of Rods terrain from
#                                        assets/terrains/<name> (tools/import_terrain.sh --list)
#   tools/play.sh --truck --no-terrain   the same vehicle on a bare flat plane
#
# The window is tracked while it lives and the tracking file is removed on exit, so a
# session can never be forgotten: tools/windows.sh list always tells the truth.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GAME_DIR="$REPO_ROOT/game"
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

# --truck is shorthand: loading the hero vehicle is the common reason to open a window, and
# a vehicle with nowhere to drive is not much of a session, so it brings a world with it. The
# test park is that world by default; --valley asks for Valley One, and --map <name> for a Rigs
# of Rods terrain from the library under assets/terrains/, loaded from the files its author
# shipped.
args=("$@")
want_terrain=0
for i in "${!args[@]}"; do
    if [[ "${args[$i]}" == "--truck" ]]; then
        args[$i]="--vehicle"
        args=("${args[@]:0:$((i+1))}" "assets/mods/ChevyS1023:S10offroad.truck" "${args[@]:$((i+1))}")
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
args=("${args[@]}")
[[ $want_terrain -eq 1 ]] && args+=("--terrain")

printf '{"pid": %d, "purpose": "human session", "started": "%s", "args": "%s"}\n' \
    "$$" "$(date -u +%FT%TZ)" "$*" > "$track_file"

echo "play.sh: opening a window. Close it to end the session."
"$GODOT" --path "$GAME_DIR" --resolution "$RESOLUTION" -- --play ${args[@]+"${args[@]}"} &
engine_pid=$!
wait "$engine_pid"
