extends GateBase
## No object a terrain places is drawn inside out.
##
## **The oracle is the mesh's own geometry.** The signed volume of a closed triangle soup says
## which way it is wound without reference to any normal: sum `a · (b × c) / 6` over its
## triangles. Nothing about that is this project's opinion; it is the divergence theorem.
##
## **Which sign is outward is a convention, and this gate had it backwards.** Godot winds its
## front faces clockwise, so a closed mesh the engine draws solid encloses a *negative* volume by
## that sum: its own `BoxMesh` scores -1.0 of its bounding box, `SphereMesh` -0.52, `CylinderMesh`
## -0.78. Asserting the positive sign, this gate was green while the loader turned every building
## in the library inside out to satisfy it. `_control` measures those three primitives first and
## refuses to report on content until they come out negative.
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
## How much of a mesh's area has to look the same way before it is a sheet rather than a shape
## with an inside. Matches `ObjectWinding.SHEET_AGREEMENT`, because the gate and the loader have
## to agree on which meshes the question applies to.
const SHEET_AGREEMENT: float = 0.5
const LISTED: int = 6



static func meta() -> Dictionary:
    return {
        "name": "a_closed_object_encloses_its_own_volume",
        "proves": "every closed object mesh a terrain places is built winding outward, so none of them is drawn inside out",
        "oracle": GateBase.ORACLE_COMPUTED,
        "threshold": "negative signed volume — outward, in Godot's clockwise convention — for every mesh enclosing at least %.0f%% of its own bounding box" % (CLOSED_SHARE * 100.0),
        "why": (
            "a wall wound the wrong way renders as empty sky, which is pixel for pixel what a"
            + " correct empty sky looks like. Only the geometry settles it, and only against a"
            + " mesh the engine drew itself does the sign of the geometry mean anything."
        ),
        "budget_s": 300.0,
        "needs_gpu": false,
        "milestone": "C2",
    }


func run(_harness: Node) -> Dictionary:
    var control: String = _control()
    if control != "":
        return fail(control)
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
                # **A sheet has no inside and its volume is about where the origin sits.**
                # `hospital.mesh` is one helipad quad; once it is turned to face up it "encloses"
                # 0.92 of its box and this gate called it inside out. A shape with an inside has
                # faces looking every way at once, so the area-weighted sum of their directions
                # cancels; a sheet's does not. That is the filter, and it needs no threshold on
                # the volume at all.
                if _agreement(mesh) > SHEET_AGREEMENT:
                    open_shapes += 1
                    continue
                var share: float = _enclosed_share(mesh)
                if absf(share) < CLOSED_SHARE:
                    open_shapes += 1
                    continue
                closed += 1
                if share > 0.0:
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
        "%d closed object meshes all wind outward; %d open shapes left as their"
        % [closed, open_shapes] + " files have them",
        closed
    )


## The same measure on closed meshes the engine builds and draws itself, which fixes the sign.
func _control() -> String:
    # Meshes the engine builds and draws itself, used to fix which sign winds outward.
    var controls: Dictionary = {
        "BoxMesh": BoxMesh.new(), "SphereMesh": SphereMesh.new(),
        "CylinderMesh": CylinderMesh.new(),
    }
    for name: String in controls.keys():
        var mesh: ArrayMesh = ArrayMesh.new()
        mesh.add_surface_from_arrays(
            Mesh.PRIMITIVE_TRIANGLES, (controls[name] as PrimitiveMesh).get_mesh_arrays()
        )
        var share: float = _enclosed_share(mesh)
        if share >= 0.0:
            return (
                "the control fails: Godot's own %s encloses %+.2f of its box, so this gate's"
                % [name, share]
                + " idea of which sign winds outward is wrong and nothing it says about content"
                + " means anything"
            )
    return ""


## How much of a mesh's area looks the same way: 1.0 for a flat sheet, near 0 for a solid.
func _agreement(mesh: ArrayMesh) -> float:
    var sum: Vector3 = Vector3.ZERO
    var area: float = 0.0
    for surface: int in mesh.get_surface_count():
        var arrays: Array = mesh.surface_get_arrays(surface)
        var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
        var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] as PackedInt32Array
        for at: int in range(0, indices.size() - 2, 3):
            var a: Vector3 = points[indices[at]]
            var face: Vector3 = -(points[indices[at + 1]] - a).cross(
                points[indices[at + 2]] - a
            ) * 0.5
            sum += face
            area += face.length()
    return 0.0 if area <= 0.0 else sum.length() / area


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
