#!/usr/bin/env bash
# Gate runner. The only way gates are invoked.
#
#   tools/gate.sh --list                 list gates, camera presets and scenarios
#   tools/gate.sh --chain                print the gate graph: what builds on what
#   tools/gate.sh <gate> [extra args]    run one gate
#   tools/gate.sh --all [extra args]     run the suite highest tier first, skipping what a
#                                        passing gate implies; non-zero on failure
#   tools/gate.sh --cmd "<line>"         run any console command: `map list`, `cvar get X`,
#                                        `gate meta smoke`. Same table the console and the
#                                        agent's channel use; `tools/gate.sh --cmd help` lists.
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
# Hard stop so a hung gate fails instead of blocking the suite, counted in frames.
#
# **It is a backstop and it was being hit by healthy runs.** Two photoset gates — a day an hour
# at a time, and a vehicle from four sides at nine of those hours — added some six hundred
# captured frames to the suite, and at 3600 the engine reached the limit part way through and
# quit, cleanly and without a word. The suite then reported "110 gates run; all passed" for a
# suite of 124, because fourteen gates that never ran emit no result line to count. The limit is
# now far above what the suite costs and the tally below is what notices if it is hit anyway.
QUIT_AFTER="${QUIT_AFTER:-60000}"
KEEP_RUNS="${KEEP_RUNS:-10}"
# How much visual history to keep. It was unbounded by design and reached 1104 runs and 194 GB in
# a fortnight, because every run copies every PNG still sitting in artifacts/ — the same stills
# again and again, 176 MB a run. Bounded now at both ends: a run older than the newest
# HISTORY_KEEP_RUNS goes, and an artifact file nothing has touched in ARTIFACT_KEEP_DAYS goes
# before the next archive copies it for the hundredth time.
HISTORY_KEEP_RUNS="${HISTORY_KEEP_RUNS:-25}"
ARTIFACT_KEEP_DAYS="${ARTIFACT_KEEP_DAYS:-3}"

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
# away. Every captured frame is copied into history/ under the run's date and commit.
#
# **It is bounded.** It used to say nothing here was ever deleted, and on this machine that
# came to 1104 runs and 194 GB in a fortnight — not 1104 distinct pictures of the project but
# the same stills copied over and over, because artifacts/ accumulates and every run archives
# all of it. Old runs are of no use to current work and the repository they sit beside is
# 1.2 GB. `prune_history` keeps the newest HISTORY_KEEP_RUNS and `prune_artifacts` drops
# captures nothing has touched in ARTIFACT_KEEP_DAYS, which is what stops the archive growing
# in the first place.
#
# Sweeps are the exception, and have to be. A sweep photographs every object a map places from
# five sides, twice over, and is 501 MB of near-identical stills per run; eight runs of
# tools/mapcheck.sh in one afternoon put 4 GB into a directory that is never pruned. It is also
# the one output here that is fully reproducible from a single command, so what it records is
# the state of the content rather than the look of the project. SWEEPS names those directories.
SWEEPS=(outside)
archive_history() {
    [[ -d "$ARTIFACTS" ]] || return 0
    local sha stamp dest
    sha="$(git -C "$REPO_ROOT" rev-parse --short HEAD 2>/dev/null || echo nogit)"
    stamp="$(date +%Y%m%d-%H%M%S)"
    dest="$REPO_ROOT/history/$stamp-$sha"
    local found=0
    local excludes=(-not -path "*/windows/*")
    local sweep
    for sweep in "${SWEEPS[@]}"; do
        excludes+=(-not -path "*/$sweep/*")
    done
    # Only what this run produced. artifacts/ accumulates, so copying all of it every time
    # archived the same stills over and over — 176 MB a run, 194 GB in a fortnight, almost none
    # of it a picture nobody already had. Anything older than the last archive is in the last
    # archive.
    local previous
    previous="$(find "$REPO_ROOT/history" -maxdepth 1 -mindepth 1 -type d 2>/dev/null |
        sort | tail -1)"
    [[ -n "$previous" ]] && excludes+=(-newer "$previous")
    while IFS= read -r png; do
        local relative target
        relative="${png#"$ARTIFACTS/"}"
        target="$dest/$relative"
        mkdir -p "$(dirname "$target")"
        cp "$png" "$target"
        found=1
    done < <(find "$ARTIFACTS" -name '*.png' "${excludes[@]}" 2>/dev/null)
    [[ $found -eq 1 ]] && echo "history: archived to history/$stamp-$sha" >&2
    prune_history
}

