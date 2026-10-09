# The harness

Audience: contributors.

The harness is the project's only eyes. Development here is CLI-only, so nothing about a
rendering change is visible unless the harness makes it visible: it renders, captures,
measures, compares, and decides. It is the first commit for that reason.

## Running things

    tools/gate.sh --list              gates, camera presets and scenarios
    tools/gate.sh --chain             the gate graph: what each gate builds on
    tools/money_shots.sh              the eight showcase frames as one sheet (PLAN §0.5)
    tools/fetch_corpus.sh [n]         n most-downloaded archive vehicles into assets/corpus/, for mod_corpus
    tools/gate.sh --all               the suite, highest tier first, as a table
    tools/gate.sh --all --every       the suite with the graph ignored: every gate runs
    tools/gate.sh --why vehicle_renders   one gate, then everything under it if it failed
    tools/gate.sh smoke               one gate
    tools/gate.sh smoke --weather golden_dusk
    tools/gate.sh --shot diag_origin  capture one ad-hoc frame
    tools/play.sh                     open a window and drive it yourself

Extra arguments after the gate name are passed to the harness, so any gate can run
under any weather preset without a second scene.

Environment overrides: `GODOT`, `RESOLUTION`, `FIXED_FPS`, `QUIT_AFTER`, `KEEP_RUNS`,
and `MOVIE=1` with `MOVIE_NAME=<name>` to record the run.

## The gate graph

Gates are not a flat list. A gate may declare `builds_on`: the gates whose claims its own claim
contains. An edge means two things, and both have to be true before it is written.

**Passing implies.** Running this gate exercises everything the named gate exercises, at least as
hard. A vehicle photographed from eight sides has rendered a frame, so there is no need to also
prove that a cube renders.

**Failing localises.** If this gate fails, the named gates are where to look next. The runner
walks down them until one fails too, and the lowest failing gate is the level the fault is at:
everything above it failed because of it, everything below it passed, so the fault is in what that
gate alone exercises.

    tools/gate.sh --chain                    what builds on what
    tools/gate.sh --all                      skips what a passing gate implies
    tools/gate.sh --why wheels_roll_on_screen   walks the chain under one gate

`--all` walks the suite highest tier first. A gate covered by one that has already passed is
reported as `IMPLIED` and not run — never as passed, because it was not. When a run fails, the
localisation lines at the end name, for each failure, the lowest failing gate under it.

**The edges are claims about claims, and nothing can check them automatically.** That is why
`--all --every` exists and is what a release run uses: it ignores the graph entirely, and it is the
only thing that catches an edge that was never true. The `gate_chain` gate checks what can be
checked — every edge names a real gate, nothing builds on itself, there are no cycles — and reports
how much of the suite the graph is allowed to imply, so that exposure is a number rather than a
feeling.

Write an edge only when the higher gate's procedure genuinely contains the lower one's: same
subject, same or harder conditions, same or tighter threshold. "It feels related" is not an edge.
When in doubt, leave the gate a leaf; a leaf always runs.

## Why a window opens

macOS has no surfaceless GPU path: `godot --headless` renders nothing at all, and a
capture taken under it is an empty buffer, not a black frame. Image gates therefore open
a real window, and the dev Mac is the sole authority for pixels. Headless is still used
where no rendering is involved — the image differ and the asset tools run that way.

Because every run opens a window, every run is tracked:

    tools/windows.sh list     what this repo has open
    tools/windows.sh kill     close it all
    tools/windows.sh check    non-zero if anything is open

`gate.sh` refuses to start while a window from an earlier run is open, because that
window holds the GPU and would skew the run's timings, and it closes anything left
behind when it exits.

## Determinism

A capture is only comparable if the run that produced it is reproducible.

- `--seed` feeds the project's single `RandomNumberGenerator`. Godot's global `randi()`
  and friends are banned, and the `no_global_random` gate enforces it.
- `--tick` pins the physics rate; a scenario advances by tick index, never by elapsed
  time.
- `--fixed-fps` (passed by `gate.sh`) replaces wall-clock pacing.
- `--converge N` renders and discards N frames before capturing. Temporal effects need
  several frames to settle, and capturing before they do produces an image that differs
  run to run. The value used is recorded in the manifest, and gates covering temporal
  effects capture at two convergence counts so "still converging" is distinguishable
  from "wrong".

## Output

