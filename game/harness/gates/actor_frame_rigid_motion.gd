extends GateBase
## Rigid motion of a whole vehicle must live in its instance transform, not in its
## vertices.
##
## This is the property milestone (b) rests on. A truck driving across the screen moves
## and turns; if that motion is baked into vertex positions, the instance transform never
## changes, motion vectors report nothing moving, and TAA smears the one object the player
## is looking at. Worse, the rest of the image looks correct, so the failure gets
## misattributed to TAA and tuned at rather than fixed.
##
## What is checked: move and rotate every node rigidly, then require that the actor frame
## picks up exactly that motion while the actor-local bone transforms do not change at
## all. A deforming pose must still change them, or the check would pass on a bridge that
## simply ignores the nodes.

const MOD_DIR: String = "assets/mods/ChevyS1023"
const TRUCK: String = "S10offroad.truck"
const MESH: String = "S10bodyshort.mesh"
## Rigid motion applied to the whole vehicle: a turn and a drive, larger than one frame's
## worth so any leakage into the local frame is unmissable.
const YAW_DEGREES: float = 37.0
const TRANSLATION: Vector3 = Vector3(5.0, 0.5, -3.0)
## Bone transforms are metres and unit axes, so this is a strict bound in both.
const MAX_LOCAL_DRIFT: float = 0.00001
## A deformation the local frame must notice, so the invariant cannot pass vacuously.
const DEFORM_METRES: float = 0.05
const MIN_DEFORM_RESPONSE: float = 0.001


static func meta() -> Dictionary:
    return {
        "name": "actor_frame_rigid_motion",
        "proves": "rigid vehicle motion appears in the instance transform and leaves actor-local bone transforms untouched",
        "oracle": GateBase.ORACLE_INVARIANT,
        "threshold": (
            "actor frame matches the applied motion; local bones drift < %s; deformation still moves them > %s"
            % [MAX_LOCAL_DRIFT, MIN_DEFORM_RESPONSE]
        ),
        "why": (
            "motion vectors for a skinned mesh come from the instance transform and the"
            + " previous bone poses. If bulk motion is baked into vertices instead, the"
            + " renderer sees a stationary object and smears it, and because the rest of"
            + " the frame looks right the fault gets blamed on TAA."
        ),
        "budget_s": 60.0,
        "needs_gpu": false,
        "milestone": "M1",
    }


func run(_harness: Node) -> Dictionary:
    var mod_dir: String = SourceScan.repo_root().path_join(MOD_DIR)
    if not DirAccess.dir_exists_absolute(mod_dir):
        return ok("skipped: hero asset not present at %s" % MOD_DIR, 0)

    var truck: TruckParser = TruckParser.new()
    var parse_error: String = truck.parse_file(mod_dir.path_join(TRUCK))
    if parse_error != "":
        return fail(parse_error)
    if truck.camera_nodes.is_empty():
        return fail("%s declares no cameras section, so the actor has no frame" % TRUCK)

    var entry: Dictionary = _entry_for(truck, MESH)
    if entry.is_empty():
        return fail("%s declares no flexbody for %s" % [TRUCK, MESH])
    var vertices: PackedVector3Array = _placed_vertices(mod_dir, entry, truck)
    if vertices.is_empty():
        return fail("could not place %s" % MESH)

    var binding: Dictionary = FlexbodyBinder.bind(
        truck.nodes, entry["forset"] as PackedInt32Array, vertices
    )
    var triads: Array[Vector3i] = binding["triads"] as Array[Vector3i]
    var bind_inverse: Array[Transform3D] = []
    for frame: Transform3D in FlexbodyBinder.bone_transforms(truck.nodes, triads):
        bind_inverse.append(frame.affine_inverse())

    var rest_actor: Transform3D = ActorFrame.of(truck.nodes, truck.camera_nodes)
    var rest_local: Array[Transform3D] = _local_bones(truck.nodes, triads, bind_inverse, rest_actor)

    # Move and turn the whole vehicle rigidly.
    var motion: Transform3D = Transform3D(
        Basis(Vector3.UP, deg_to_rad(YAW_DEGREES)), TRANSLATION
    )
    var moved_nodes: PackedVector3Array = _apply(motion, truck.nodes)
    var moved_actor: Transform3D = ActorFrame.of(moved_nodes, truck.camera_nodes)
    var moved_local: Array[Transform3D] = _local_bones(moved_nodes, triads, bind_inverse, moved_actor)

    var frame_error: float = _transform_distance(moved_actor, motion * rest_actor)
    if frame_error > MAX_LOCAL_DRIFT:
        return fail(
            "actor frame did not follow the rigid motion: off by %s" % frame_error, frame_error
        )
    var drift: float = _max_distance(rest_local, moved_local)
    if drift > MAX_LOCAL_DRIFT:
        return fail(
            "rigid motion leaked into actor-local bones by %s, over %s: the instance"
            % [drift, MAX_LOCAL_DRIFT]
            + " transform is not carrying the vehicle's motion and TAA will smear it",
            drift
        )

    # The invariant must not hold for the wrong reason.
    var deformed: PackedVector3Array = _deform(truck.nodes)
    var deformed_actor: Transform3D = ActorFrame.of(deformed, truck.camera_nodes)
    var deformed_local: Array[Transform3D] = _local_bones(
        deformed, triads, bind_inverse, deformed_actor
    )
    var response: float = _max_distance(rest_local, deformed_local)
    if response < MIN_DEFORM_RESPONSE:
        return fail(
            "a %.0f cm deformation moved the local bones by only %s: the check would pass"
            % [DEFORM_METRES * 100.0, response]
            + " on a bridge that ignores node positions entirely",
            response
        )
    return ok(
        "%d bones: rigid motion leaks %s into local space, deformation moves them %s"
        % [triads.size(), drift, response],
        drift
    )


