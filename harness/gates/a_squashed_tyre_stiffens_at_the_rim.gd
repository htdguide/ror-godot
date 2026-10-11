extends GateBase
## A flexbody wheel's support beams, axle to tread, carry the tyre's own rate until the tread is
## squashed to near the rim, and then stiffen towards upstream's structural default, so the tread
## cannot reach the rim.
##
## Upstream's `ProcessFlexBodyWheel` makes each support a SHOCK1 (`AddWheelBeam`, `BEAM_NORMAL`)
## with `shortbound = 1 - rim_radius / tyre_radius * 0.95`, and `CalcBeams` ramps a SHOCK1 past its
## bound towards `shock->sbd_spring` only for a `BEAM_HYDRO` (a `shocks` row); every other one ramps
## towards `DEFAULT_SPRING` (9 MN/m) and `DEFAULT_DAMP`. Ours ramped towards the tyre's own rate,
## which is no stiffening at all.
##
## The oracle is that law on the library's flexbody-wheeled car: every support beam carries the
## defaults as its bump rates, and one support beam held squashed 10% of its length past its bound
## pushes back with upstream's `k + (DEFAULT_SPRING - k) * overshoot` times its compression.

const MOD_DIR: String = "assets/mods/mazda626gf"
const TRUCK: String = "mazda626sd18i-mt.car"
const DEFAULT_SPRING: float = 9000000.0
const DEFAULT_DAMP: float = 12000.0
const OVERSHOOT: float = 0.1
const TOLERANCE: float = 1e-4


static func meta() -> Dictionary:
    return {
        "name": "a_squashed_tyre_stiffens_at_the_rim",
        "proves": "flexbody wheel support beams ramp to upstream's DEFAULT_SPRING/DEFAULT_DAMP past their bound, not to the tyre's rate",
        "builds_on": ["a_wheel_rig_matches_upstreams_budget", "bounded_beams_oracle"],
        "oracle": GateBase.ORACLE_COMPUTED,
        "threshold": "every support beam's bump rates %.0f / %.0f; squashed %.0f%% past its bound it pushes upstream's force within %s" % [DEFAULT_SPRING, DEFAULT_DAMP, OVERSHOOT * 100.0, String.num_scientific(TOLERANCE)],
        "why": "a squashed flexbody tyre met no stiffening and its tread could fold onto the rim.",
        "budget_s": 20.0,
        "needs_gpu": false,
        "milestone": "M1",
    }


func run(_harness: Node) -> Dictionary:
    var mod_dir: String = SourceScan.repo_root().path_join(MOD_DIR)
    if not DirAccess.dir_exists_absolute(mod_dir):
        return ok("skipped: %s not present" % MOD_DIR, 0)
    var rig: Dictionary = RigBuilder.from_file(mod_dir, TRUCK, 0.0)
    if (rig["error"] as String) != "":
        return fail(rig["error"] as String)
    var truck: TruckParser = rig["truck"] as TruckParser
    var supports: Array[Dictionary] = []
    for entry: Dictionary in truck.bounded_beams:
        if (entry["bound"] as int) == BeamRows.BOUND_SHOCK and (entry["long_bound"] as float) == 0.0 \
                and (entry["short_bound"] as float) > 0.0:
            supports.append(entry)
    if supports.is_empty():
        return fail("the car has no flexbody support beams to check")
    for entry: Dictionary in supports:
        if entry["bound_spring"] != DEFAULT_SPRING or entry["bound_damp"] != DEFAULT_DAMP:
            return fail("support beam %d ramps to %.0f / %.0f, not upstream's %.0f / %.0f" % [
                entry["beam"], entry["bound_spring"], entry["bound_damp"], DEFAULT_SPRING, DEFAULT_DAMP])

    var solver: RefCounted = rig["solver"] as RefCounted
    solver.set_gravity(Vector3.ZERO)
    var beam: int = supports[0]["beam"] as int
    var short_bound: float = supports[0]["short_bound"] as float
    var nodes: Vector2i = solver.get_beam_nodes(beam)
    for node: int in solver.node_count():
        solver.set_node_immovable(node, true)
    var rest: float = solver.get_beam_rest_length(beam)
    var a: Vector3 = solver.get_node_position(nodes.x)
    var b: Vector3 = solver.get_node_position(nodes.y)
    solver.set_node_position(nodes.y, a + (b - a).normalized() * rest * (1.0 - short_bound - OVERSHOOT))
    var extension: float = solver.get_beam_length(beam) - rest
    solver.step(1.0 / 2000.0, 1)
    var spring: float = truck.beam_spring[beam]
    var overshoot: float = -extension - short_bound * rest
    var k: float = spring + (DEFAULT_SPRING - spring) * overshoot
    var want: float = -k * extension
    var got: float = solver.get_beam_stress(beam)
    if absf(got - want) > TOLERANCE * absf(want):
        return fail("squashed %.4f m past its bound, support beam %d pushes %.1f N; upstream's law says %.1f" % [
            overshoot, beam, got, want], got)
    return ok("%d support beams ramp to %.0f / %.0f; one squashed %.4f m past its bound pushes %.0f N (tyre rate alone: %.0f N)" % [
        supports.size(), DEFAULT_SPRING, DEFAULT_DAMP, overshoot, got, -spring * extension], got)