prune_artifacts() {
    [[ -d "$ARTIFACTS" ]] || return 0
    # Artifacts are disposable and bounded: keep the last KEEP_RUNS run directories.
    # BSD head has no negative line count, so drop the newest KEEP_RUNS from a
    # reverse-sorted list instead.
    find "$ARTIFACTS" -maxdepth 1 -type d -name 'run-*' 2>/dev/null | sort -r |
        tail -n "+$((KEEP_RUNS + 1))" | while read -r old; do rm -rf "$old"; done
    # And every capture nothing has touched lately, whatever directory it is in. Without this
    # a sheet taken once stays in artifacts/ for ever and is copied into every archive after
    # it, which is where 194 GB of history came from.
    find "$ARTIFACTS" -type f -mtime "+$ARTIFACT_KEEP_DAYS" -not -path "*/windows/*" -delete \
        2>/dev/null || true
    find "$ARTIFACTS" -type d -empty -not -path "*/windows*" -delete 2>/dev/null || true
}

# The newest HISTORY_KEEP_RUNS runs, and nothing older. Deliberately by count rather than by
# age: a heavy afternoon writes more history than a quiet week, and what matters is having the
# recent ones to compare against rather than covering a particular span of days.
prune_history() {
    local history="$REPO_ROOT/history"
    [[ -d "$history" ]] || return 0
    find "$history" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | sort -r |
        tail -n "+$((HISTORY_KEEP_RUNS + 1))" | while read -r old; do rm -rf "$old"; done
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
    output="$(run_engine --command "gate run $gate" "$@" 2>&1)"
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
    # Through the console's own command table, which is what makes this runner a client of it
    # rather than a second way to run gates -- PLAN 0.8. `--gate` is sugar for the same line.
    output="$(run_engine --command "gate run ${gates//,/ }" "$@" 2>&1)"
    printf '%s\n' "$output" | grep 'HARNESS_GATE_RESULT ' |
        python3 -c '
import json, sys

# Only the gates this batch asked for, and only the first row for each.
#
# Some gates run gates -- `console_fronts_agree` and
# `the_console_reports_a_run_as_it_happens` both drive the real runner -- so a run emits result
# lines for gates nobody in this batch requested, and can emit a second line for one who was.
# Taking them at face value would report an inner run as the outer one.
wanted = [name for name in sys.argv[1].split(",") if name]
seen = set()
for line in sys.stdin:
    row = json.loads(line.split("HARNESS_GATE_RESULT ", 1)[1])
    gate = row.get("gate", "?")
    if gate not in wanted or gate in seen:
        continue
    seen.add(gate)
    verdict = "PASS" if row.get("pass") else "FAIL"
    elapsed = row.get("elapsed_s", "-")
    print("\t".join([
        gate, verdict,
        ("%ss" % elapsed) if elapsed != "-" else "-",
        str(row.get("detail", "")).replace("\t", " "),
        repr(row.get("measured")),
    ]))
' "$gates" > "$BATCH_FILE"
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
    RESULTS_FILE="$(mktemp)"
    local output line command
    command="gate all"
    [[ "$every" -eq 1 ]] && command="gate all every"
    # ONE window for the whole suite. The scheduling that used to be here -- walk the graph, run
    # a tier, consult its results, decide the next -- is `GateSuite` in the engine now, because
    # it is arithmetic on a graph the engine already holds and keeping it out here cost a fresh
    # engine per tier. See PLAN 0.8.
    output="$(run_engine --command "$command" "$@" 2>&1)"
    table_header
    local failed=0 ran=0 implied=0
    while IFS=$'\t' read -r kind gate verdict elapsed detail; do
        case "$kind" in
            RESULT)
                ran=$((ran + 1))
                printf '%-26s %-7s %-8s %s\n' "$gate" "$verdict" "$elapsed" "$detail"
                printf '%s\t%s\n' "$gate" "$verdict" >> "$RESULTS_FILE"
                [[ "$verdict" == "PASS" ]] || failed=1
                ;;
            IMPLIED)
                implied=$((implied + 1))
                printf '%-26s %-7s %-8s %s\n' "$gate" IMPLIED "-" "$detail"
                printf '%s\t%s\n' "$gate" "IMPLIED" >> "$RESULTS_FILE"
                ;;
        esac
    done < <(printf '%s\n' "$output" | python3 -c '
import json, sys

# The run, in the order it happened, and only what the suite itself scheduled.
#
# A gate that runs gates emits result lines of its own -- `console_fronts_agree` deliberately
# runs one named `definitely_not_a_gate` -- so reading every `HARNESS_GATE_RESULT` reported
# those as part of the suite, with a gate name that does not exist. The suite marks its own.
for line in sys.stdin:
    if "HARNESS_SUITE_RESULT " in line:
        row = json.loads(line.split("HARNESS_SUITE_RESULT ", 1)[1])
        gate = row.get("gate", "?")
        print("\t".join([
            "RESULT", gate, "PASS" if row.get("pass") else "FAIL",
            "%ss" % row.get("elapsed_s", "-"),
            str(row.get("detail", "")).replace("\t", " "),
        ]))
    elif "HARNESS_GATE_IMPLIED " in line:
        row = json.loads(line.split("HARNESS_GATE_IMPLIED ", 1)[1])
        print("\t".join([
            "IMPLIED", row["gate"], "IMPLIED", "-",
            "implied by %s, which passed" % row["by"],
        ]))
')
    if [[ $ran -eq 0 ]]; then
        printf '%s\n' "$output" | tail -25 >&2
        echo "gate.sh: the engine ran no gates" >&2
        cleanup_plan
        return 1
    fi
    # A run that stopped early is not a run that passed.
    #
    # The engine says how many gates it planned and how many it accounted for. Without that,
    # what is counted here is the result lines that arrived, and a gate that never ran emits
    # none: a suite killed part way through printed "110 gates run; all passed" for a suite of
    # 125, with fourteen gates simply absent. Reported by the machine running out of memory
    # during a run, which is exactly the kind of thing that must not come back green.
    local planned accounted
    planned="$(printf '%s\n' "$output" | sed -n 's/.*HARNESS_SUITE_PLAN {"gates": *\([0-9]*\)}.*/\1/p' | tail -1)"
    accounted="$(printf '%s\n' "$output" | sed -n 's/.*HARNESS_SUITE_DONE .*"planned": *\([0-9]*\).*/\1/p' | tail -1)"
    if [[ -z "$accounted" ]]; then
        echo "gate.sh: the engine stopped before the suite finished: $ran of ${planned:-?} gates ran" >&2
        cleanup_plan
        return 1
    fi
    if [[ $((ran + implied)) -ne "$accounted" ]]; then
        echo "gate.sh: $ran run and $implied implied, of $accounted the suite planned" >&2
        cleanup_plan
        return 1
    fi
    archive_history
    prune_artifacts
    if [[ $failed -eq 0 ]]; then
        printf '%d gates run in 1 window, %d implied by a higher gate; all passed' "$ran" "$implied"
        if [[ $implied -gt 0 ]]; then
            printf ' (run --all --every to check the implied ones)'
        fi
        printf '\n'
        cleanup_plan
        return 0
    fi
    echo "FAILURES present" >&2
    load_chain
    report_localization
    cleanup_plan
    return 1
}

