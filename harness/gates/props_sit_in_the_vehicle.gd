extends GateBase
## Checks that every prop is built and lands on the vehicle rather than beside it.
##
## Props are the rigid meshes that ride a node triad: the dashboard, the steering wheel,
## the seatbelt buckles. The section was not parsed at all, so a cab with no steering
## wheel rendered without a single complaint from any gate — the parser counted the lines
## and moved on.
##
## Placement is the other half. A prop's own row places it, but a dashboard carries the
## steering wheel as a second mesh in the dashboard's local space, and getting that offset
## wrong put the hero truck's wheel out beside the front tyre. So this checks where they
## land, not only that they exist: a prop belongs within the body it is bolted to.

const MOD_DIR: String = "assets/mods/ChevyS1023"
const TRUCK: String = "S10offroad.truck"
## Props legitimately overhang a little — a mirror stands off the door, a buckle hangs
## past the seat — so the body's box is grown before asking. Not by much: the fault this
## guards put a prop a metre and a half out.
const OVERHANG_M: float = 0.30
const MIN_PROPS: int = 1
## A steering column runs downwards from the wheel to the dash. Upstream's rake constant
## could not simply be copied — the sign and a handedness both differ here — and three
## separate wrong values each produced a wheel that looked reasonable in isolation: face
## into the dash, stalk standing up, stalk lying flat. Down is the part that is not a
## matter of opinion, and it is what separates all three from the right answer.
const MIN_COLUMN_DOWN: float = 0.2


static func meta() -> Dictionary:
    return {
        "name": "props_sit_in_the_vehicle",
        "proves": "every prop is built, placed within the bodywork, and the steering column points down",
        "oracle": GateBase.ORACLE_COMPUTED,
        "threshold": (
            "all %d+ props built, each within %.2f m of the body's bounds, steering"
            % [MIN_PROPS, OVERHANG_M]
            + " column at least %.1f downwards" % MIN_COLUMN_DOWN
        ),
        "why": (
            "a section that is never parsed fails silently and looks like missing"
            + " geometry, and a prop placed in the wrong local space looks like a bug in"
            + " the mesh. Both happened here. The body's own bounds are the oracle:"
            + " whatever is bolted to a truck is on the truck."
        ),
        "budget_s": 30.0,
        "needs_gpu": false,
        "milestone": "M1",
    }


func run(_harness: Node) -> Dictionary:
    var mod_dir: String = SourceScan.repo_root().path_join(MOD_DIR)
    if not DirAccess.dir_exists_absolute(mod_dir):
        return ok("skipped: hero asset not present at %s" % MOD_DIR, 0)
    var built: Dictionary = VehicleBuilder.build(mod_dir, TRUCK)
    if (built.get("error", "") as String) != "":
        return fail(built["error"] as String)
    var root: Node3D = built["root"] as Node3D
    var truck: TruckParser = built["truck"] as TruckParser

    var declared: int = truck.props.size()
    var made: int = int(built["props"])
    if declared < MIN_PROPS:
        root.queue_free()
        return fail("the file declares %d props, expected at least %d" % [declared, MIN_PROPS])
    if made != declared:
        root.queue_free()
        return fail("%d of %d declared props were built" % [made, declared], made)

    # The body, not the whole vehicle: the vehicle's bounds already contain the props, so
    # a prop flung out into the open would simply enlarge the box it is measured against.
    var body: AABB = _body_bounds(built, root)
    if body.size == Vector3.ZERO:
        root.queue_free()
        return fail("the vehicle has no skinned body to measure props against")
    # A steering wheel is held to the cab rather than the body. The body of a pickup
    # spans the load bed as well, so its box is wide enough to contain a wheel sitting out
    # by the front tyre — which is exactly where a wrong local offset put this one, and
    # exactly what a body-sized box fails to notice.
    var cab: AABB = _glazing_bounds(built, root)
    var allowed: AABB = body.grow(OVERHANG_M)
    var cab_allowed: AABB = cab.grow(OVERHANG_M) if cab.size != Vector3.ZERO else allowed
    var strays: PackedStringArray = PackedStringArray()
    for node: Node3D in built["prop_nodes"] as Array[Node3D]:
        for mesh_instance: MeshInstance3D in _meshes_of(node):
            var centre: Vector3 = (
                _rig_transform(mesh_instance, root) * mesh_instance.get_aabb()
            ).get_center()
            var box: AABB = (
                cab_allowed if mesh_instance.name == "SteeringWheel" else allowed
            )
            if not box.has_point(centre):
                strays.append("%s/%s at %.2v" % [node.name, mesh_instance.name, centre])
    var column: String = _column_fault(built, root)
    root.queue_free()
    if column != "":
        return fail(column)
    if strays.size() > 0:
        return fail(
            "%d prop meshes sit outside the bodywork (%s), which spans %.2v to %.2v"
            % [strays.size(), ", ".join(strays), allowed.position, allowed.end],
            strays.size()
        )
    return ok("%d props built and placed within the bodywork" % made, made)


