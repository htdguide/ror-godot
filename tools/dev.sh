#!/usr/bin/env bash
# One window, open all day, that gates and commands run inside.
#
#   tools/dev.sh                 open the window and leave it open
#   tools/dev.sh --map lapaz     open it on a terrain
#
# The window serves the console (` or F1) and the agent's drop box. Nothing closes it but `quit`
# in the console, Ctrl-C here, or closing the window.
#
# Once it is up, `tools/send.sh "<command>"` runs a command in it rather than launching a second
# engine — which is the point: `gate run rig_steers` in a window that is already warm is under a
# second, where a fresh engine pays startup, shader compilation and terrain import first.
#
# **This is the development loop, not the release run.** Renderer state warms across a process:
# shader compilation, probe capture timing, deferred frees. A rendered measurement moves in its
# fourth decimal because of it, which `tools/gate.sh --order-check` measures and reports on every
# run. For a number that goes in a commit message, use `tools/gate.sh --all --every`, which
# starts fresh.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
RESOLUTION="${RESOLUTION:-1600x900}"
TRACK_DIR="$REPO_ROOT/artifacts/windows"

mkdir -p "$TRACK_DIR" "$REPO_ROOT/artifacts/console/in"
track_file="$TRACK_DIR/dev-$$.json"
cleanup() {
    rm -f "$track_file"
    [[ -n "${engine_pid:-}" ]] && kill "$engine_pid" 2>/dev/null
}
trap cleanup EXIT INT TERM

printf '{"pid": %d, "purpose": "dev session", "started": "%s", "args": "%s"}\n' \
    "$$" "$(date -u +%FT%TZ)" "$*" > "$track_file"

echo "dev.sh: one window, staying open. \` or F1 for the console, 'quit' to close."
echo "dev.sh: from another shell:  tools/send.sh \"gate run smoke\""
"$GODOT" --path "$REPO_ROOT" --resolution "$RESOLUTION" -- --console ${@+"$@"} &
engine_pid=$!
wait "$engine_pid"
