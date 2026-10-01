extends GateBase
## Crashed, then reset: the rig comes back whole. No broken beams, no bends, full strength.
##
## **Reported from the window**, which is the only reason this exists: "after pressing R car is
## resetting but it is broken, doors and wheels fall of". `RigBuilder.place` reset node positions,
## velocities and rest lengths and its own documentation called the result "undeformed" — which
## was true of bends and false of breaks. A broken beam stays broken through all of that, so the
## truck was put back on its wheels still holding every beam it had snapped, and shed its doors
## and wheels again as soon as it was stepped.
##
## Damage is not one field. A hit can change a beam's `rest_length` (the bend), weaken both yield
## stresses, lower the `strength` where upstream softened a beam instead of snapping it, and set
## `broken` — and a break also decrements `active_beams` on both of the beam's nodes, which is the
## count upstream consults before it will break the last beams holding a cab node. Resetting one
## of those six and calling it a repair is how this looked fixed while being broken.
##
## So the gate checks the state a reset is supposed to produce rather than the one field anybody
## happened to think of: nothing broken, every rest length back to what the rig was built with,
## and every beam at full strength. It crashes the rig first and **requires the crash to have
## done real damage**, because a repair gate that runs on an undamaged rig passes without
## repairing anything — this suite has shipped that mistake before.

const MOD_DIR: String = "assets/mods/ChevyS1023"
const TRUCK: String = "S10offroad.truck"
const SUBSTEP_HZ: float = 2000.0
const SETTLE_SECONDS: float = 1.5
const IMPACT_SECONDS: float = 6.0
## The wall, as `a_crash_bends_the_rig` places it: along the rig's own forward axis once settled.
const WALL_AT_M: float = 22.0
const WALL_HALF: Vector3 = Vector3(9.0, 1.6, 1.0)
const CLEARANCE_M: float = 0.15
## The crash has to actually damage the rig, or this gate proves nothing about repairing one.
const MIN_BROKEN: int = 1
## What counts as back where it started. A hair under a millimetre: rest lengths are restored from
## a stored copy, so the honest expectation is exact and this is only float comparison slack.
const SAME_M: float = 0.0005
const SAME_STRENGTH: float = 0.001


static func meta() -> Dictionary:
    return {
        "name": "a_reset_vehicle_is_whole_again",
        "proves": "a crashed rig that is reset comes back with nothing broken, nothing bent and every beam at full strength",
        "builds_on": ["a_crash_bends_the_rig"],
        "oracle": GateBase.ORACLE_INVARIANT,
        "threshold": (
            "after a crash that breaks at least %d beam, a reset leaves 0 broken, every rest"
            % MIN_BROKEN + " length within %.1f mm of as-built and every strength within %.3f"
            % [SAME_M * 1000.0, SAME_STRENGTH]
        ),
        "why": (
            "reported from the window: the truck reset but came back in pieces. Resetting node"
            + " positions and rest lengths undoes a bend and leaves a break, and the function"
            + " doing it already described itself as leaving the rig undeformed — so the bug was"
            + " invisible in the code and obvious on screen. Damage is six fields and a per-node"
            + " count; a repair that restores one of them looks fixed and is not."
        ),
        "budget_s": 120.0,
        "needs_gpu": false,
        "milestone": "M1",
    }


