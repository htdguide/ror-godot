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
    # The rig is authored around its own origin, so centre it on the camera's subject.
    vehicle.position = -_centre_of(vehicle)
    harness.world.add_child(vehicle)

    var shot: Dictionary = await harness.capture_shot("vehicle", "static", 12)
    if shot["error"] != "":
        return fail(shot["error"] as String)
    var coverage: float = _coverage(shot["png"] as String)
    if coverage < MIN_COVERAGE:
        return fail(
            "vehicle covers %.2f%% of the frame, under %.0f%%; artifact: %s"
            % [coverage * 100.0, MIN_COVERAGE * 100.0, shot["png"]],
            coverage
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


func _centre_of(vehicle: Node3D) -> Vector3:
    var total: Vector3 = Vector3.ZERO
    var count: int = 0
    for child: Node in vehicle.get_children():
        var mesh_instance: MeshInstance3D = child as MeshInstance3D
        if mesh_instance == null:
            continue
        total += mesh_instance.position
        count += 1
    return Vector3.ZERO if count == 0 else total / float(count)


## Share of sampled pixels that differ from the empty-scene background. The ground plane
## and sky are flat, so anything textured stands out from them.
func _coverage(png_path: String) -> float:
    var image: Image = Image.load_from_file(png_path)
    if image == null:
        return 0.0
    var size: Vector2i = image.get_size()
    var sky: Color = image.get_pixel(size.x / 2, 8)
    var differing: int = 0
    var sampled: int = 0
    for y: int in range(0, size.y, 4):
        for x: int in range(0, size.x, 4):
            sampled += 1
            var pixel: Color = image.get_pixel(x, y)
            # Distance from both the sky and the grey checker floor.
            if absf(pixel.r - pixel.b) > 0.06 or pixel.g > pixel.b + 0.04:
                differing += 1
            elif _colour_distance(pixel, sky) > 0.35 and pixel.r > 0.05:
                differing += 1
    return float(differing) / float(maxi(sampled, 1))
