#!/usr/bin/env bash
# Window bookkeeping for this repository's Godot processes.
#
# Every engine run opens a real window: macOS has no surfaceless GPU path, so image
# gates cannot run headless. A window left open holds the GPU, skews the next run's
# timings, and clutters the desktop, so every run is tracked and nothing is left behind.
#
#   tools/windows.sh list    show this repo's running Godot processes
#   tools/windows.sh kill    close all of them
#   tools/windows.sh check   exit non-zero if any are running (used before a gate run)
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GAME_DIR="$REPO_ROOT/game"

repo_pids() {
    # Match only engines started against this project, never the user's other Godot work.
    pgrep -f "Godot.*--path $GAME_DIR" 2>/dev/null || true
}

case "${1:-list}" in
    list)
        pids="$(repo_pids)"
        if [[ -z "$pids" ]]; then
            echo "no Godot windows open for this repository"
            exit 0
        fi
        printf '%-8s %-8s %s\n' PID ELAPSED COMMAND
        for pid in $pids; do
            printf '%-8s %-8s %s\n' "$pid" \
                "$(ps -o etime= -p "$pid" | tr -d ' ')" \
                "$(ps -o command= -p "$pid" | cut -c1-90)"
        done
        ;;
    kill)
        pids="$(repo_pids)"
        [[ -z "$pids" ]] && { echo "nothing to close"; exit 0; }
        for pid in $pids; do
            echo "closing $pid"
            kill "$pid" 2>/dev/null
        done
        sleep 1
        for pid in $(repo_pids); do
            echo "force closing $pid" >&2
            kill -9 "$pid" 2>/dev/null
        done
        ;;
    check)
        pids="$(repo_pids)"
        if [[ -n "$pids" ]]; then
            echo "windows.sh: Godot already running for this repo (pids: $(echo $pids | tr '\n' ' '))" >&2
            echo "windows.sh: close them with 'tools/windows.sh kill' before measuring anything" >&2
            exit 1
        fi
        ;;
    *)
        echo "usage: windows.sh [list|kill|check]" >&2
        exit 2
        ;;
esac