- PNG captures and their manifests go to `artifacts/<name>/`. Everything under
  `artifacts/` is disposable, gitignored, and pruned to the last `KEEP_RUNS` runs.
- Every PNG has a manifest recording engine version, rendering driver, GPU, OS,
  resolution, seed, tick rate and convergence count. The differ refuses to compare
  captures whose driver or GPU differ rather than reporting a difference that looks like
  a regression but is a backend change.
- `HARNESS_METRIC {json}` is printed once per frame, and `HARNESS_SUMMARY {json}` once
  per run. The prefixes are an interface: tooling greps for them, so they do not change.
  Summaries report p50 and p99, never the mean, because the mean hides the hitches that
  are the reason to measure. The first frames pay for world construction and shader
  compilation and are reported separately as warm-up.
- `MOVIE=1` records the run; `tools/contact_sheet.sh <movie.avi>` turns it into a tiled
  sheet plus a consecutive-frame difference sheet. The difference sheet is how ghosting,
  smear and particle boiling become visible in a still image.

## Visual history

Artifacts are pruned, so `tools/gate.sh` copies each run's captured frames into `history/`
under the run's date and short commit before pruning. It is not committed — thousands of
full-resolution frames do not belong in a repository — but it is kept locally, so how the
project looked recently can be reviewed.

**It is bounded at both ends, and it has to be.** This said "nothing there is ever deleted"
and reached 1104 runs and 194 GB in a fortnight beside a 1.2 GB repository — not 1104
distinct pictures of the project, but the same stills copied again and again, because
`artifacts/` accumulates and every run archived all of it. Now a run archives only what it
produced, captures nothing has touched in `ARTIFACT_KEEP_DAYS` (3) are dropped before the next
archive can copy them, the newest `HISTORY_KEEP_RUNS` (25) runs are kept, and sweep output —
`tools/mapcheck.sh` photographs every object a map places, 501 MB a run and reproducible from
one command — is not archived at all. A smoke run archives 520 KB.

    tools/history.sh list                      what has been archived, newest first
    tools/history.sh shots vehicle/hero_3q.png every version of one capture, oldest first
    tools/history.sh sheet vehicle/hero_3q.png those versions as one contact sheet

The contact sheet is the useful one: one image showing a single framing across every run
that produced it, which is how a slow drift becomes visible. Every row also carries `solver_ms`,
`solver_wait_ms`, `deform_ms` and `submit_ms` — zero on a frame that drove nothing — reported into
the frame by `PlayDrive.step` and `VehicleBuilder.apply_pose` through `HarnessMetrics.phase`, and
the summary gives each its p50 and p99. `solver_ms` is the step's own time on the solver's thread;
`solver_wait_ms` is what the frame spent waiting for it, which is the solver's whole cost to the
frame now that it has a thread.

## Writing a gate

A gate is a script in `game/harness/gates/` extending `GateBase`. It declares metadata
and implements `run()`. The metadata is mandatory — the `gate_metadata` gate refuses any
gate that omits it — and it exists so that a failure is actionable and so the suite can
report its own debt.

Required: `name`, `proves`, `oracle`, `threshold`, `why`, `budget_s`, `needs_gpu`,
`milestone`. Optional: `builds_on`, the gates this one covers — see the gate graph above; and
`measured_is_wall_clock`, for a gate whose measured value is a time off the clock, which
`--order-check` then compares by verdict alone and names on every run. A gate red in both passes
fails the order check too: identical verdicts were once enough, and a gate failed twice under a
passing report.

`oracle` is one of `external` (a third-party reference: Khronos sample renders, a
Blender Cycles render, published transfer values, a physical formula), `computed` (a
value the harness derives independently), `invariant` (a property that must hold),
`golden` (a stored image) or `none`. Prefer anything over `golden`: the share of gates
using goldens is capped and reported, because an unbounded golden count turns the suite
into a record of its own past output rather than a test of the product.

Rules that are enforced rather than encouraged:

- One gate, one claim. A gate that fails for six unrelated reasons tells you nothing.
- A failure must print the measured value, the threshold and the artifact path.
- No retry logic, ever. A flaky gate is fixed or deleted within one milestone; retrying
  launders exactly the non-determinism bugs the suite exists to catch.
- A gate never writes its own expected value and never mutates the repository.
- Fixtures are shared. Use a scenario from `Scenarios`; never build an ad-hoc scene.