func run(_harness: Node) -> Dictionary:
    var mod_dir: String = SourceScan.repo_root().path_join(MOD_DIR)
    if not DirAccess.dir_exists_absolute(mod_dir):
        return ok("skipped: hero asset not present at %s" % MOD_DIR, 0)

    var rig: Dictionary = RigBuilder.from_file(mod_dir, TRUCK, 0.0)
    if (rig["error"] as String) != "":
        return fail(rig["error"] as String)
    var truck: TruckParser = rig["truck"] as TruckParser
    var solver: RefCounted = rig["solver"] as RefCounted
    solver.set_ground(0.0, true)
    RigBuilder.place(solver, truck, Vector3.ZERO, 0.0, CLEARANCE_M)

    # The shape and the strength the rig is built with. Read after `place` and before anything has
    # driven, which is the condition a reset is supposed to return to.
    var built_lengths: PackedFloat32Array = _rest_lengths(solver)
    var built_strengths: PackedFloat32Array = _strengths(solver)

    var crashed: String = _crash(solver, truck)
    if crashed != "":
        return fail(crashed)
    var broken: int = solver.broken_beam_count()
    var bent: int = _moved(built_lengths, _rest_lengths(solver), SAME_M)
    if broken < MIN_BROKEN:
        return fail(
            "the crash broke %d beams and bent %d, so there is no damage to repair and this gate"
            % [broken, bent] + " would pass without repairing anything. Hit the wall harder.",
            broken
        )

    # The reset the window does, and the whole subject of the gate.
    RigBuilder.place(solver, truck, Vector3.ZERO, 0.0, CLEARANCE_M)

    var still_broken: int = solver.broken_beam_count()
    if still_broken > 0:
        return fail(
            "reset, and %d of %d beams are still broken: the rig is back on its wheels in pieces,"
            % [still_broken, solver.beam_count()]
            + " which is what a person sees as the doors and the wheels falling off again",
            still_broken
        )
    var still_bent: int = _moved(built_lengths, _rest_lengths(solver), SAME_M)
    if still_bent > 0:
        return fail(
            "reset, and %d beams are still bent: their rest lengths did not come back to what the"
            % still_bent + " rig was built with, so the structure kept the set the crash gave it",
            still_bent
        )
    var still_weak: int = _moved(built_strengths, _strengths(solver), SAME_STRENGTH)
    if still_weak > 0:
        return fail(
            "reset, and %d beams are still weakened: upstream softens a beam it declines to break,"
            % still_weak + " so a rig repaired without restoring strength breaks at a lighter"
            + " knock every time it is reset",
            still_weak
        )
    return ok(
        "crashed to %d broken and %d bent of %d beams; after a reset 0 broken, 0 bent and 0"
        % [broken, bent, solver.beam_count()] + " weakened",
        broken
    )


## Drives the rig into a wall placed along its own forward axis. Returns "" on success.
func _crash(solver: RefCounted, truck: TruckParser) -> String:
    var dt: float = 1.0 / SUBSTEP_HZ
    var chunk: int = int(SUBSTEP_HZ / 60.0)
    for _i: int in int(SETTLE_SECONDS * 60.0):
        solver.step(dt, chunk)
    var pose: Transform3D = ActorFrame.of(solver.get_positions(), truck.camera_nodes)
    var forward: Vector3 = -pose.basis.z
    forward = Vector3(forward.x, 0.0, forward.z).normalized()
    var centre: Vector3 = pose.origin + forward * WALL_AT_M + Vector3(0.0, WALL_HALF.y, 0.0)
    solver.add_obstacle_box(
        Transform3D(Basis.looking_at(-forward, Vector3.UP), centre), WALL_HALF, 0
    )
    solver.start_engine()
    solver.set_gear_selector(1)
    solver.set_throttle(1.0)
    for frame: int in int(IMPACT_SECONDS * 60.0):
        solver.step(dt, chunk)
        if not is_finite(solver.get_node_position(0).length()):
            return "the solver went non-finite %.2f s into the run" % (float(frame) / 60.0)
    solver.set_throttle(0.0)
    solver.set_brake(1.0)
    for _i: int in int(2.0 * 60.0):
        solver.step(dt, chunk)
    return ""


func _rest_lengths(solver: RefCounted) -> PackedFloat32Array:
    var out: PackedFloat32Array = PackedFloat32Array()
    for beam: int in solver.beam_count():
        out.append(solver.get_beam_rest_length(beam))
    return out


func _strengths(solver: RefCounted) -> PackedFloat32Array:
    var out: PackedFloat32Array = PackedFloat32Array()
    for beam: int in solver.beam_count():
        out.append(solver.beam_strength(beam))
    return out


## How many entries moved by more than a tolerance.
func _moved(before: PackedFloat32Array, after: PackedFloat32Array, tolerance: float) -> int:
    var count: int = 0
    for index: int in mini(before.size(), after.size()):
        if absf(after[index] - before[index]) > tolerance:
            count += 1
    return count
