extends GateBase
## On La Paz, the asphalt holds what the dirt beside it lets go, by the terrain's own numbers.
##
## The terrain paints where its surfaces are and ships the friction numbers for them, and this
## project reads both: the traction map decides which ground model each cell uses, and the mod's
## own config sets what those models are — its dirt holds 0.5 where its asphalt holds 1.0. All of
## that can be right in the data and reach nothing, which is exactly what a transposed surface map
## looked like the last time: the right surfaces, in the wrong places.
##
## **The test is Coulomb's, at the terrain's own places.** A block of four stiffly joined nodes is
## set down on the road and on the dirt beside it, with La Paz's real heightfield and surface map
## under it, and the world is leaned sideways until the ratio of the force along the ground to the
## force into it lies halfway between the two surfaces' own static coefficients — read from the
## loaded models, not written here. A mass holds while that ratio is below its surface's
## coefficient and slides once it is above, so the asphalt block has to stay put and the dirt one
## has to go. The ground's own tilt at each spot is folded into the lean, so the ratio is the one
## the block actually feels.
##
## **Why not the truck any more.** This gate used to lean the hero, parked and braked, at 0.7 g
## and ask the dirt to let it go 25% further than the asphalt. It passed at 1.47x while the rig
## sat 3.7 km from the origin in float32 — positions that coarse cannot creep. With per-actor
## frames the same lean reads 1.14x, identical to the same rig moved to the true origin, and
## `harness/dev/lean_probe.gd` found why: the parked truck creeps downhill on asphalt at half its
## friction limit (3.1 m in 3 s at 0.5 g), driven by the tyres' 248 Hz ring against upstream's
## static-friction branch, which cancels a node's tangential force but brakes a moving node by
## only `1 - exp(-v / adhesion velocity)` — and La Paz's asphalt states 8 m/s. So the truck's drift
## measured that creep, not which surface grips harder. The creep is an open finding of its own
## (HANDOFF, "the tyres ring"); this gate asks only what it says.

const TERRAIN_DIR: String = "assets/terrains/lapaz2"
const SUBSTEP_HZ: float = 2000.0
## Where to test: a point on the road, and one out in the desert beside it.
const ON_THE_ROAD: Vector2 = Vector2(3700.0, 45.0)
const OFF_THE_ROAD: Vector2 = Vector2(3700.0, 95.0)
const BLOCK_SIDE_M: float = 1.0
const NODE_KG: float = 100.0
const BEAM_SPRING: float = 2.0e6
const BEAM_DAMP: float = 2000.0
const SETTLE_SECONDS: float = 0.5
const LEAN_SECONDS: float = 1.5
## A held block may creep by the smoothing in the static branch, but not by this; a sliding one
## has to actually go somewhere. The same two figures `surfaces_change_grip` holds a lone node to.
const HOLD_TOLERANCE_M: float = 0.002
const MIN_SLIDE_M: float = 0.05


static func meta() -> Dictionary:
    return {
        "name": "a_loaded_terrain_grips_by_its_surfaces",
        "proves": "on La Paz's own heightfield and surface map, a block leaned halfway between its asphalt's and its dirt's own static coefficients holds on the road and slides on the dirt beside it",
        "builds_on": ["ror_terrain_is_drivable", "ground_models_match_upstream", "surfaces_change_grip"],
        "oracle": GateBase.ORACLE_COMPUTED,
        "threshold": (
            "at a tangential-to-normal ratio of (mu_road + mu_dirt) / 2 from the loaded models,"
            + " the road block moves under %.0f mm and the dirt block at least %.0f mm"
            % [HOLD_TOLERANCE_M * 1000.0, MIN_SLIDE_M * 1000.0]
        ),
        "why": (
            "which surface is where and what each one grips like are both the terrain's own"
            + " data, and both can be correct and reach nothing — a transposed surface map"
            + " reads as the right surfaces in the wrong places, which this project has had."
            + " A leaned truck cannot answer it: parked and braked it creeps on asphalt at half"
            + " its friction limit, so its drift measures the creep."
        ),
        "budget_s": 120.0,
        "needs_gpu": false,
        "milestone": "M1",
    }


