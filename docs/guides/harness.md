# The harness

Audience: contributors.

The harness is the project's only eyes. Development here is CLI-only, so nothing about a
rendering change is visible unless the harness makes it visible: it renders, captures,
measures, compares, and decides. It is the first commit for that reason.

## Running things

    tools/gate.sh --list              gates, camera presets and scenarios
    tools/gate.sh --all               every gate, as a table, non-zero exit on failure
    tools/gate.sh smoke               one gate
    tools/gate.sh smoke --weather golden_dusk
    tools/gate.sh --shot diag_origin  capture one ad-hoc frame
    tools/play.sh                     open a window and drive it yourself

Extra arguments after the gate name are passed to the harness, so any gate can run
under any weather preset without a second scene.

Environment overrides: `GODOT`, `RESOLUTION`, `FIXED_FPS`, `QUIT_AFTER`, `KEEP_RUNS`,
and `MOVIE=1` with `MOVIE_NAME=<name>` to record the run.

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

## Writing a gate

A gate is a script in `game/harness/gates/` extending `GateBase`. It declares metadata
and implements `run()`. The metadata is mandatory — the `gate_metadata` gate refuses any
gate that omits it — and it exists so that a failure is actionable and so the suite can
report its own debt.

Required: `name`, `proves`, `oracle`, `threshold`, `why`, `budget_s`, `needs_gpu`,
`milestone`.

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
