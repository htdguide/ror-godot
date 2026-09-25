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
## Share of the frame the vehicle must occupy. Low enough to survive reframing, high
## enough that an empty frame or a vehicle collapsed to a speck cannot pass.
const MIN_COVERAGE: float = 0.05


static func meta() -> Dictionary:
    return {
        "name": "vehicle_renders",
        "proves": "an unmodified community vehicle loads and renders from its own meshes and textures",
        "oracle": GateBase.ORACLE_EXTERNAL,
        "threshold": (
            "%d+ flexbodies placed, %d+ textures loaded, vehicle covers %.0f%% of frame"
            % [MIN_FLEXBODIES, MIN_TEXTURES, MIN_COVERAGE * 100.0]
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
    if int(result["textures"]) < MIN_TEXTURES:
        return fail("only %d textures loaded" % int(result["textures"]), int(result["textures"]))

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
        "%d flexbodies, %d textures, %.0f%% frame coverage: %s"
        % [built, int(result["textures"]), coverage * 100.0, shot["png"]],
        coverage
    )


## Color has no distance_to, so the separation is measured on the channels directly.
func _colour_distance(a: Color, b: Color) -> float:
    return Vector3(a.r - b.r, a.g - b.g, a.b - b.b).length()


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
