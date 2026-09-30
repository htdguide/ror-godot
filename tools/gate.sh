#!/usr/bin/env bash
# Gate runner. The only way gates are invoked.
#
#   tools/gate.sh --list                 list gates, camera presets and scenarios
#   tools/gate.sh --chain                print the gate graph: what builds on what
#   tools/gate.sh <gate> [extra args]    run one gate
#   tools/gate.sh --all [extra args]     run the suite highest tier first, skipping what a
#                                        passing gate implies; non-zero on failure
#   tools/gate.sh --order-check [seed]   every gate twice, in the graph's order and in a seeded
#                                        shuffle, comparing verdicts AND measured values. The
#                                        acceptance test for the gate containers.
#   tools/gate.sh --all --every          run every gate, ignoring the graph. What a release
#                                        run uses: it is the only thing that catches an edge
#                                        that was never true
#   tools/gate.sh --why <gate>           run one gate and, if it fails, walk down everything it
#                                        builds on until the lowest failing gate is found
#   tools/gate.sh --shot <preset>        capture one ad-hoc frame
#
# Extra arguments pass through to the harness, so any gate runs under any weather:
#   tools/gate.sh smoke --weather golden_dusk
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_DIR="$REPO_ROOT"
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
    local cache="$PROJECT_DIR/.godot/global_script_class_cache.cfg"
    if [[ ! -f "$cache" ]] || [[ -n "$(find "$PROJECT_DIR" -name '*.gd' -newer "$cache" -print -quit)" ]]; then
        echo "gate.sh: importing project (script cache stale)..." >&2
        "$GODOT" --path "$PROJECT_DIR" --headless --import >/dev/null 2>&1
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
    "$GODOT" --path "$PROJECT_DIR" \
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
    find "$PROJECT_DIR/harness/gates" -name '*.gd' -exec basename {} .gd \; | sort
}

result_field() {
    python3 -c 'import json,sys; print(json.loads(sys.argv[1]).get(sys.argv[2], ""))' "$1" "$2"
}


# --------------------------------------------------------------------------------
# Scheduling from the gate graph.
#
# A gate may declare the gates whose claims its own claim contains (`builds_on`). Two things
# follow, and the suite uses both: a passing gate implies everything under it, so that a run does
# not re-prove that a cube renders after a whole vehicle has; and a failing gate is a reason to
# run what is under it, until the lowest failing gate says which level the fault is at.
#
# The graph is a set of claims about claims that nothing can check automatically, so `--every`
# ignores it and runs everything. An implied gate is reported as implied and never as passed.

CHAIN_FILE=""
RESULTS_FILE=""
IMPLIED_FILE=""

cleanup_plan() {
    [[ -n "$CHAIN_FILE" ]] && rm -f "$CHAIN_FILE"
    [[ -n "$RESULTS_FILE" ]] && rm -f "$RESULTS_FILE"
    [[ -n "$IMPLIED_FILE" ]] && rm -f "$IMPLIED_FILE"
    return 0
}

load_chain() {
    CHAIN_FILE="$(mktemp)"
    run_engine --chain 2>/dev/null | grep 'HARNESS_CHAIN ' | tail -1 > "$CHAIN_FILE"
    if [[ ! -s "$CHAIN_FILE" ]]; then
        echo "gate.sh: the engine printed no gate graph" >&2
        exit 3
    fi
}

plan() {
    python3 "$REPO_ROOT/tools/gate_plan.py" "$@" --chain "$CHAIN_FILE"
}

# Runs one gate and leaves its verdict in VERDICT, ELAPSED and DETAIL.
VERDICT=""
ELAPSED=""
DETAIL=""
run_one() {
    local gate="$1"
    shift
    local output line json
    output="$(run_engine --gate "$gate" "$@" 2>&1)"
    line="$(printf '%s\n' "$output" | grep 'HARNESS_GATE_RESULT ' | tail -1)"
    if [[ -z "$line" ]]; then
        VERDICT=FAIL
        ELAPSED="-"
        DETAIL="no result line; engine output below"
        printf '%s\n' "$output" | tail -25 >&2
        return
    fi
    json="${line#*HARNESS_GATE_RESULT }"
    if [[ "$(result_field "$json" pass)" == "True" ]]; then VERDICT=PASS; else VERDICT=FAIL; fi
    ELAPSED="$(result_field "$json" elapsed_s)s"
    DETAIL="$(result_field "$json" detail)"
}

