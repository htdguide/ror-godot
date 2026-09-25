extends GateBase
## Builds the hero vehicle from an unmodified mod and renders it.
##
## This is the compatibility promise being exercised rather than described: the mod is
## read where it sits, with no conversion step and no re-export, and what appears on
## screen comes from its own meshes and its own textures.

const MOD_DIR: String = "assets/mods/ChevyS1023"
const TRUCK: String = "S10offroad.truck"
const PRESET: String = "hero_3q"
const MIN_FLEXBODIES: int = 8
const MIN_TEXTURES: int = 3
## A pickup has four wheels; fewer means the meshwheels rows were not understood.
const MIN_WHEELS: int = 4
## A compact pickup's wheelbase and track, in metres. Wheels placed from the wrong axle
## nodes, or with the axis mixed up, land outside these and nowhere near a real vehicle.
const MIN_WHEELBASE_M: float = 1.5
const MAX_WHEELBASE_M: float = 4.5
const MIN_TRACK_M: float = 1.0
const MAX_TRACK_M: float = 2.4
## Share of the frame the vehicle must occupy. Low enough to survive reframing, high
## enough that an empty frame or a vehicle collapsed to a speck cannot pass.
const MIN_COVERAGE: float = 0.05
## Height above the ground to stand the vehicle at, in metres.
const GROUND_CLEARANCE_M: float = 0.05
## Measured coverage as a share of the vehicle's projected screen area. Coverage alone
## cannot tell a whole vehicle from four wheels and a shadow: when the body silently
## stopped rendering, coverage stayed at 62% and the gate passed. Comparing against what
## the geometry should cover catches that.
const MIN_PROJECTED_FILL: float = 0.35
## How far a pixel must move to count as changed by the vehicle's arrival. Above sampling
## and compression noise, far below any real geometry.
const BACKGROUND_DELTA: float = 0.02


static func meta() -> Dictionary:
    return {
        "name": "vehicle_renders",
        "proves": "an unmodified community vehicle loads and renders from its own meshes and textures",
        "oracle": GateBase.ORACLE_EXTERNAL,
        "threshold": (
            "%d+ flexbodies, %d+ wheels, %d+ textures, vehicle covers %.0f%% of frame"
            % [MIN_FLEXBODIES, MIN_WHEELS, MIN_TEXTURES, MIN_COVERAGE * 100.0]
        ),
        "why": (
            "the mod is third-party and unmodified, so the check is that its own data"
            + " reaches the screen. Coverage is measured because every other signal here"
            + " is satisfied by a vehicle that loads perfectly and renders nothing."
        ),
        "budget_s": 120.0,
        "needs_gpu": true,
        "milestone": "M1",
    }


func run(harness: Node) -> Dictionary:
    var mod_dir: String = SourceScan.repo_root().path_join(MOD_DIR)
    if not DirAccess.dir_exists_absolute(mod_dir):
        return ok("skipped: hero asset not present at %s" % MOD_DIR, 0)
    var err: String = harness.setup_for(PRESET)
    if err != "":
        return fail(err)

    # The empty scene first. Coverage is then measured as what changed when the vehicle
    # arrived, which needs no assumptions about sky or floor colour — an earlier version
    # classified pixels by hue and broke the moment the background became a real sky.
    var empty_shot: Dictionary = await harness.capture_shot("vehicle_empty", "static", 6)
    if empty_shot["error"] != "":
        return fail(empty_shot["error"] as String)

    var result: Dictionary = VehicleBuilder.build(mod_dir, TRUCK)
    if (result.get("error", "") as String) != "":
        return fail(result["error"] as String)
    var built: int = int(result["built"])
    if built < MIN_FLEXBODIES:
        return fail(
            "only %d flexbodies built, expected %d+; skipped: %s"
            % [built, MIN_FLEXBODIES, ", ".join(result["skipped"] as PackedStringArray)],
            built
        )
    if int(result["wheels"]) < MIN_WHEELS:
        return fail(
            "only %d wheels built, expected %d+" % [int(result["wheels"]), MIN_WHEELS],
            int(result["wheels"])
        )
    if int(result["textures"]) < MIN_TEXTURES:
        return fail("only %d textures loaded" % int(result["textures"]), int(result["textures"]))

    var wheel_check: Dictionary = _check_wheel_geometry(result["root"] as Node3D)
    if (wheel_check["error"] as String) != "":
        return fail(wheel_check["error"] as String)

    var vehicle: Node3D = result["root"] as Node3D
    harness.world.add_child(vehicle)
    # Translate for the camera without touching the vehicle's own frame: overwriting the
    # root's position would discard the actor transform the bones are expressed against,
    # and the vehicle would sink through the floor while still reporting fine.
    var bounds: AABB = _world_bounds(vehicle)
    vehicle.position += Vector3(
        -bounds.get_center().x,
        -bounds.position.y + GROUND_CLEARANCE_M,
        -bounds.get_center().z
    )

    var probe_truck: TruckParser = TruckParser.new()
    probe_truck.parse_file(mod_dir.path_join(TRUCK))
    var shot: Dictionary = await harness.capture_shot("vehicle", "static", 12)
    if shot["error"] != "":
        return fail(shot["error"] as String)
    var coverage: float = _coverage_against(
        empty_shot["png"] as String, shot["png"] as String
    )
    if coverage < MIN_COVERAGE:
        return fail(
            "vehicle covers %.2f%% of the frame, under %.0f%%; artifact: %s"
            % [coverage * 100.0, MIN_COVERAGE * 100.0, shot["png"]],
            coverage
        )
    var fill: float = _projected_fill(harness, vehicle, coverage)
    if fill < MIN_PROJECTED_FILL:
        return fail(
            "vehicle covers %.1f%% of the frame but its geometry projects to %.1f%%"
            % [coverage * 100.0, coverage * 100.0 / maxf(fill, 0.0001)]
            + " (fill %.2f, need %.2f): most of it is not being drawn. Artifact: %s"
            % [fill, MIN_PROJECTED_FILL, shot["png"]],
            fill
        )
    return ok(
        "%d flexbodies, %d wheels (%.2f m wheelbase, %.2f m track), %d textures, %.0f%% coverage: %s"
        % [
            built, int(result["wheels"]), float(wheel_check["wheelbase"]),
            float(wheel_check["track"]), int(result["textures"]), coverage * 100.0, shot["png"]
        ],
        coverage
    )


