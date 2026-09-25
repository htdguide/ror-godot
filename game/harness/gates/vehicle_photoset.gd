extends GateBase
## Photographs the vehicle from every side, including inside it.
##
## One angle hides too much. In this project a door has looked open from the front, a
## tailgate has looked missing, and single-sided panels have looked transparent — each
## obvious from another view and invisible from the one being used. The set is front,
## back, left, right, top, bottom, three-quarter and interior, framed from the vehicle's
## own bounds so it fits any vehicle.
##
## The gate checks each view actually contains the vehicle. Judging how it looks is for a
## person; `tools/photoset.sh` assembles the set into one sheet for that.

const MOD_DIR: String = "assets/mods/ChevyS1023"
const TRUCK: String = "S10offroad.truck"
const BASE_PRESET: String = "hero_3q"
const CONVERGE: int = 6
## Every view must show something. The interior sees less of the vehicle than the
## outside views do, and the bottom view is mostly frame rails, so the bound is low: this
## catches an empty frame, not a poor composition.
const MIN_COVERAGE: float = 0.02


static func meta() -> Dictionary:
    return {
        "name": "vehicle_photoset",
        "proves": "the vehicle is present and drawn from every side, including its interior",
        "oracle": GateBase.ORACLE_INVARIANT,
        "threshold": "each of the %d views covers at least %.0f%% of its frame" % [
            Photoset.VIEWS.size(), MIN_COVERAGE * 100.0
        ],
        "why": (
            "geometry faults hide from single viewpoints. Every model problem found here"
            + " so far — an open-looking door, a missing-looking tailgate, panels"
            + " transparent from one side — was obvious from a view nobody was taking."
        ),
        "budget_s": 180.0,
        "needs_gpu": true,
        "milestone": "M2",
    }


func run(harness: Node) -> Dictionary:
    var mod_dir: String = SourceScan.repo_root().path_join(MOD_DIR)
    if not DirAccess.dir_exists_absolute(mod_dir):
        return ok("skipped: hero asset not present at %s" % MOD_DIR, 0)
    var err: String = harness.setup_for(BASE_PRESET)
    if err != "":
        return fail(err)

    var built: Dictionary = VehicleBuilder.build(mod_dir, TRUCK)
    if (built.get("error", "") as String) != "":
        return fail(built["error"] as String)
    var root: Node3D = built["root"] as Node3D
    harness.world.add_child(root)
    var truck: TruckParser = built["truck"] as TruckParser

    var bounds: AABB = VehicleBuilder.world_bounds(root)
    # The driver's eye. A cinecam gives it exactly; this vehicle declares none, so fall
    # back to the cameras section's centre node raised to head height. Using the bounds
    # centre instead puts the camera inside the bodywork, looking at the inside of the
    # panels, which is what the first run of this gate did.
    var rig_to_local: Transform3D = built["rig_to_local"] as Transform3D
    var interior: Vector3 = _cabin_eye(built, truck, rig_to_local, bounds)

    var empty: Dictionary = {}
    var thin: PackedStringArray = PackedStringArray()
    var report: PackedStringArray = PackedStringArray()
    for view: String in Photoset.VIEWS:
        var placement: Dictionary = Photoset.placement(view, bounds, interior)
        harness.camera.position = placement["pos"] as Vector3
        harness.camera.look_at_from_position(
            placement["pos"] as Vector3, placement["look_at"] as Vector3, Vector3.UP
        )
        var shot: Dictionary = await harness.capture_shot("photoset/" + view, "static", CONVERGE)
        if shot["error"] != "":
            return fail("%s: %s" % [view, shot["error"]])
        var coverage: float = _coverage(shot["png"] as String)
        report.append("%s %.0f%%" % [view, coverage * 100.0])
        if coverage < MIN_COVERAGE:
            thin.append("%s (%.1f%%)" % [view, coverage * 100.0])

    if thin.size() > 0:
        return fail(
            "%d of %d views are effectively empty: %s" % [thin.size(), Photoset.VIEWS.size(), ", ".join(thin)],
            thin.size()
        )
    return ok("%d views captured: %s" % [Photoset.VIEWS.size(), ", ".join(report)], 0)


## Where a driver's eyes would be.
##
## A cinecam states it exactly. This vehicle declares none, and the cameras section's
## centre node turned out to sit ahead of the cab — an interior shot from there looks out
## over the hood. Falling back to the body part's own bounds puts the camera inside the
## cabin, which is the thing the shot is for.
func _cabin_eye(
    built: Dictionary, truck: TruckParser, rig_to_local: Transform3D, bounds: AABB
) -> Vector3:
    var root: Node3D = built["root"] as Node3D
    if truck.has_cinecam:
        return root.global_transform * (rig_to_local * truck.cinecam_position)
    for part: SkinnedFlexbody in built["parts"] as Array[SkinnedFlexbody]:
        if not str(part.mesh_instance.name).to_lower().contains("body"):
            continue
        var box: AABB = AABB(part.rest_vertices[0], Vector3.ZERO)
        for vertex: Vector3 in part.rest_vertices:
            box = box.expand(vertex)
        var eye: Vector3 = box.get_center() + Vector3(0.0, box.size.y * 0.15, 0.0)
        return root.global_transform * (rig_to_local * eye)
    return bounds.get_center() + Vector3(0.0, bounds.size.y * 0.2, 0.0)


## Share of the frame that is not sky or ground. The vehicle is the only other thing in
## the scene, so anything that is neither is it.
func _coverage(png_path: String) -> float:
    var image: Image = Image.load_from_file(png_path)
    if image == null:
        return 0.0
    var size: Vector2i = image.get_size()
    var sky: Color = image.get_pixel(size.x / 2, 4)
    var floor_colour: Color = image.get_pixel(size.x / 2, size.y - 4)
    var differing: int = 0
    var sampled: int = 0
    for y: int in range(0, size.y, 4):
        for x: int in range(0, size.x, 4):
            sampled += 1
            var pixel: Color = image.get_pixel(x, y)
            var from_sky: float = Vector3(
                pixel.r - sky.r, pixel.g - sky.g, pixel.b - sky.b
            ).length()
            var from_floor: float = Vector3(
                pixel.r - floor_colour.r, pixel.g - floor_colour.g, pixel.b - floor_colour.b
            ).length()
            if from_sky > 0.12 and from_floor > 0.12:
                differing += 1
    return float(differing) / float(maxi(sampled, 1))
