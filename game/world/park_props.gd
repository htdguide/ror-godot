class_name ParkProps
extends RefCounted
## Everything in the test park that a heightfield cannot be: ramps, walls, kerbs, poles, crates,
## rocks.
##
## One list, two consumers. `boxes()` is the single description of what is there; `build()` draws
## it and `apply_to_solver()` hands the same transforms to the solver as static obstacles. A prop
## that is drawn somewhere other than where it is collided is the oldest bug in this kind of scene
## and the reason these are not two lists — `park_props_match_their_meshes` measures that they are
## still one.
##
## Boxes sit *on* the ground: each is seated by finding its own lowest corner and lifting it, which
## is done numerically rather than by working out the trigonometry per prop, because the sign of a
## rotation about the wrong axis is exactly the sort of thing that puts a ramp underground.

## Ramps are boxes, so the part under the ramp face is buried. This is how thick they are.
const RAMP_THICKNESS_M: float = 1.2
## Rocks vary by a hash of their position, like the valley's trees.
const ROCK_HASH_SALT: int = 0x27D4EB2F


## Every prop in the park, as {"transform", "half", "kind", "surface"}.
static func boxes() -> Array[Dictionary]:
    var out: Array[Dictionary] = []
    _add_ramps(out)
    _add_rocks(out)
    _add_walls(out)
    _add_skid_pad_ring(out)
    return out


## Draws the props, one multimesh per kind.
static func build() -> Node3D:
    var root: Node3D = Node3D.new()
    root.name = "ParkProps"
    var by_kind: Dictionary = {}
    for box: Dictionary in boxes():
        var kind: String = box["kind"] as String
        if not by_kind.has(kind):
            by_kind[kind] = []
        (by_kind[kind] as Array).append(box)
    for kind: String in by_kind.keys():
        root.add_child(_multimesh(kind, by_kind[kind] as Array))
    return root


## Hands the same boxes to a solver as static obstacles. Returns how many were added.
static func apply_to_solver(solver: RefCounted) -> int:
    solver.clear_obstacles()
    var added: int = 0
    for box: Dictionary in boxes():
        solver.add_obstacle_box(
            box["transform"] as Transform3D,
            box["half"] as Vector3,
            GroundModels.index_of(box["surface"] as String)
        )
        added += 1
    return added


## --- The segments -----------------------------------------------------------------------------


## The ramp yard: a row of ramps of increasing angle, a split ramp that lifts one side of the rig
## only, and a kicker on the road itself.
static func _add_ramps(out: Array[Dictionary]) -> void:
    for index: int in ParkCfg.RAMPS.size():
        var ramp: Array = ParkCfg.RAMPS[index] as Array
        var angle: float = deg_to_rad(float(ramp[0]))
        var width: float = float(ramp[1])
        var length: float = float(ramp[2])
        var at: Vector2 = Vector2(
            ParkCfg.RAMP_YARD_X_M + float(index) * ParkCfg.RAMP_SPACING_M, ParkCfg.RAMP_YARD_Z_M
        )
        out.append(_seated(
            at, Basis(Vector3.RIGHT, -angle),
            Vector3(width * 0.5, RAMP_THICKNESS_M * 0.5, length * 0.5), "ramp", "concrete"
        ))
    # The split ramp: the same wedge, but only under one wheel track.
    var split_at: Vector2 = Vector2(
        ParkCfg.RAMP_YARD_X_M + float(ParkCfg.RAMPS.size()) * ParkCfg.RAMP_SPACING_M,
        ParkCfg.RAMP_YARD_Z_M
    )
    out.append(_seated(
        split_at + Vector2(0.0, 0.0),
        Basis(Vector3.RIGHT, -deg_to_rad(ParkCfg.SPLIT_RAMP_ANGLE_DEG)),
        Vector3(ParkCfg.SPLIT_RAMP_WIDTH_M * 0.5, RAMP_THICKNESS_M * 0.5, 7.0),
        "ramp", "concrete"
    ))
    # The kicker, on the straight itself: something to leave the ground from without turning off.
    out.append(_seated(
        Vector2(-40.0, 0.0), Basis(Vector3.UP, PI * 0.5) * Basis(
            Vector3.RIGHT, -deg_to_rad(ParkCfg.KICKER_ANGLE_DEG)
        ),
        Vector3(ParkCfg.ROAD_HALF_WIDTH_M, RAMP_THICKNESS_M * 0.5,
                ParkCfg.KICKER_LENGTH_M * 0.5),
        "ramp", "asphalt"
    ))


## The rock garden: a grid of boxes, each turned and sized by a hash of where it stands, so it is
## a field of rocks rather than a row of identical blocks.
static func _add_rocks(out: Array[Dictionary]) -> void:
    for column: int in ParkCfg.ROCKS_ACROSS:
        for row: int in ParkCfg.ROCKS_ALONG:
            var at: Vector2 = Vector2(
                ParkCfg.ROCKS_X_M + float(column) * ParkCfg.ROCK_SPACING_M,
                ParkCfg.ROCKS_Z_M + float(row) * ParkCfg.ROCK_SPACING_M
            )
            var jitter: Vector2 = Vector2(
                (_hash01(at, 1) - 0.5) * ParkCfg.ROCK_SPACING_M * 0.7,
                (_hash01(at, 2) - 0.5) * ParkCfg.ROCK_SPACING_M * 0.7
            )
            var size: float = lerpf(ParkCfg.ROCK_MIN_M, ParkCfg.ROCK_MAX_M, _hash01(at, 3))
            var basis: Basis = (
                Basis(Vector3.UP, _hash01(at, 4) * TAU)
                * Basis(Vector3.RIGHT, (_hash01(at, 5) - 0.5) * 0.6)
                * Basis(Vector3.FORWARD, (_hash01(at, 6) - 0.5) * 0.6)
            )
            out.append(_seated(
                at + jitter, basis,
                Vector3(size, size * lerpf(0.5, 0.9, _hash01(at, 7)), size * lerpf(0.7, 1.3,
                        _hash01(at, 8))),
                "rock", ParkCfg.ROCK_SURFACE
            ))