# Runs a whole list of gates in ONE engine invocation, which is one window, and leaves their
# verdicts in BATCH_FILE as `gate<TAB>verdict<TAB>elapsed<TAB>detail`.
#
# The engine opens a fresh container per gate, so batching changes which window a gate runs in
# and nothing about what it measures. `harness/dev/gate_container.gd` is what makes that true and
# `gates_are_order_independent` is what checks it.
BATCH_FILE=""
run_batch() {
    local gates="$1"
    shift
    local output
    BATCH_FILE="$(mktemp)"
    output="$(run_engine --gate "$gates" "$@" 2>&1)"
    printf '%s\n' "$output" | grep 'HARNESS_GATE_RESULT ' |
        python3 -c '
import json, sys
for line in sys.stdin:
    row = json.loads(line.split("HARNESS_GATE_RESULT ", 1)[1])
    verdict = "PASS" if row.get("pass") else "FAIL"
    elapsed = row.get("elapsed_s", "-")
    print("\t".join([
        row.get("gate", "?"), verdict,
        ("%ss" % elapsed) if elapsed != "-" else "-",
        str(row.get("detail", "")).replace("\t", " "),
        repr(row.get("measured")),
    ]))
' > "$BATCH_FILE"
    if [[ ! -s "$BATCH_FILE" ]]; then
        printf '%s\n' "$output" | tail -25 >&2
    fi
}

# The verdict a batch recorded for one gate, or a synthetic failure when the engine died before
# reaching it -- which is the case a per-gate runner reported for free and a batch has to state.
batch_row() {
    local gate="$1" row
    row="$(grep -F "$gate	" "$BATCH_FILE" 2>/dev/null | head -1)"
    if [[ -z "$row" ]]; then
        printf '%s\tFAIL\t-\tno result: the engine did not reach this gate (see output above)\tNone\n' "$gate"
        return
    fi
    printf '%s\n' "$row"
}

table_header() {
    printf '%-26s %-7s %-8s %s\n' GATE RESULT ELAPSED DETAIL
    printf '%-26s %-7s %-8s %s\n' "--------------------------" "-------" "--------" "------"
}

run_suite() {
    local every="$1"
    shift
    load_chain
    RESULTS_FILE="$(mktemp)"
    IMPLIED_FILE="$(mktemp)"
    local failed=0 ran=0 implied=0 windows=0
    table_header
    # One batch per tier, and one window per batch. A tier is safe to batch because `builds_on`
    # edges run from a higher tier to a lower one, so no gate in a tier implies another in the
    # same tier: nothing in a batch depends on a result from the same batch.
    while IFS= read -r tier; do
        [[ -n "$tier" ]] || continue
        local todo="" name
        while IFS= read -r name; do
            [[ -n "$name" ]] || continue
            local implier=""
            if [[ "$every" -eq 0 ]]; then
                implier="$(grep -F "	$name	" "$IMPLIED_FILE" 2>/dev/null | head -1 | cut -f3)"
            fi
            if [[ -n "$implier" ]]; then
                printf '%-26s %-7s %-8s %s\n' "$name" IMPLIED "-" "implied by $implier, which passed"
                printf '%s\t%s\n' "$name" "IMPLIED" >> "$RESULTS_FILE"
                implied=$((implied + 1))
                continue
            fi
            todo="${todo:+$todo,}$name"
        done < <(printf '%s' "$tier" | tr '\t' '\n')
        [[ -n "$todo" ]] || continue
        run_batch "$todo" "$@"
        windows=$((windows + 1))
        while IFS= read -r name; do
            [[ -n "$name" ]] || continue
            IFS=$'\t' read -r _g verdict elapsed detail _measured < <(batch_row "$name")
            ran=$((ran + 1))
            printf '%-26s %-7s %-8s %s\n' "$name" "$verdict" "$elapsed" "$detail"
            printf '%s\t%s\n' "$name" "$verdict" >> "$RESULTS_FILE"
            if [[ "$verdict" == "PASS" ]]; then
                if [[ "$every" -eq 0 ]]; then
                    while read -r covered; do
                        [[ -n "$covered" ]] || continue
                        printf '\t%s\t%s\n' "$covered" "$name" >> "$IMPLIED_FILE"
                    done < <(plan implied "$name")
                fi
            else
                failed=1
            fi
        done < <(printf '%s' "$todo" | tr ',' '\n')
        rm -f "$BATCH_FILE"
    done < <(plan tiers)
    archive_history
    prune_artifacts
    if [[ $failed -eq 0 ]]; then
        printf '%d gates run in %d windows, %d implied by a higher gate; all passed' \
            "$ran" "$windows" "$implied"
        if [[ $implied -gt 0 ]]; then
            printf ' (run --all --every to check the implied ones)'
        fi
        printf '\n'
        cleanup_plan
        return 0
    fi
    echo "FAILURES present" >&2
    report_localization
    cleanup_plan
    return 1
}