func run(_harness: Node) -> Dictionary:
    var directory: String = SourceScan.repo_root().path_join(TERRAIN_DIR)
    if not DirAccess.dir_exists_absolute(directory):
        return ok("skipped: no terrain at %s" % TERRAIN_DIR, 0)
    var loaded: Dictionary = RorTerrain.load_from(directory)
    if (loaded["error"] as String) != "":
        return fail(loaded["error"] as String)
    var terrain: RorTerrain = loaded["terrain"] as RorTerrain

    var road_name: String = terrain.models.name_of(terrain.surface_at_world(ON_THE_ROAD.x, ON_THE_ROAD.y))
    var dirt_name: String = terrain.models.name_of(terrain.surface_at_world(OFF_THE_ROAD.x, OFF_THE_ROAD.y))
    if road_name == dirt_name:
        return fail(
            "both places are '%s': the two chosen are the same surface, so nothing here is"
            % road_name + " being compared"
        )
    var road_mu: float = float(terrain.models.values_of(road_name)[1])
    var dirt_mu: float = float(terrain.models.values_of(dirt_name)[1])
    if road_mu <= dirt_mu:
        return fail(
            "the terrain states %s at %.2f and %s at %.2f: the road is not the grippier surface,"
            % [road_name, road_mu, dirt_name, dirt_mu] + " so this test has no direction"
        )
    var ratio: float = (road_mu + dirt_mu) * 0.5

    var road: Dictionary = _lean_block(terrain, ON_THE_ROAD, ratio)
    var dirt: Dictionary = _lean_block(terrain, OFF_THE_ROAD, ratio)
    for run: Dictionary in [road, dirt]:
        if (run["error"] as String) != "":
            return fail(run["error"] as String)
        if (run["surface"] as String) != (road_name if run == road else dirt_name):
            return fail(
                "the solver reads '%s' under the block where the terrain's map says '%s': the map"
                % [run["surface"], road_name if run == road else dirt_name]
                + " does not reach the contact law",
                0
            )
    if (road["drift"] as float) > HOLD_TOLERANCE_M:
        return fail(
            "on %s (mu %.2f) leaned to %.3f the block moved %.4f m: it should hold"
            % [road_name, road_mu, ratio, road["drift"]],
            road["drift"]
        )
    if (dirt["drift"] as float) < MIN_SLIDE_M:
        return fail(
            "on %s (mu %.2f) leaned to %.3f the block moved %.4f m: it should slide"
            % [dirt_name, dirt_mu, ratio, dirt["drift"]],
            dirt["drift"]
        )
    return ok(
        "leaned to %.3f (halfway between %s %.2f and %s %.2f): the road block moved %.5f m, the"
        % [ratio, road_name, road_mu, dirt_name, dirt_mu, road["drift"]]
        + " dirt block slid %.3f m" % dirt["drift"],
        dirt["drift"]
    )


## A block set down at `at` on the terrain's own ground, leaned so the force along the ground over
## the force into it is `ratio`, and how far it went.
func _lean_block(terrain: RorTerrain, at: Vector2, ratio: float) -> Dictionary:
    var out: Dictionary = {"error": "", "drift": 0.0, "surface": ""}
    var solver: RorSolver = RorSolver.new()
    _give_terrain(solver, terrain)
    solver.set_ground(0.0, true)
    var nodes: PackedInt32Array = PackedInt32Array()
    for corner: Vector2 in [Vector2(0, 0), Vector2(1, 0), Vector2(0, 1), Vector2(1, 1)]:
        var xz: Vector2 = at + (corner - Vector2(0.5, 0.5)) * BLOCK_SIDE_M
        var ground: float = solver.ground_height_at(Vector3(xz.x, 0.0, xz.y))
        nodes.append(solver.add_node(Vector3(xz.x, ground + 0.001, xz.y), NODE_KG))
    for a: int in nodes.size():
        for b: int in range(a + 1, nodes.size()):
            solver.add_beam(nodes[a], nodes[b], 0.0, BEAM_SPRING, BEAM_DAMP)
    var centre: Vector3 = Vector3(at.x, 0.0, at.y)
    out["surface"] = terrain.models.name_of(solver.surface_at(centre))

    var dt: float = 1.0 / SUBSTEP_HZ
    var chunk: int = int(SUBSTEP_HZ / 60.0)
    for _settle: int in int(SETTLE_SECONDS * 60.0):
        solver.step(dt, chunk)
    var from: Vector3 = _centre(solver, nodes)
    solver.set_gravity(_leaning_gravity(solver.ground_normal_at(centre), ratio))
    for _lean: int in int(LEAN_SECONDS * 60.0):
        solver.step(dt, chunk)
    var here: Vector3 = _centre(solver, nodes)
    if not is_finite(here.length()):
        out["error"] = "the solver went non-finite while the block at %s was leaned on" % at
        return out
    out["drift"] = here.distance_to(from)
    return out


## Gravity of 9.81 m/s2 turned so that against a ground of normal `normal` its along-ground part
## over its into-ground part is `ratio`: the ground's own tilt is part of the lean, not added to it.
func _leaning_gravity(normal: Vector3, ratio: float) -> Vector3:
    var n: Vector3 = normal.normalized()
    var along: Vector3 = Vector3.RIGHT - n * Vector3.RIGHT.dot(n)
    if along.length() < 1.0e-6:
        along = Vector3.FORWARD - n * Vector3.FORWARD.dot(n)
    along = along.normalized()
    return (-n + along * ratio).normalized() * 9.81


func _centre(solver: RorSolver, nodes: PackedInt32Array) -> Vector3:
    var sum: Vector3 = Vector3.ZERO
    for node: int in nodes:
        sum += solver.get_node_position(node)
    return sum / float(nodes.size())


## The terrain's own heights and surfaces, straight from the shape.
func _give_terrain(solver: RorSolver, terrain: RorTerrain) -> void:
    var grid: Dictionary = terrain.lattice()
    var size: int = grid["size"] as int
    var heights: PackedFloat32Array = PackedFloat32Array()
    heights.resize(size * size)
    var surfaces: PackedByteArray = PackedByteArray()
    surfaces.resize(size * size)
    for z: int in size:
        var row: int = z * size
        for x: int in size:
            heights[row + x] = terrain.height_at(x, z)
            surfaces[row + x] = terrain.surface_at(x, z)
    solver.set_heightfield(
        heights, size, size, grid["origin"] as Vector3, grid["spacing"] as float
    )
    solver.set_surface_map(surfaces, size, size)
    terrain.models.apply(solver)