## The crash yard: the things to drive into, one of each kind.
static func _add_walls(out: Array[Dictionary]) -> void:
    for wall: Array in ParkCfg.WALLS:
        var kind: String = wall[0] as String
        var at: Vector2 = Vector2(float(wall[1]), ParkCfg.CRASH_YARD_Z_M + float(wall[2]))
        var width: float = float(wall[3])
        var height: float = float(wall[4])
        var thickness: float = float(wall[5])
        match kind:
            "poles":
                for index: int in ParkCfg.POLE_COUNT:
                    var share: float = (
                        float(index) / float(maxi(ParkCfg.POLE_COUNT - 1, 1)) - 0.5
                    )
                    out.append(_seated(
                        at + Vector2(share * width, 0.0), Basis(),
                        Vector3(thickness * 0.5, height * 0.5, thickness * 0.5),
                        kind, "concrete"
                    ))
            "crates":
                var crate: float = width / float(ParkCfg.CRATE_COLUMNS)
                for column: int in ParkCfg.CRATE_COLUMNS:
                    for level: int in ParkCfg.CRATE_ROWS:
                        var offset: float = (
                            float(column) - float(ParkCfg.CRATE_COLUMNS - 1) * 0.5
                        ) * crate
                        var box: Dictionary = _seated(
                            at + Vector2(offset, 0.0), Basis(),
                            Vector3(crate * 0.45, crate * 0.45, crate * 0.45), kind, "concrete"
                        )
                        # Stacked: each level sits on the one below rather than on the ground.
                        var transform: Transform3D = box["transform"] as Transform3D
                        transform.origin.y += float(level) * crate * 0.9
                        box["transform"] = transform
                        out.append(box)
            _:
                out.append(_seated(
                    at, Basis(), Vector3(width * 0.5, height * 0.5, thickness * 0.5),
                    kind, "concrete"
                ))


## A ring of kerbs around the skid pad, so leaving it is something a driver feels.
static func _add_skid_pad_ring(out: Array[Dictionary]) -> void:
    var segments: int = 48
    for index: int in segments:
        var angle: float = float(index) / float(segments) * TAU
        var at: Vector2 = ParkCfg.SKID_PAD_CENTRE + Vector2(
            cos(angle), sin(angle)
        ) * (ParkCfg.SKID_PAD_RADIUS_M + 1.0)
        out.append(_seated(
            at, Basis(Vector3.UP, -angle), Vector3(0.35, 0.09, 2.4), "kerb", "concrete"
        ))


## --- Shared pieces ------------------------------------------------------------------------------


## A box at a place, turned, and lifted until its lowest corner rests on the ground there.
##
## Seated numerically: the alternative is trigonometry per prop kind, and the sign of a rotation
## about the wrong axis is what buries a ramp or floats it.
static func _seated(
    at: Vector2, basis: Basis, half: Vector3, kind: String, surface: String
) -> Dictionary:
    var lowest: float = INF
    for corner: Vector3 in [
        Vector3(half.x, half.y, half.z), Vector3(half.x, half.y, -half.z),
        Vector3(half.x, -half.y, half.z), Vector3(half.x, -half.y, -half.z),
        Vector3(-half.x, half.y, half.z), Vector3(-half.x, half.y, -half.z),
        Vector3(-half.x, -half.y, half.z), Vector3(-half.x, -half.y, -half.z),
    ]:
        lowest = minf(lowest, (basis * corner).y)
    var ground: float = ParkShape.height_at_world(at.x, at.y)
    return {
        "transform": Transform3D(basis, Vector3(at.x, ground - lowest, at.y)),
        "half": half,
        "kind": kind,
        "surface": surface,
    }


static func _multimesh(kind: String, boxes_of_kind: Array) -> MultiMeshInstance3D:
    var mesh: BoxMesh = BoxMesh.new()
    mesh.size = Vector3.ONE
    var material: StandardMaterial3D = StandardMaterial3D.new()
    material.albedo_color = ParkCfg.PROP_COLOURS.get(kind, Color(0.5, 0.5, 0.5)) as Color
    material.roughness = ParkCfg.PROP_ROUGHNESS
    mesh.material = material
    var multimesh: MultiMesh = MultiMesh.new()
    multimesh.transform_format = MultiMesh.TRANSFORM_3D
    multimesh.mesh = mesh
    multimesh.instance_count = boxes_of_kind.size()
    for index: int in boxes_of_kind.size():
        var box: Dictionary = boxes_of_kind[index] as Dictionary
        var transform: Transform3D = box["transform"] as Transform3D
        # The mesh is a unit cube, so the box's own half extents are its scale.
        transform.basis = transform.basis.scaled((box["half"] as Vector3) * 2.0)
        multimesh.set_instance_transform(index, transform)
    var instance: MultiMeshInstance3D = MultiMeshInstance3D.new()
    instance.name = kind
    instance.multimesh = multimesh
    return instance


## A stable 0-to-1 value for a place and a purpose, so the rock field is the same on every machine.
static func _hash01(at: Vector2, purpose: int) -> float:
    var mixed: int = (int(at.x * 16.0) * 73856093) ^ (int(at.y * 16.0) * 19349663)
    mixed = ((mixed ^ (purpose * 83492791)) ^ ROCK_HASH_SALT) & 0x7FFFFFFF
    mixed = (mixed * 1103515245 + 12345) & 0x7FFFFFFF
    return float(mixed % 100000) / 100000.0