# Order independence: the acceptance test for the gate containers themselves.
#
# Every gate, twice, in one window each: once in the graph's own order and once in a seeded
# shuffle. Same verdicts and the same measured values, or a container is not containing something
# and the suite's results depend on what ran before them. Verdicts alone are too weak -- a number
# that drifts inside a threshold is the same bug one release before it fails.
run_order_check() {
    local seed="${1:-7}"
    local forward shuffled first second
    first="$(mktemp)"
    second="$(mktemp)"
    forward="$(list_gates | tr '\n' ',' | sed 's/,$//')"
    shuffled="$(list_gates | python3 -c "
import random, sys
gates = [line.strip() for line in sys.stdin if line.strip()]
random.Random($seed).shuffle(gates)
print(','.join(gates))
")"
    echo "order check: $(list_gates | wc -l | tr -d ' ') gates, twice, one window each (seed $seed)" >&2
    run_batch "$forward"
    cp "$BATCH_FILE" "$first"
    rm -f "$BATCH_FILE"
    run_batch "$shuffled"
    cp "$BATCH_FILE" "$second"
    rm -f "$BATCH_FILE"
    python3 - "$first" "$second" << 'ORDER_EOF'
import sys

def rows(path):
    out = {}
    with open(path) as handle:
        for line in handle:
            parts = line.rstrip("\n").split("\t")
            if len(parts) >= 5:
                out[parts[0]] = (parts[1], parts[4])
    return out

# How far a measured value may move between the two orders.
#
# Zero for anything computed, and it holds: those compare bit for bit. Not zero for anything
# rendered, and the reason is measured rather than assumed -- `ror_terrain_photoset` returns a
# mean luma over seven rendered views of La Paz and produced 0.282191, 0.282165, 0.282781 and
# 0.282671 across four runs, in the same order and in different ones. Renderer state that warms
# across a process -- shader compilation, probe capture timing, deferred frees -- is outside what
# a container can isolate, and this gate's own threshold is "no view is black", which none of
# those numbers comes close to moving.
#
# So the bound is tight enough to catch a real dependence and loose enough to admit that limit,
# and the worst drift is always printed, pass or fail, so a gate that starts drifting further is
# visible before it crosses.
TOLERANCE = 1e-3


def as_float(text):
    try:
        return float(text)
    except (TypeError, ValueError):
        return None


a, b = rows(sys.argv[1]), rows(sys.argv[2])
problems = []
worst, worst_gate = 0.0, ""
for gate in sorted(set(a) | set(b)):
    if gate not in a or gate not in b:
        problems.append("%s ran in only one of the two orders" % gate)
        continue
    if a[gate][0] != b[gate][0]:
        problems.append("%s: %s in order, %s shuffled" % (gate, a[gate][0], b[gate][0]))
        continue
    first, second = as_float(a[gate][1]), as_float(b[gate][1])
    if first is None or second is None:
        if a[gate][1] != b[gate][1]:
            problems.append(
                "%s: measured %s in order, %s shuffled" % (gate, a[gate][1], b[gate][1])
            )
        continue
    scale = max(abs(first), abs(second), 1e-12)
    drift = abs(first - second) / scale
    if drift > worst:
        worst, worst_gate = drift, gate
    if drift > TOLERANCE:
        problems.append(
            "%s: measured %r in order, %r shuffled (%.2g relative, over %g)"
            % (gate, first, second, drift, TOLERANCE)
        )
if problems:
    print("ORDER CHECK FAILED -- a gate depends on what ran before it:")
    for problem in problems:
        print("  " + problem)
    raise SystemExit(1)
print(
    "order check passed: %d gates, identical verdicts in both orders; worst measured drift"
    " %.2g (%s), under %g" % (len(a), worst, worst_gate or "none", TOLERANCE)
)
ORDER_EOF
    local status=$?
    rm -f "$first" "$second"
    return $status
}

