extends GateBase
## Reads every OGRE mesh in the hero asset and checks the geometry is structurally sound.
##
## The meshes are upstream community binaries this project did not author, so what is
## checked is what the format and physics guarantee: indices must address real vertices,
## normals must be unit length, triangles must be whole, and a truck part must be the
## size of a truck part. A golden would prove only that the reader still does whatever it
## did last time.

const MOD_DIR: String = "assets/mods/ChevyS1023"
const MIN_MESHES: int = 10
const MAX_PART_SIZE_M: float = 12.0
const MIN_PART_SIZE_M: float = 0.02
const NORMAL_TOLERANCE: float = 0.02
const NORMAL_SAMPLE_STRIDE: int = 37
## Below this vertex count a mesh is a stub, not geometry. Community packs ship
## placeholders — the hero asset has two, of 3 and 8 vertices — and holding them to a
## real part's dimensions would fail the gate on content that upstream loads happily.
const STUB_VERTEX_COUNT: int = 32
## A reader bug would flatten real geometry too, so an unexpected number of stubs is
## itself the signal. Two of 42 is the hero asset's true figure.
const MAX_STUB_SHARE: float = 0.25


static func meta() -> Dictionary:
    return {
        "name": "ogre_mesh_read",
        "proves": "every OGRE mesh in the hero asset reads into consistent, correctly scaled geometry",
        "oracle": GateBase.ORACLE_EXTERNAL,
        "threshold": (
            "all indices in range, triangle-complete, normals unit to %.2f, parts %.2f-%.0f m,"
            % [NORMAL_TOLERANCE, MIN_PART_SIZE_M, MAX_PART_SIZE_M]
            + " stubs under %d%% of meshes" % int(MAX_STUB_SHARE * 100.0)
        ),
        "why": (
            "these are third-party binaries, so the only trustworthy expectations are the"
            + " ones the format and the physical object guarantee. An off-by-one in the"
            + " vertex declaration produces geometry that still loads and is subtly wrong,"
            + " which unit-length normals and plausible bounds both catch."
        ),
        "budget_s": 60.0,
        "needs_gpu": false,
        "milestone": "M1",
    }


func run(_harness: Node) -> Dictionary:
    var dir_path: String = SourceScan.repo_root().path_join(MOD_DIR)
    if not DirAccess.dir_exists_absolute(dir_path):
        # The hero asset is not redistributable, so it is absent from a fresh clone. The
        # gate says so rather than failing, and rather than passing quietly.
        return ok("skipped: hero asset not present at %s" % MOD_DIR, 0)

    var meshes: PackedStringArray = SourceScan.find_files(dir_path, ["mesh"])
    if meshes.size() < MIN_MESHES:
        return fail("found %d meshes, expected at least %d" % [meshes.size(), MIN_MESHES])

    var reader: RefCounted = ClassDB.instantiate("OgreMeshReader") as RefCounted
    if reader == null:
        return fail("OgreMeshReader is not registered: the GDExtension did not load")

    var total_vertices: int = 0
    var total_triangles: int = 0
    var total_submeshes: int = 0
    var problems: PackedStringArray = PackedStringArray()
    var stubs: int = 0
    for path: String in meshes:
        var problem: String = _check_mesh(reader, path)
        if problem == "stub":
            stubs += 1
            continue
        if problem != "":
            problems.append(problem)
            continue
        var result: Dictionary = reader.read_file(path)
        for submesh: Dictionary in result["submeshes"] as Array:
            total_submeshes += 1
            total_vertices += (submesh["positions"] as PackedVector3Array).size()
            total_triangles += (submesh["indices"] as PackedInt32Array).size() / 3
    if problems.size() > 0:
        return fail(
            "%d of %d meshes failed: %s"
            % [problems.size(), meshes.size(), ", ".join(problems)],
            problems.size()
        )
    var stub_share: float = float(stubs) / float(meshes.size())
    if stub_share > MAX_STUB_SHARE:
        return fail(
            "%d of %d meshes are stubs (%.0f%%), over the %.0f%% cap: the reader is"
            % [stubs, meshes.size(), stub_share * 100.0, MAX_STUB_SHARE * 100.0]
            + " probably flattening real geometry rather than the content being stubby",
            stub_share
        )
    return ok(
        "%d meshes (%d stubs), %d submeshes, %d vertices, %d triangles"
        % [meshes.size(), stubs, total_submeshes, total_vertices, total_triangles],
        total_vertices
    )


func _check_mesh(reader: RefCounted, path: String) -> String:
    var name: String = path.get_file()
    var result: Dictionary = reader.read_file(path)
    if (result.get("error", "") as String) != "":
        return "%s: %s" % [name, result["error"]]
    var submeshes: Array = result["submeshes"] as Array
    if submeshes.is_empty():
        return "%s: no submeshes" % name

    var vertex_total: int = 0
    for submesh: Dictionary in submeshes:
        vertex_total += (submesh["positions"] as PackedVector3Array).size()
    if vertex_total < STUB_VERTEX_COUNT:
        return "stub"

    var bounds: AABB = AABB()
    var started: bool = false
    for submesh: Dictionary in submeshes:
        var positions: PackedVector3Array = submesh["positions"] as PackedVector3Array
        var indices: PackedInt32Array = submesh["indices"] as PackedInt32Array
        var normals: PackedVector3Array = submesh["normals"] as PackedVector3Array
        if positions.is_empty() or indices.is_empty():
            return "%s: empty submesh" % name
        if indices.size() % 3 != 0:
            return "%s: %d indices is not whole triangles" % [name, indices.size()]
        for index: int in indices:
            if index < 0 or index >= positions.size():
                return "%s: index %d outside 0..%d" % [name, index, positions.size() - 1]
        for i: int in range(0, normals.size(), NORMAL_SAMPLE_STRIDE):
            var length: float = normals[i].length()
            if absf(length - 1.0) > NORMAL_TOLERANCE:
                return "%s: normal %d has length %.3f" % [name, i, length]
        for position: Vector3 in positions:
            if not started:
                bounds = AABB(position, Vector3.ZERO)
                started = true
            bounds = bounds.expand(position)

    var longest: float = maxf(bounds.size.x, maxf(bounds.size.y, bounds.size.z))
    if longest > MAX_PART_SIZE_M or longest < MIN_PART_SIZE_M:
        return "%s: %.2f m on its longest axis" % [name, longest]
    return ""
