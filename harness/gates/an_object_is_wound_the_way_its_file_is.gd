extends GateBase
## A terrain object's triangles face the way the normals in its own file say they do.
##
## **The oracle is the normal the file carries for each vertex.** A triangle's own winding gives a
## facing; the author stored one too; they agree or the triangle is drawn backwards. Nothing here
## is this project's opinion about which way a wall should face, and that matters, because the
## obvious test — "do the triangles face away from the object's centre" — is meaningless for a
## sidewalk, a helipad or any other flat thing, and those are a third of a terrain's objects.
##
## **Which sign means "agrees" is not an opinion either, and this gate had it backwards.** Godot
## winds its front faces clockwise, so a triangle facing the way its normal points satisfies
## `cross(b - a, c - a) · normal <= 0`. Written the other way round, the gate was green for a year
## of work while asserting the opposite of the truth, and the loader was changed to satisfy it:
## every terrain object in the library was turned inside out to pass a test with a sign error in
## it. `_control` now measures the engine's own `BoxMesh`, `SphereMesh` and `CylinderMesh` first —
## meshes Godot draws correctly by definition — and refuses to report on content until they score
## 100%. A convention this gate asserts on its own is a convention nobody checked.

## What share of a mesh's triangles must agree.
##
## **A majority, not all of them.** Real content disagrees with itself: 9 of the 470 object meshes
## in this library carry between 8% and 18% of their triangles wound against their own normals,
## `lapaz-pole.mesh` worst at 18.4%, and that is how their authors left them. The fault this
## guards is wholesale — every triangle reversed — so the line sits where a mesh stops being
## mostly with its own normals and starts being mostly against them. Half is not a figure fitted
## to the measurements; it is the only place the two cases can be told apart without an exception
## list.
const MIN_AGREEING: float = 0.5
## Below this a mesh has nothing to measure.
const MIN_TRIANGLES: int = 8
const LISTED: int = 6



static func meta() -> Dictionary:
    return {
        "name": "an_object_is_wound_the_way_its_file_is",
        "proves": "every terrain object mesh is built with its triangles wound to agree with the vertex normals its own file carries",
        "oracle": GateBase.ORACLE_EXTERNAL,
        "threshold": "more than %.0f%% of each mesh's triangles agreeing with their own normals" % (MIN_AGREEING * 100.0),
        "why": (
            "the mesh reader reverses every triangle for the vehicle path, which mirrors geometry"
            + " somewhere nobody has isolated. A terrain object has no such path, so the same"
            + " reversal draws every building inside out — 0.0% of store08's triangles agreed"
            + " with their own normals."
        ),
        "budget_s": 300.0,
        "needs_gpu": false,
        "milestone": "C2",
    }


func run(_harness: Node) -> Dictionary:
    var control: String = _control()
    if control != "":
        return fail(control)
    var meshes: int = 0
    var triangles: int = 0
    var worst: float = 1.0
    var worst_name: String = ""
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
                var measured: Dictionary = _agreement(mesh)
                if (measured["triangles"] as int) < MIN_TRIANGLES:
                    continue
                meshes += 1
                triangles += measured["triangles"] as int
                var share: float = measured["share"] as float
                if share < worst:
                    worst = share
                    worst_name = file
                if share < MIN_AGREEING:
                    problems.append(
                        "%s: %s has %.1f%% of its %d triangles wound against their own normals"
                        % [summary["name"], file, (1.0 - share) * 100.0, measured["triangles"]]
                    )

    if meshes == 0:
        return ok("skipped: no terrain object mesh in this checkout carries normals", 0)
    if problems.size() > 0:
        return fail(
            "%d of %d object meshes are wound against their own files: %s"
            % [problems.size(), meshes, "; ".join(problems.slice(0, LISTED))],
            problems.size()
        )
    return ok(
        "%d object meshes, %d triangles, every mesh at least %.1f%% agreeing with its own"
        % [meshes, triangles, worst * 100.0] + " normals (worst %s)" % worst_name,
        worst
    )


## The same measure on meshes Godot generates and draws itself, which fixes the sign.
##
## `BoxMesh`, `SphereMesh` and `CylinderMesh` are correct by construction: the engine builds them,
## the engine draws them, and a convention they fail is a convention this file has wrong rather
## than a fault in them. Measured under the counter-clockwise reading they score 0.0%, which is
## how the sign error here was found.
func _control() -> String:
    # Meshes the engine builds and draws itself, used to fix which winding faces forward.
    var controls: Dictionary = {
        "BoxMesh": BoxMesh.new(), "SphereMesh": SphereMesh.new(),
        "CylinderMesh": CylinderMesh.new(),
    }
    for name: String in controls.keys():
        var mesh: ArrayMesh = ArrayMesh.new()
        mesh.add_surface_from_arrays(
            Mesh.PRIMITIVE_TRIANGLES, (controls[name] as PrimitiveMesh).get_mesh_arrays()
        )
        var share: float = _agreement(mesh)["share"] as float
        if share < 1.0:
            return (
                "the control fails: Godot's own %s has %.1f%% of its triangles disagreeing with"
                % [name, (1.0 - share) * 100.0]
                + " their own normals, so this gate's idea of which winding faces forward is"
                + " wrong and nothing it says about content means anything"
            )
    return ""


## What share of a mesh's triangles are wound to agree with the normals it carries.
func _agreement(mesh: ArrayMesh) -> Dictionary:
    var agree: int = 0
    var total: int = 0
    for surface: int in mesh.get_surface_count():
        var arrays: Array = mesh.surface_get_arrays(surface)
        var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
        var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL] as PackedVector3Array
        var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] as PackedInt32Array
        if normals.size() != points.size():
            continue
        for at: int in range(0, indices.size() - 2, 3):
            var a: int = indices[at]
            var face: Vector3 = (
                points[indices[at + 1]] - points[a]
            ).cross(points[indices[at + 2]] - points[a])
            if face.length_squared() <= 0.0:
                continue
            total += 1
            # Clockwise is forward here: see the note on `_control`.
            if face.dot(normals[a]) <= 0.0:
                agree += 1
    return {
        "triangles": total,
        "share": 1.0 if total == 0 else float(agree) / float(total),
    }
