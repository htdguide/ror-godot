extends GateBase
## No object a terrain places is drawn inside out.
##
## **The content is not consistent and no blanket rule fixes it.** `OgreMeshReader` reverses every
## triangle, which the vehicle path needs and an object does not, so objects are wound back — and
## that is right for 79 of Port Starling's 90 distinct meshes and wrong for four. `store02`,
## `haus3`, `firehouse` and `haus4` are authored the other way round, **and their own vertex
## normals agree with it**, so a check against the normals passes them while from outside they are
## a hole. Reported from a window as "the outside texture is facing inside, from outside it looks
## transparent".
##
## **The oracle is the mesh's own geometry.** The signed volume of a closed triangle soup says
## which way it is wound without reference to any normal: sum `a · (b × c) / 6` over its
## triangles, and a mesh whose faces wind outward encloses a positive volume. Nothing about that
## is this project's opinion; it is the divergence theorem.
##
## **An open mesh encloses nothing in particular**, so the measure is only read where it is a real
## share of the mesh's own bounding box. A sidewalk, a road slab, a sign and a helipad all land
## near zero and are left exactly as their files have them — which is also why the obvious test,
## "do the faces point away from the centre", is useless here: it is meaningless for a third of a
## terrain's objects.

## How much of its bounding box a mesh must enclose before its volume is a statement about
## winding. Matches `ObjectWinding.CLOSED_SHARE`, because the gate and the loader have to agree on
## which meshes the question applies to.
const CLOSED_SHARE: float = 0.05
const MIN_TRIANGLES: int = 8
const LISTED: int = 6


static func meta() -> Dictionary:
    return {
        "name": "a_closed_object_encloses_its_own_volume",
        "proves": "every closed object mesh a terrain places is built winding outward, so none of them is drawn inside out",
        "oracle": GateBase.ORACLE_COMPUTED,
        "threshold": "positive signed volume for every mesh enclosing at least %.0f%% of its own bounding box" % (CLOSED_SHARE * 100.0),
        "why": (
            "four of Port Starling's meshes are authored wound the other way round and their own"
            + " normals agree with it, so the gate that checks winding against normals passes"
            + " them while from outside they are a hole. Only the geometry settles it."
        ),
        "budget_s": 300.0,
        "needs_gpu": false,
        "milestone": "C2",
    }


func run(_harness: Node) -> Dictionary:
    var closed: int = 0
    var open_shapes: int = 0
    var problems: PackedStringArray = PackedStringArray()
    for summary: Dictionary in RorTerrainLibrary.summaries():
        if (summary["error"] as String) != "":
            continue
        var loaded: Dictionary = RorTerrainLibrary.load_named(summary["name"] as String)
        if (loaded.get("error", "") as String) != "":
            continue
        var terrain: RorTerrain = loaded["terrain"] as RorTerrain
        var state: Dictionary = RorObjects.state(terrain)
        var seen: Dictionary = {}
        for placement: Dictionary in RorObjects.placements(terrain):
            var odef: Dictionary = RorObjects.definition(
                terrain, placement["name"] as String, state
            )
            if (odef.get("error", "") as String) != "":
                continue
            for file: String in odef["meshes"] as PackedStringArray:
                if seen.has(file):
                    continue
                seen[file] = true
                var mesh: ArrayMesh = RorObjects.mesh_of(terrain, file, state)
                if mesh == null:
                    continue
                var share: float = _enclosed_share(mesh)
                if absf(share) < CLOSED_SHARE:
                    open_shapes += 1
                    continue
                closed += 1
                if share < 0.0:
                    problems.append(
                        "%s: %s encloses %.2f of its own box, inside out"
                        % [summary["name"], file, share]
                    )

    if closed == 0:
        return ok("skipped: no closed object mesh in this checkout", 0)
    if problems.size() > 0:
        return fail(
            "%d of %d closed object meshes are drawn inside out: %s"
            % [problems.size(), closed, "; ".join(problems.slice(0, LISTED))],
            problems.size()
        )
    return ok(
        "%d closed object meshes all enclose a positive volume; %d open shapes left as their"
        % [closed, open_shapes] + " files have them",
        closed
    )


## What share of its own bounding box a mesh encloses, signed. Near zero for an open shape.
func _enclosed_share(mesh: ArrayMesh) -> float:
    var volume: float = 0.0
    var triangles: int = 0
    for surface: int in mesh.get_surface_count():
        var arrays: Array = mesh.surface_get_arrays(surface)
        var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
        var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] as PackedInt32Array
        for at: int in range(0, indices.size() - 2, 3):
            volume += points[indices[at]].dot(
                points[indices[at + 1]].cross(points[indices[at + 2]])
            ) / 6.0
            triangles += 1
    if triangles < MIN_TRIANGLES:
        return 0.0
    var box: Vector3 = mesh.get_aabb().size
    var capacity: float = box.x * box.y * box.z
    return 0.0 if capacity <= 0.0 else volume / capacity