# Where the fault is, rather than everything downstream of it: for each failing gate, the lowest
# gate under it that also failed.
report_localization() {
    local lines
    lines="$(plan localize --results "$RESULTS_FILE")"
    [[ -n "$lines" ]] || return 0
    echo "" >&2
    echo "where the fault is:" >&2
    printf '%s\n' "$lines" | while IFS=$'\t' read -r top lowest note; do
        if [[ "$top" == "$lowest" ]]; then
            echo "  $top failed and nothing it builds on did: the fault is at its own level" >&2
        else
            echo "  $top failed because $lowest failed under it ($note)" >&2
        fi
    done
}

# One gate, and the chain under it when it fails. This is the question "is it this gate, or
# something it is built on?" asked directly.
run_why() {
    local gate="$1"
    shift
    load_chain
    RESULTS_FILE="$(mktemp)"
    table_header
    run_one "$gate" "$@"
    printf '%-26s %-7s %-8s %s\n' "$gate" "$VERDICT" "$ELAPSED" "$DETAIL"
    printf '%s\t%s\n' "$gate" "$VERDICT" >> "$RESULTS_FILE"
    if [[ "$VERDICT" == "PASS" ]]; then
        archive_history
        prune_artifacts
        echo "$gate passed; nothing under it needed running"
        cleanup_plan
        return 0
    fi
    local walked=0
    while read -r covered; do
        [[ -n "$covered" ]] || continue
        walked=$((walked + 1))
        run_one "$covered" "$@"
        printf '%-26s %-7s %-8s %s\n' "$covered" "$VERDICT" "$ELAPSED" "$DETAIL"
        printf '%s\t%s\n' "$covered" "$VERDICT" >> "$RESULTS_FILE"
    done < <(plan closure "$gate")
    archive_history
    prune_artifacts
    if [[ $walked -eq 0 ]]; then
        echo "" >&2
        echo "$gate builds on nothing: the fault is at its own level" >&2
    else
        report_localization
    fi
    cleanup_plan
    return 1
}

# A window left open from an earlier run holds the GPU and skews this run's timings.
"$REPO_ROOT/tools/windows.sh" check || exit 3

close_strays() {
    cleanup_plan
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
        every=0
        extra=()
        for arg in "$@"; do
            if [[ "$arg" == "--every" ]]; then every=1; else extra+=("$arg"); fi
        done
        run_suite "$every" ${extra[@]+"${extra[@]}"}
        exit "$?"
        ;;
    --order-check)
        shift
        run_order_check "${1:-}"
        exit "$?"
        ;;
    --chain)
        load_chain
        python3 "$REPO_ROOT/tools/gate_plan.py" order --chain "$CHAIN_FILE" | while read -r gate; do
            deps="$(plan implied "$gate" | tr '\n' ' ')"
            printf '%-30s %s\n' "$gate" "${deps:-(builds on nothing)}"
        done
        ;;
    --why)
        shift
        [[ -n "${1:-}" ]] || { echo "gate.sh: --why needs a gate name" >&2; exit 2; }
        why_gate="$1"
        shift
        run_why "$why_gate" "$@"
        exit "$?"
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
