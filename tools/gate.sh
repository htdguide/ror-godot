#!/usr/bin/env bash
# Gate runner. The only way gates are invoked.
#
#   tools/gate.sh --list                 list gates, camera presets and scenarios
#   tools/gate.sh <gate> [extra args]    run one gate
#   tools/gate.sh --all [extra args]     run every gate, print a table, non-zero on failure
#   tools/gate.sh --shot <preset>        capture one ad-hoc frame
#
# Extra arguments pass through to the harness, so any gate runs under any weather:
#   tools/gate.sh smoke --weather golden_dusk
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GAME_DIR="$REPO_ROOT/game"
ARTIFACTS="$REPO_ROOT/artifacts"
GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
RESOLUTION="${RESOLUTION:-1920x1080}"
# Fixed frame pacing: a scenario advances by frame count, never by wall-clock time.
FIXED_FPS="${FIXED_FPS:-60}"
# Hard stop so a hung gate fails instead of blocking the suite.
QUIT_AFTER="${QUIT_AFTER:-3600}"
KEEP_RUNS="${KEEP_RUNS:-10}"

if [[ ! -x "$GODOT" ]]; then
    echo "gate.sh: Godot not found at $GODOT (override with GODOT=...)" >&2
    exit 2
fi

bootstrap() {
    # GDScript class_name globals resolve from .godot/global_script_class_cache.cfg,
    # which only an import pass writes. A new class_name is therefore invisible until
    # the project is re-imported, and the symptom is a parse error that reads like a
    # code bug. The runner re-imports whenever a script is newer than the cache.
    local cache="$GAME_DIR/.godot/global_script_class_cache.cfg"
    if [[ ! -f "$cache" ]] || [[ -n "$(find "$GAME_DIR" -name '*.gd' -newer "$cache" -print -quit)" ]]; then
        echo "gate.sh: importing project (script cache stale)..." >&2
        "$GODOT" --path "$GAME_DIR" --headless --import >/dev/null 2>&1
    fi
}

# MOVIE=1 records the run. Godot's --write-movie also pins frame pacing, which is what
# makes a recorded run comparable to a captured still.
movie_args() {
    [[ "${MOVIE:-0}" == "1" ]] || return 0
    mkdir -p "$ARTIFACTS/movies"
    printf -- '--write-movie\n%s\n' "$ARTIFACTS/movies/${MOVIE_NAME:-run}.avi"
}

run_engine() {
    local extra=()
    while IFS= read -r line; do [[ -n "$line" ]] && extra+=("$line"); done < <(movie_args)
    # macOS has no surfaceless GPU path: --headless renders nothing, so image gates
    # need a real window. This is why the dev Mac is the sole authority for pixels.
    "$GODOT" --path "$GAME_DIR" \
        --resolution "$RESOLUTION" \
        --fixed-fps "$FIXED_FPS" \
        --quit-after "$QUIT_AFTER" \
        ${extra[@]+"${extra[@]}"} \
        -- "$@"
}

# Artifacts are pruned, so without this the record of how the project looked is thrown
# away. Every captured frame is copied into history/ under the run's date and commit, and
# nothing there is ever deleted: it is the visual history of the project.
archive_history() {
    [[ -d "$ARTIFACTS" ]] || return 0
    local sha stamp dest
    sha="$(git -C "$REPO_ROOT" rev-parse --short HEAD 2>/dev/null || echo nogit)"
    stamp="$(date +%Y%m%d-%H%M%S)"
    dest="$REPO_ROOT/history/$stamp-$sha"
    local found=0
    while IFS= read -r png; do
        local relative target
        relative="${png#"$ARTIFACTS/"}"
        target="$dest/$relative"
        mkdir -p "$(dirname "$target")"
        cp "$png" "$target"
        found=1
    done < <(find "$ARTIFACTS" -name '*.png' -not -path "*/windows/*" 2>/dev/null)
    [[ $found -eq 1 ]] && echo "history: archived to history/$stamp-$sha" >&2
}

prune_artifacts() {
    [[ -d "$ARTIFACTS" ]] || return 0
    # Artifacts are disposable and bounded: keep the last KEEP_RUNS run directories.
    # BSD head has no negative line count, so drop the newest KEEP_RUNS from a
    # reverse-sorted list instead.
    find "$ARTIFACTS" -maxdepth 1 -type d -name 'run-*' 2>/dev/null | sort -r |
        tail -n "+$((KEEP_RUNS + 1))" | while read -r old; do rm -rf "$old"; done
}

list_gates() {
    find "$GAME_DIR/harness/gates" -name '*.gd' -exec basename {} .gd \; | sort
}

result_field() {
    python3 -c 'import json,sys; print(json.loads(sys.argv[1]).get(sys.argv[2], ""))' "$1" "$2"
}

# A window left open from an earlier run holds the GPU and skews this run's timings.
"$REPO_ROOT/tools/windows.sh" check || exit 3

close_strays() {
    # Belt and braces: --quit-after bounds a hung gate, but a crashed engine can still
    # leave a window behind, and the next run's measurements would inherit it.
    "$REPO_ROOT/tools/windows.sh" kill >/dev/null 2>&1
}
trap close_strays EXIT

bootstrap

case "${1:-}" in
    --list)
        run_engine --list
        ;;
    --shot)
        shift
        run_engine --shot "$@"
        ;;
    --all)
        shift
        failed=0
        printf '%-26s %-6s %-8s %s\n' GATE RESULT ELAPSED DETAIL
        printf '%-26s %-6s %-8s %s\n' "--------------------------" "------" "--------" "------"
        while read -r gate; do
            output="$(run_engine --gate "$gate" "$@" 2>&1)"
            line="$(printf '%s\n' "$output" | grep 'HARNESS_GATE_RESULT ' | tail -1)"
            if [[ -z "$line" ]]; then
                printf '%-26s %-6s %-8s %s\n' "$gate" FAIL - "no result line; engine output below"
                printf '%s\n' "$output" | tail -25 >&2
                failed=1
                continue
            fi
            json="${line#*HARNESS_GATE_RESULT }"
            verdict="$(result_field "$json" pass)"
            elapsed="$(result_field "$json" elapsed_s)"
            detail="$(result_field "$json" detail)"
            if [[ "$verdict" == "True" ]]; then
                printf '%-26s %-6s %-8s %s\n' "$gate" PASS "${elapsed}s" "$detail"
            else
                printf '%-26s %-6s %-8s %s\n' "$gate" FAIL "${elapsed}s" "$detail"
                failed=1
            fi
        done < <(list_gates)
        archive_history
        prune_artifacts
        [[ $failed -eq 0 ]] && echo "all gates passed" || echo "FAILURES present" >&2
        exit "$failed"
        ;;
    "")
        echo "gate.sh: expected a gate name, --all, --list or --shot. Known gates:" >&2
        list_gates >&2
        exit 2
        ;;
    *)
        gate="$1"
        shift
        output="$(run_engine --gate "$gate" "$@" 2>&1)"
        printf '%s\n' "$output"
        archive_history
        prune_artifacts
        printf '%s\n' "$output" | grep -q '"pass":true' || exit 1
        ;;
esac