## The steering column's direction, from the wheel mesh itself: a steering wheel is a
## disc, so its thinnest axis is the column it turns on.
func _column_fault(built: Dictionary, root: Node3D) -> String:
    for node: Node3D in built["prop_nodes"] as Array[Node3D]:
        for mesh_instance: MeshInstance3D in _meshes_of(node):
            if mesh_instance.name != "SteeringWheel":
                continue
            var size: Vector3 = mesh_instance.mesh.get_aabb().size
            var thin: int = 0
            for axis: int in 3:
                if size[axis] < size[thin]:
                    thin = axis
            var local: Vector3 = Vector3.ZERO
            local[thin] = 1.0
            var column: Vector3 = (_rig_transform(mesh_instance, root).basis * local).normalized()
            if column.y > -MIN_COLUMN_DOWN:
                return (
                    "the steering column points %+.2v, which is not downwards: a wheel"
                    % column
                    + " raked this way sits face-on to the dashboard or with its stalk in"
                    + " the air. Down needs at least %.1f." % MIN_COLUMN_DOWN
                )
    return ""


## Where a node sits relative to the vehicle root, composed from the chain of local
## transforms. `global_transform` cannot be used: the vehicle is measured without being
## added to a scene tree, and outside a tree it reports identity for everything, which
## silently collapses every measurement onto the origin.
func _rig_transform(node: Node3D, root: Node3D) -> Transform3D:
    var out: Transform3D = Transform3D.IDENTITY
    var at: Node = node
    while at != null and at != root:
        out = (at as Node3D).transform * out
        at = at.get_parent()
    return out


## The cab volume: the glazing encloses it and nothing else does.
func _glazing_bounds(built: Dictionary, root: Node3D) -> AABB:
    for part: SkinnedFlexbody in built["parts"] as Array[SkinnedFlexbody]:
        if not str(part.mesh_instance.name).to_lower().contains("window"):
            continue
        return _rig_transform(part.mesh_instance, root) * part.mesh_instance.get_aabb()
    return AABB()


func _body_bounds(built: Dictionary, root: Node3D) -> AABB:
    var bounds: AABB = AABB()
    var started: bool = false
    for part: SkinnedFlexbody in built["parts"] as Array[SkinnedFlexbody]:
        var box: AABB = _rig_transform(part.mesh_instance, root) * part.mesh_instance.get_aabb()
        bounds = box if not started else bounds.merge(box)
        started = true
    return bounds


func _meshes_of(node: Node) -> Array[MeshInstance3D]:
    var out: Array[MeshInstance3D] = []
    for child: Node in node.get_children():
        var mesh_instance: MeshInstance3D = child as MeshInstance3D
        if mesh_instance != null and mesh_instance.mesh != null:
            out.append(mesh_instance)
    return out
