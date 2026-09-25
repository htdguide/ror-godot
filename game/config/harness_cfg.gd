class_name HarnessCfg
extends RefCounted
## Harness defaults. Data only: no logic lives in a config file.

## Physics ticks per second. Fixed so a scenario advances by tick count, never by
## wall-clock time. 60 matches the render rate, which keeps scenario frame indices
## and physics tick indices in step and makes off-by-one capture bugs visible.
const TICK_HZ: int = 60

## Frames rendered and discarded before a capture. Temporal effects (TAA and FSR
## history, SDFGI cascade population, volumetric fog reprojection) need several
## frames to settle, and capturing before they do produces an image that differs
## run to run. 8 is enough for the M0 pipeline; milestones that add temporal
## effects raise it and record the value they used in every manifest.
const CONVERGE_FRAMES: int = 8

## Default seed for the single explicit RandomNumberGenerator. Global randi() is
## banned by the no_global_random gate precisely so this is the only source.
const SEED: int = 1

## Capture resolution. The frame budget in the plan is stated at this resolution,
## so gates that report timings must use it.
const WIDTH: int = 1920
const HEIGHT: int = 1080

## Where run output goes. Everything under this directory is disposable, gitignored,
## and pruned by the runner; only goldens and oracle references are committed.
const ARTIFACT_ROOT: String = "artifacts"
const GOLDEN_ROOT: String = "goldens"

## Hard stop for any single gate, in rendered frames. A gate that has not finished
## by here has hung, and a hung gate must fail rather than block the suite.
const MAX_FRAMES: int = 6000
