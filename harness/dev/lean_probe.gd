extends SceneTree
## Why a parked, braked truck slides sideways on asphalt whose friction should hold it.
##
##   godot --path . --headless --script res://harness/dev/lean_probe.gd
##
## Found when per-actor frames turned `a_loaded_terrain_grips_by_its_surfaces` red: leaned on at
## 0.7 g, the hero drifts 5.2 m in 3 s on La Paz's asphalt (static and sliding friction both 1.0),
## and the drift does not order the surfaces by their friction. Each row here changes one thing on
## a flat plane, so the cause is the row that moves.

const MOD_DIR: String = "assets/mods/ChevyS1023"
const TRUCK: String = "S10offroad.truck"
const SUBSTEP_HZ: float = 2000.0
const SETTLE_FRAMES: int = 180
const LEAN_FRAMES: int = 180
## La Paz's own two surfaces, in GroundModelCfg.KEYS order: adhesion velocity, static, sliding,
## hydrodynamic, Stribeck velocity, alpha, strength, then the soft-ground five.
const ASPHALT: Array[float] = [8.0, 1.0, 1.0, 0.001, 0.8, 2.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0]
const DIRT: Array[float] = [3.0, 0.5, 0.8, 0.05, 6.0, 2.0, 1.0, 0.0, 0.0, 800.0, 0.0, 0.0]


func _initialize() -> void:
    var mod_dir: String = SourceScan.repo_root().path_join(MOD_DIR)
    var dirt_hard: Array[float] = DIRT.duplicate()
    dirt_hard[9] = 0.0
    var asphalt_va3: Array[float] = ASPHALT.duplicate()
    asphalt_va3[0] = 3.0
    var asphalt_va05: Array[float] = ASPHALT.duplicate()
    asphalt_va05[0] = 0.5
    for g: float in [0.5, 0.7]:
        print("lean %.1f g" % g)
        print("  block on asphalt:           %s" % _block(ASPHALT, g))
        print("  block on dirt:              %s" % _block(DIRT, g))
        print("  truck on asphalt:           %s" % _truck(mod_dir, ASPHALT, g, SUBSTEP_HZ))
        print("  truck on dirt:              %s" % _truck(mod_dir, DIRT, g, SUBSTEP_HZ))
        print("  truck on dirt, no soft:     %s" % _truck(mod_dir, dirt_hard, g, SUBSTEP_HZ))
        print("  truck on asphalt, va 3:     %s" % _truck(mod_dir, asphalt_va3, g, SUBSTEP_HZ))
        print("  truck on asphalt, va 0.5:   %s" % _truck(mod_dir, asphalt_va05, g, SUBSTEP_HZ))
        print("  truck on asphalt, 6 kHz:    %s" % _truck(mod_dir, ASPHALT, g, 6000.0))
        for factor: float in [3.0, 10.0]:
            print("  truck on asphalt, tread damping x%2.0f: %s"
                % [factor, _truck(mod_dir, ASPHALT, g, SUBSTEP_HZ, factor)])
    quit(0)


func _apply(solver: RefCounted, model: Array[float]) -> void:
    solver.set_ground(0.0, true)
    solver.set_ground_model(0, model[0], model[1], model[2], model[3], model[4], model[5], model[6])
    solver.set_ground_fluid(0, model[7], model[8], model[9], model[10], model[11])


## Four nodes 1 m apart, stiffly beamed, resting on the plane: the contact law with no vehicle.
func _block(model: Array[float], g: float) -> String:
    var solver: RorSolver = RorSolver.new()
    var corners: Array[Vector3] = [
        Vector3(0, 0.0, 0), Vector3(1, 0.0, 0), Vector3(0, 0.0, 1), Vector3(1, 0.0, 1),
    ]
    for corner: Vector3 in corners:
        solver.add_node(corner, 100.0)
    for a: int in 4:
        for b: int in range(a + 1, 4):
            solver.add_beam(a, b, 0.0, 2.0e6, 2000.0)
    _apply(solver, model)
    return _lean(solver, PackedInt32Array([0, 1, 2, 3]), g, SUBSTEP_HZ)


## `tread_damping` multiplies the damping of every beam touching a generated wheel node — the tyre
## and rim beams that ring at 248 Hz — and nothing else.
func _truck(
    mod_dir: String, model: Array[float], g: float, rate: float, tread_damping: float = 1.0
) -> String:
    var rig: Dictionary = RigBuilder.from_file(mod_dir, TRUCK, 0.0)
    var solver: RefCounted = rig["solver"] as RefCounted
    var truck: TruckParser = rig["truck"] as TruckParser
    _apply(solver, model)
    RigBuilder.place(solver, truck, Vector3.ZERO, 0.0, 0.15)
    # After placing: `place` repairs the rig from its snapshot, which puts damping back.
    if tread_damping != 1.0:
        for beam: int in solver.beam_count():
            var ends: Vector2i = solver.get_beam_nodes(beam)
            if ends.x >= truck.generated_from or ends.y >= truck.generated_from:
                solver.set_beam_damping(beam, solver.get_beam_damping(beam) * tread_damping)
    solver.set_brake(1.0)
    solver.set_parking_brake(true)
    return _lean(solver, PackedInt32Array([truck.camera_nodes["centre"] as int]), g, rate)


## Settles, leans the world by `g` sideways, and reports the drift and the fastest the reference
## moved.
func _lean(solver: RefCounted, reference: PackedInt32Array, g: float, rate: float) -> String:
    var dt: float = 1.0 / rate
    var chunk: int = int(rate / 60.0)
    for _i: int in SETTLE_FRAMES:
        solver.step(dt, chunk)
    var from: Vector3 = _centre(solver, reference)
    solver.set_gravity(Vector3(9.81 * g, -9.81, 0.0))
    var fastest: float = 0.0
    var last: Vector3 = from
    var first_metre_s: float = -1.0
    for frame: int in LEAN_FRAMES:
        solver.step(dt, chunk)
        var now: Vector3 = _centre(solver, reference)
        fastest = maxf(fastest, (now - last).length() * 60.0)
        last = now
        if first_metre_s < 0.0 and Vector2(now.x - from.x, now.z - from.z).length() > 0.1:
            first_metre_s = float(frame) / 60.0
    var drift: float = Vector2(last.x - from.x, last.z - from.z).length()
    return "drift %6.3f m, fastest %.2f m/s, first 10 cm at %s" % [
        drift, fastest, "never" if first_metre_s < 0.0 else "%.2f s" % first_metre_s]


func _centre(solver: RefCounted, nodes: PackedInt32Array) -> Vector3:
    var sum: Vector3 = Vector3.ZERO
    for node: int in nodes:
        sum += solver.get_node_position(node)
    return sum / float(nodes.size())
