class_name PlayFleet
extends Node
## Undriven vehicles beside the driven one, with `--add <mod dir>:<file>[,<mod dir>:<file>...]`:
## a trailer, a load, anything a hook or a tie can take. Each is stood behind the one before it
## along the driven vehicle's own length, takes the same terrain, and is stepped with it by one
## `RorWorld`, which puts them in one island when they touch or are linked.
##
## They have no keys: nothing drives them but what they are hitched or tied to, and the ground.

## How far behind the vehicle in front each one stands, centre to centre.
const BEHIND_M: float = 8.0

var driver: PlayDrive = null
var extras: Array[PlayDrive] = []
var _world: RorWorld = RorWorld.new()


## Builds the vehicles `specs` names into `world`. Returns "" or what went wrong.
func setup(world: Node3D, first: PlayDrive, specs: String) -> String:
    driver = first
    for spec: String in specs.split(",", false):
        var parts: PackedStringArray = spec.split(":")
        if parts.size() != 2:
            return "--add needs <mod dir>:<file>, got '%s'" % spec
        var mod_dir: String = parts[0] if parts[0].is_absolute_path() else SourceScan.repo_root().path_join(parts[0])
        var built: Dictionary = VehicleBuilder.build(mod_dir, parts[1])
        if (built.get("error", "") as String) != "":
            return "%s cannot be built: %s" % [spec, built["error"]]
        world.add_child(built["root"] as Node3D)
        var extra: PlayDrive = PlayDrive.new()
        var error: String = extra.setup(built)
        if error != "":
            return "%s cannot be simulated: %s" % [spec, error]
        extra.keys = {}
        extras.append(extra)
    join_world()
    place()
    return ""


## Every vehicle in one world, stepped by it.
func join_world() -> void:
    _world.clear()
    for member: PlayDrive in [driver] + extras:
        member.world_stepped = true
        member.world = _world
        _world.add_solver(member.solver as RorSolver)


## Stands each extra behind the one before, along the driven vehicle's own forward axis.
func place() -> void:
    for i: int in extras.size():
        _spawn_behind(i)
        extras[i].respawn()


## The driven vehicle's terrain, for the extras too.
func hand_terrain(wanted: RorTerrain, data: Object) -> void:
    for i: int in extras.size():
        _spawn_behind(i)
        extras[i].solver.set_gravity(Vector3(0.0, wanted.gravity(), 0.0))
        var error: String = extras[i].use_terrain(data)
        if error != "":
            printerr("PLAY  an added vehicle could not take the terrain: " + error)
            continue
        RorObjectCollision.apply(wanted, extras[i].solver)


## After the driver's `begin` has worked out the substeps: the extras' frame, then all stepped.
func begin(delta: float) -> void:
    for extra: PlayDrive in extras:
        extra.begin(delta)
    _world.step(1.0 / DriveCfg.SUBSTEP_HZ, driver.substeps_wanted)


func finish() -> void:
    for extra: PlayDrive in extras:
        extra.finish()


func _spawn_behind(index: int) -> void:
    # Forward in an actor's frame is -Z, so behind is +Z, flattened onto the ground.
    var back: Vector3 = Vector3(driver.frame.basis.z.x, 0.0, driver.frame.basis.z.z)
    if back.length() < 0.1:
        back = Basis(Vector3.UP, driver.spawn_heading) * Vector3.BACK
    extras[index].spawn = driver.spawn + back.normalized() * BEHIND_M * float(index + 1)
    extras[index].spawn_heading = driver.spawn_heading