# Order independence: the acceptance test for the gate containers, and for the development loop.
#
# Every gate twice, in the graph's order and in a seeded shuffle, and **both passes in one
# session**. That is the stronger claim and it is the one a window kept open all day depends on:
# "the same results in a fresh process" is not what has to hold when the process is not fresh.
# The second pass is therefore measured against a renderer the first has already warmed.
#
# Verdicts alone would be too weak -- a number that drifts inside a threshold is the same bug one
# release before it fails -- so measured values are compared too.
run_order_check() {
    local seed="${1:-7}"
    local forward shuffled first second script output
    first="$(mktemp)"
    second="$(mktemp)"
    script="$(mktemp)"
    forward="$(list_gates | tr '\n' ' ')"
    shuffled="$(list_gates | python3 -c "
import random, sys
gates = [line.strip() for line in sys.stdin if line.strip()]
random.Random($seed).shuffle(gates)
print(' '.join(gates))
")"
    printf 'gate run %s\ngate run %s\n' "$forward" "$shuffled" > "$script"
    echo "order check: $(list_gates | wc -l | tr -d ' ') gates, twice, in ONE session (seed $seed)" >&2
    output="$(run_engine --command "exec $script" 2>&1)"
    rm -f "$script"
    # The raw session is kept, because when this check fails it is the only evidence there is.
    # Everything below reduces 180-odd result lines to a verdict, and a failure that says "ran in
    # only one of the two passes" is unactionable without the lines it was reduced from.
    mkdir -p "$ARTIFACTS/order-check"
    printf '%s\n' "$output" > "$ARTIFACTS/order-check/session.txt"
    printf '%s\n' "$output" | python3 -c '
import json, sys

# Two passes over every gate in one process: the first line for a gate is pass one, the second is
# pass two. A gate that runs gates emits lines of its own and they carry a `nested` mark, so they
# are skipped here. Before that mark existed, gate_metadata and static_state emitted four lines
# each across the two passes, so both lines from pass one were paired against each other and pass
# two was thrown away -- two gates were not being order-checked at all.
#
# A name that still turns up more than twice is reported rather than silently truncated. Quietly
# keeping the first two is exactly how the previous fault stayed invisible.
first, second, extra = {}, {}, {}
for line in sys.stdin:
    if "HARNESS_GATE_RESULT " not in line:
        continue
    row = json.loads(line.split("HARNESS_GATE_RESULT ", 1)[1])
    if row.get("nested"):
        continue
    gate = row.get("gate", "?")
    value = ("PASS" if row.get("pass") else "FAIL", repr(row.get("measured")),
             "wall-clock" if row.get("wall_clock") else "")
    if gate not in first:
        first[gate] = value
    elif gate not in second:
        second[gate] = value
    else:
        extra[gate] = extra.get(gate, 2) + 1
for gate, seen in sorted(extra.items()):
    sys.stderr.write("order check: %s produced %d top-level results, expected 2\n" % (gate, seen))
for table, path in ((first, sys.argv[1]), (second, sys.argv[2])):
    with open(path, "w") as handle:
        for gate in sorted(table):
            handle.write("\t".join([gate, table[gate][0], "-", "", table[gate][1], table[gate][2]]) + "\n")
' "$first" "$second"
    if [[ ! -s "$first" || ! -s "$second" ]]; then
        printf '%s\n' "$output" | tail -25 >&2
        echo "order check: the session did not complete both passes" >&2
        rm -f "$first" "$second"
        return 1
    fi
    python3 - "$first" "$second" << 'ORDER_EOF'
import sys


def rows(path):
    out = {}
    with open(path) as handle:
        for line in handle:
            parts = line.rstrip("\n").split("\t")
            if len(parts) >= 5:
                out[parts[0]] = (parts[1], parts[4], parts[5] if len(parts) > 5 else "")
    return out


# How far a measured value may move between the two passes.
#
# Nearly zero, and the history of this number is worth keeping. It was 1e-3, on the grounds that
# a rendered measurement cannot be stable across a warm process -- shader compilation, probe
# capture timing, deferred frees. **That was wrong**, and running both passes in one session is
# what exposed it: `ror_terrain_photoset` drifted 0.282191 -> 0.282288 -> 0.282456 over three
# runs, monotonically, while `surfaces_are_visible` rendered the same terrain three times bit
# for bit. Renderer warmth does not drift monotonically; something was accumulating.
#
# It was the wind. `foliage.gdshader` swayed on `TIME`, so a captured frame depended on the wall
# clock, and with one gate per process every run had started near zero and landed in the same
# part of the sway. The shader takes a phase now and gates fix it, and the drift went to 1e-7.
#
# So the bound is what the measurements actually hold, not what a wrong explanation asked for.
# The worst drift is printed on every run, pass or fail, so anything that starts moving is
# visible before it crosses.
TOLERANCE = 1e-5


def as_float(text):
    try:
        return float(text)
    except (TypeError, ValueError):
        return None


a, b = rows(sys.argv[1]), rows(sys.argv[2])
problems = []
worst, worst_gate = 0.0, ""
# A gate that declares its measured value a wall-clock time is held to its verdict alone. The
# frame-time gate read 10.998 ms in order and 11.049 shuffled, and 10.960 and 10.982 twice in the
# same order: that is a clock, not a dependence on what ran before. It is counted and printed so
# the exemption is never silent.
by_verdict_only = []
for gate in sorted(set(a) | set(b)):
    if gate not in a or gate not in b:
        problems.append("%s ran in only one of the two passes" % gate)
        continue
    if a[gate][0] != b[gate][0]:
        problems.append("%s: %s in order, %s shuffled" % (gate, a[gate][0], b[gate][0]))
        continue
    # A gate that fails in both passes has identical verdicts and is still red. This check used
    # to call that a pass: the haze gate failed twice in one session and the order check reported
    # "identical verdicts" over it.
    if a[gate][0] == "FAIL":
        problems.append("%s: FAIL in both passes (%s / %s)" % (gate, a[gate][1], b[gate][1]))
        continue
    if a[gate][2] == "wall-clock" or b[gate][2] == "wall-clock":
        by_verdict_only.append("%s (%s / %s)" % (gate, a[gate][1], b[gate][1]))
        continue
    first_value, second_value = as_float(a[gate][1]), as_float(b[gate][1])
    if first_value is None or second_value is None:
        if a[gate][1] != b[gate][1]:
            problems.append(
                "%s: measured %s in order, %s shuffled" % (gate, a[gate][1], b[gate][1])
            )
        continue
    scale = max(abs(first_value), abs(second_value), 1e-12)
    drift = abs(first_value - second_value) / scale
    if drift > worst:
        worst, worst_gate = drift, gate
    if drift > TOLERANCE:
        problems.append(
            "%s: measured %r in order, %r shuffled (%.2g relative, over %g)"
            % (gate, first_value, second_value, drift, TOLERANCE)
        )
if problems:
    print("ORDER CHECK FAILED -- a gate depends on what ran before it, or is red in both passes:")
    for problem in problems:
        print("  " + problem)
    raise SystemExit(1)
if by_verdict_only:
    print("order check: %d wall-clock measurement(s) compared by verdict only: %s"
          % (len(by_verdict_only), ", ".join(by_verdict_only)))
print(
    "order check passed: %d gates, two passes in one session, identical verdicts; worst"
    " measured drift %.2g (%s), under %g" % (len(a), worst, worst_gate or "none", TOLERANCE)
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
    --cmd)
        shift
        [[ -n "${1:-}" ]] || { echo "gate.sh: --cmd needs a command line" >&2; exit 2; }
        run_engine --command "$1"
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