## Color has no distance_to, so the separation is measured on the channels directly.
func _colour_distance(a: Color, b: Color) -> float:
    return Vector3(a.r - b.r, a.g - b.g, a.b - b.b).length()


## Wheel centres must form a rectangle the size of a real vehicle's footprint.
func _check_wheel_geometry(vehicle: Node3D) -> Dictionary:
    var centres: PackedVector3Array = PackedVector3Array()
    for child: Node in vehicle.get_children():
        if (child as Node3D) != null and child.name.begins_with("Wheel_"):
            centres.append((child as Node3D).position)
    if centres.size() < MIN_WHEELS:
        var names: PackedStringArray = PackedStringArray()
        for child: Node in vehicle.get_children():
            names.append(str(child.name))
        return {"error": "only %d wheel nodes among: %s" % [centres.size(), ", ".join(names)]}
    var box: AABB = AABB(centres[0], Vector3.ZERO)
    for centre: Vector3 in centres:
        box = box.expand(centre)
    # The longer horizontal span is the wheelbase, the shorter the track.
    var wheelbase: float = maxf(box.size.x, box.size.z)
    var track: float = minf(box.size.x, box.size.z)
    if wheelbase < MIN_WHEELBASE_M or wheelbase > MAX_WHEELBASE_M:
        return {"error": "wheelbase is %.2f m, outside %.1f-%.1f m" % [wheelbase, MIN_WHEELBASE_M, MAX_WHEELBASE_M]}
    if track < MIN_TRACK_M or track > MAX_TRACK_M:
        return {"error": "track is %.2f m, outside %.1f-%.1f m" % [track, MIN_TRACK_M, MAX_TRACK_M]}
    return {"error": "", "wheelbase": wheelbase, "track": track}


## World bounds of everything the vehicle draws.
func _world_bounds(vehicle: Node3D) -> AABB:
    var bounds: AABB = AABB()
    var started: bool = false
    for node: Node in _all_descendants(vehicle):
        var mesh_instance: MeshInstance3D = node as MeshInstance3D
        if mesh_instance == null or mesh_instance.mesh == null:
            continue
        var world: AABB = mesh_instance.global_transform * mesh_instance.mesh.get_aabb()
        bounds = world if not started else bounds.merge(world)
        started = true
    return bounds


func _all_descendants(node: Node) -> Array[Node]:
    var out: Array[Node] = []
    for child: Node in node.get_children():
        out.append(child)
        out.append_array(_all_descendants(child))
    return out


## Share of sampled pixels that changed when the vehicle was added. Background-agnostic
## by construction, which a colour classifier is not.
func _coverage_against(empty_path: String, with_vehicle_path: String) -> float:
    var empty: Image = Image.load_from_file(empty_path)
    var full: Image = Image.load_from_file(with_vehicle_path)
    if empty == null or full == null or empty.get_size() != full.get_size():
        return 0.0
    var size: Vector2i = full.get_size()
    var differing: int = 0
    var sampled: int = 0
    for y: int in range(0, size.y, 4):
        for x: int in range(0, size.x, 4):
            sampled += 1
            if _colour_distance(full.get_pixel(x, y), empty.get_pixel(x, y)) > BACKGROUND_DELTA:
                differing += 1
    return float(differing) / float(maxi(sampled, 1))


## Measured coverage divided by the share of the frame the vehicle's bounds project to.
## A value near 1 means what is on screen matches what should be; a low value means most
## of the geometry is not being drawn, whatever the raw coverage says.
func _projected_fill(harness: Node, vehicle: Node3D, coverage: float) -> float:
    var camera: Camera3D = harness.camera
    var bounds: AABB = _world_bounds(vehicle)
    var min_screen: Vector2 = Vector2(INF, INF)
    var max_screen: Vector2 = Vector2(-INF, -INF)
    for corner: int in 8:
        var point: Vector3 = bounds.get_endpoint(corner)
        if camera.is_position_behind(point):
            return 1.0  # Partly behind the camera: the estimate would be meaningless.
        var screen: Vector2 = camera.unproject_position(point)
        min_screen = min_screen.min(screen)
        max_screen = max_screen.max(screen)
    var viewport: Vector2 = harness.get_viewport().get_visible_rect().size
    var area: float = (
        (max_screen.x - min_screen.x) * (max_screen.y - min_screen.y)
        / maxf(viewport.x * viewport.y, 1.0)
    )
    return 1.0 if area <= 0.0 else coverage / area
