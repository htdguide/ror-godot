extends GateBase
## Measures how many bones a real vehicle needs under the skinning bridge.
##
## ADR 0002 proved FlexBody deformation is single-bone skinning with one bone per locator
## triad, and left the count on a real vehicle open. This answers it on the hero asset,
## and the answer decides whether the skinning path is affordable: bones are uploaded
## every frame, so a count near the vertex count would mean skinning buys nothing over
## streaming vertices.

const MOD_DIR: String = "assets/mods/ChevyS1023"
const TRUCK: String = "S10offroad.truck"
## Bytes uploaded per frame, which is what the two paths actually trade against each
## other. A bone is a 3x4 float matrix; a streamed vertex is a position and a normal.
const BONE_BYTES: int = 48
const VERTEX_BYTES: int = 24
## Skinning must pay for itself across the vehicle, not on every mesh: a mesh with a poor
## ratio is routed to the streaming path instead (ADR 0003 already has two paths).
const MIN_AGGREGATE_SAVING: float = 2.0
## Godot stores bone transforms in a texture, so thousands are fine, but a vehicle
## needing more than this would mean the triad assignment is behaving unlike upstream's.
const MAX_BONES_PER_MESH: int = 4096


static func meta() -> Dictionary:
    return {
        "name": "flexbody_bone_count",
        "proves": "a real vehicle's flexbodies bind to far fewer locator triads than they have vertices",
        "oracle": GateBase.ORACLE_COMPUTED,
        "threshold": (
            "skinning uploads at least %.0fx fewer bytes per frame than streaming;"
            % MIN_AGGREGATE_SAVING
            + " at most %d bones per mesh" % MAX_BONES_PER_MESH
        ),
        "why": (
            "bone transforms are uploaded every frame, so bytes per frame is the real"
            + " comparison, not a per-mesh ratio. Measuring it per vehicle rather than"
            + " per mesh matches how the decision is actually made: a mesh with a poor"
            + " ratio is routed to the streaming path, so one bad mesh is a routing"
            + " choice and not a refutation of ADR 0002."
        ),
        "budget_s": 120.0,
        "needs_gpu": false,
        "milestone": "M1",
    }


func run(_harness: Node) -> Dictionary:
    var dir_path: String = SourceScan.repo_root().path_join(MOD_DIR)
    if not DirAccess.dir_exists_absolute(dir_path):
        return ok("skipped: hero asset not present at %s" % MOD_DIR, 0)

    var truck: TruckParser = TruckParser.new()
    var error: String = truck.parse_file(dir_path.path_join(TRUCK))
    if error != "":
        return fail(error)
    if truck.flexbodies.is_empty():
        return fail("%s declares no flexbodies" % TRUCK)

    var reader: RefCounted = ClassDB.instantiate("OgreMeshReader") as RefCounted
    if reader == null:
        return fail("OgreMeshReader is not registered: the GDExtension did not load")

    var total_vertices: int = 0
    var total_bones: int = 0
    var stream_candidates: PackedStringArray = PackedStringArray()
    var reported: PackedStringArray = PackedStringArray()

    for entry: Dictionary in truck.flexbodies:
        var mesh_name: String = entry["mesh"] as String
        var mesh_path: String = dir_path.path_join(mesh_name)
        if not FileAccess.file_exists(mesh_path):
            continue
        var forset: PackedInt32Array = entry["forset"] as PackedInt32Array
        if forset.is_empty():
            return fail("flexbody '%s' has an empty forset" % mesh_name)

        var placed: PackedVector3Array = _placed_vertices(reader, mesh_path, truck.nodes, entry)
        if placed.is_empty():
            continue
        var stats: Dictionary = FlexbodyBinder.bind_stats(truck.nodes, forset, placed)
        var bones: int = int(stats["triads"])
        var ratio: float = float(stats["shared"])
        total_vertices += int(stats["vertices"])
        total_bones += bones
        reported.append(
            "%s %dv/%db %.1fx" % [mesh_name, int(stats["vertices"]), bones, ratio]
        )
        if bones > MAX_BONES_PER_MESH:
            return fail("%s needs %d bones, over %d" % [mesh_name, bones, MAX_BONES_PER_MESH], bones)
        # Per-mesh routing: skinning only helps where it moves fewer bytes.
        if bones * BONE_BYTES >= int(stats["vertices"]) * VERTEX_BYTES:
            stream_candidates.append("%s(%.1fx)" % [mesh_name, ratio])

    if total_bones == 0:
        return fail("no flexbody meshes could be placed and bound")
    var skinned_bytes: int = total_bones * BONE_BYTES
    var streamed_bytes: int = total_vertices * VERTEX_BYTES
    var saving: float = float(streamed_bytes) / float(maxi(skinned_bytes, 1))
    if saving < MIN_AGGREGATE_SAVING:
        return fail(
            "skinning uploads %d bytes per frame against %d streamed (%.1fx), under %.0fx: %s"
            % [skinned_bytes, streamed_bytes, saving, MIN_AGGREGATE_SAVING, ", ".join(reported)],
            saving
        )
    var routing: String = (
        "" if stream_candidates.is_empty()
        else "; route to streaming: %s" % ", ".join(stream_candidates)
    )
    return ok(
        "%d vertices bind to %d bones: %d B/frame skinned vs %d B/frame streamed (%.1fx saving)%s"
        % [total_vertices, total_bones, skinned_bytes, streamed_bytes, saving, routing],
        saving
    )


func _placed_vertices(
    reader: RefCounted, mesh_path: String, nodes: PackedVector3Array, entry: Dictionary
) -> PackedVector3Array:
    var result: Dictionary = reader.read_file(mesh_path)
    if (result.get("error", "") as String) != "":
        return PackedVector3Array()
    var transform: Transform3D = FlexbodyBinder.placement(nodes, entry)
    var out: PackedVector3Array = PackedVector3Array()
    for submesh: Dictionary in result["submeshes"] as Array:
        for vertex: Vector3 in submesh["positions"] as PackedVector3Array:
            out.append(transform * vertex)
    return out