func _entry_for(truck: TruckParser, mesh_name: String) -> Dictionary:
    for entry: Dictionary in truck.flexbodies:
        if (entry["mesh"] as String) == mesh_name:
            return entry
    return {}


func _placed_vertices(mod_dir: String, entry: Dictionary, truck: TruckParser) -> PackedVector3Array:
    var reader: RefCounted = ClassDB.instantiate("OgreMeshReader") as RefCounted
    if reader == null:
        return PackedVector3Array()
    var result: Dictionary = reader.read_file(mod_dir.path_join(entry["mesh"] as String))
    if (result.get("error", "") as String) != "":
        return PackedVector3Array()
    var transform: Transform3D = FlexbodyBinder.placement(truck.nodes, entry)
    var out: PackedVector3Array = PackedVector3Array()
    for submesh: Dictionary in result["submeshes"] as Array:
        for vertex: Vector3 in submesh["positions"] as PackedVector3Array:
            out.append(transform * vertex)
    return out


func _local_bones(
    nodes: PackedVector3Array,
    triads: Array[Vector3i],
    bind_inverse: Array[Transform3D],
    actor: Transform3D
) -> Array[Transform3D]:
    var to_local: Transform3D = actor.affine_inverse()
    var out: Array[Transform3D] = []
    var frames: Array[Transform3D] = FlexbodyBinder.bone_transforms(nodes, triads)
    for bone: int in frames.size():
        out.append(to_local * frames[bone] * bind_inverse[bone])
    return out


func _apply(motion: Transform3D, nodes: PackedVector3Array) -> PackedVector3Array:
    var out: PackedVector3Array = PackedVector3Array()
    out.resize(nodes.size())
    for i: int in nodes.size():
        out[i] = motion * nodes[i]
    return out


## Suspension travel on one side: a real deformation, not a rigid motion.
func _deform(nodes: PackedVector3Array) -> PackedVector3Array:
    var out: PackedVector3Array = PackedVector3Array()
    out.resize(nodes.size())
    for i: int in nodes.size():
        var node: Vector3 = nodes[i]
        out[i] = node + Vector3(0.0, DEFORM_METRES if node.x > 0.0 else -DEFORM_METRES, 0.0)
    return out


func _transform_distance(a: Transform3D, b: Transform3D) -> float:
    # Basis.x/y/z are the columns; GDScript has no get_column.
    var worst: float = (a.origin - b.origin).length()
    worst = maxf(worst, (a.basis.x - b.basis.x).length())
    worst = maxf(worst, (a.basis.y - b.basis.y).length())
    worst = maxf(worst, (a.basis.z - b.basis.z).length())
    return worst


func _max_distance(a: Array[Transform3D], b: Array[Transform3D]) -> float:
    var worst: float = 0.0
    for i: int in mini(a.size(), b.size()):
        worst = maxf(worst, _transform_distance(a[i], b[i]))
    return worst
