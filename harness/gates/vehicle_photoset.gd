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

## **More than the hero truck.** A photoset exists so that a fault nobody is looking for shows up
## in a view nobody thought to take, and one vehicle cannot do that for a library of 69: every
## wheel-section fault, every material fault and every suspension fault found so far was invisible
## on the S10 and obvious on a second car.
const VEHICLES: Array[Dictionary] = [
    {"dir": "assets/mods/ChevyS1023", "file": "S10offroad.truck", "tag": "s10"},
    {"dir": "assets/mods/mazda626gf", "file": "mazda626sd18i-mt.car", "tag": "mazda"},
]
const BASE_PRESET: String = "hero_3q"
const CONVERGE: int = 6
## Every view must show something. The interior sees less of the vehicle than the
## outside views do, and the bottom view is mostly frame rails, so the bound is low: this
## catches an empty frame, not a poor composition.
const MIN_COVERAGE: float = 0.02
const LABEL_MARGIN: int = 32
const DIGIT_WIDTH: int = 60
const DIGIT_HEIGHT: int = 110
const DIGIT_THICKNESS: int = 14


static func meta() -> Dictionary:
    return {
        "name": "vehicle_photoset",
        "proves": "the vehicle is present and drawn from every side, including its interior",
        # photographing the vehicle from eight sides builds it and draws it, which is what
        # vehicle_renders proves.
        "builds_on": ["vehicle_renders"],
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
    var reports: PackedStringArray = PackedStringArray()
    for entry: Dictionary in VEHICLES:
        var outcome: Dictionary = await _photograph(harness, entry)
        if (outcome["error"] as String) != "":
            return fail("%s: %s" % [entry["file"], outcome["error"]], outcome.get("thin", 0))
        reports.append("%s %s" % [entry["tag"], outcome["report"]])
    return ok("; ".join(reports), 0)


func _photograph(harness: Node, entry: Dictionary) -> Dictionary:
    var mod_dir: String = SourceScan.repo_root().path_join(entry["dir"] as String)
    if not DirAccess.dir_exists_absolute(mod_dir):
        return {"error": "", "report": "skipped: not in this checkout"}
    var err: String = harness.setup_for(BASE_PRESET)
    if err != "":
        return {"error": err, "report": ""}

    var built: Dictionary = VehicleBuilder.build(mod_dir, entry["file"] as String)
    if (built.get("error", "") as String) != "":
        return {"error": built["error"] as String, "report": ""}
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

    var thin: PackedStringArray = PackedStringArray()
    var report: PackedStringArray = PackedStringArray()
    for index: int in Photoset.VIEWS.size():
        var view: String = Photoset.VIEWS[index]
        var placement: Dictionary = Photoset.placement(view, bounds, interior)
        harness.camera.position = placement["pos"] as Vector3
        harness.camera.look_at_from_position(
            placement["pos"] as Vector3, placement["look_at"] as Vector3, Vector3.UP
        )
        var shot: Dictionary = await harness.capture_shot(
            "photoset/%s/%s" % [entry["tag"], view], "static", CONVERGE
        )
        if shot["error"] != "":
            return {"error": "%s: %s" % [view, shot["error"]], "report": ""}
        _stamp_number(shot["png"] as String, index + 1)
        var coverage: float = _coverage(shot["png"] as String)
        report.append("%s %.0f%%" % [view, coverage * 100.0])
        if coverage < MIN_COVERAGE:
            thin.append("%s (%.1f%%)" % [view, coverage * 100.0])

    harness.world.remove_child(root)
    root.queue_free()
    if thin.size() > 0:
        return {
            "error": (
                "%d of %d views are effectively empty: %s"
                % [thin.size(), Photoset.VIEWS.size(), ", ".join(thin)]
            ),
            "thin": thin.size(),
            "report": "",
        }
    return {"error": "", "report": "%d views: %s" % [Photoset.VIEWS.size(), ", ".join(report)]}


## Stamps a view's number into the corner of its capture.
##
## Drawn as filled rectangles rather than text. Godot's Label in a CanvasLayer did not
## appear in the captures, and ffmpeg's drawtext filter is missing from this build, so
## both of the obvious ways to label an image failed silently. Seven segments cannot.
const SEGMENTS: Dictionary = {
    1: [2, 5],
    2: [0, 2, 3, 4, 6],
    3: [0, 2, 3, 5, 6],
    4: [1, 2, 3, 5],
    5: [0, 1, 3, 5, 6],
    6: [0, 1, 3, 4, 5, 6],
    7: [0, 2, 5],
    8: [0, 1, 2, 3, 4, 5, 6],
}


func _stamp_number(png_path: String, number: int) -> void:
    var image: Image = Image.load_from_file(png_path)
    if image == null:
        return
    var x: int = LABEL_MARGIN
    var y: int = LABEL_MARGIN
    var w: int = DIGIT_WIDTH
    var h: int = DIGIT_HEIGHT
    var t: int = DIGIT_THICKNESS
    # Backing plate, so the digit reads over sky or bodywork alike.
    _fill(image, x - t, y - t, w + t * 3, h + t * 3, Color(0.0, 0.0, 0.0, 1.0))
    # Segment rectangles: 0 top, 1 upper left, 2 upper right, 3 middle, 4 lower left,
    # 5 lower right, 6 bottom.
    var boxes: Array = [
        [x, y, w, t], [x, y, t, h / 2], [x + w - t, y, t, h / 2],
        [x, y + h / 2 - t / 2, w, t], [x, y + h / 2, t, h / 2],
        [x + w - t, y + h / 2, t, h / 2], [x, y + h - t, w, t],
    ]
    for segment: int in SEGMENTS.get(number, []) as Array:
        var box: Array = boxes[segment]
        _fill(image, box[0] as int, box[1] as int, box[2] as int, box[3] as int, Color.WHITE)
    image.save_png(png_path)


func _fill(image: Image, x: int, y: int, w: int, h: int, colour: Color) -> void:
    var size: Vector2i = image.get_size()
    for row: int in range(maxi(y, 0), mini(y + h, size.y)):
        for column: int in range(maxi(x, 0), mini(x + w, size.x)):
            image.set_pixel(column, row, colour)


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
    var cabin: AABB = _cabin_bounds(built)
    if cabin.size != Vector3.ZERO:
        # A rig lists several switchable cinecams and only some of them are inside the
        # cab. The hero truck's first is 0.22 m above its own roof, which pointed this
        # shot at the sky over the bodywork; its second is the driver's eye. Take the
        # first that is actually within the cab, which is a property of the vehicle
        # rather than a guess about which index a mod author used.
        for position: Vector3 in truck.cinecams:
            if cabin.has_point(position):
                return root.global_transform * (rig_to_local * position)
        # No cinecam is inside the cab. The upper middle of the cab is a better guess
        # than any of them, and better than the whole vehicle's centre, which lands in
        # the engine bay on a truck whose bed is half its length.
        var eye: Vector3 = cabin.get_center() + Vector3(0.0, cabin.size.y * 0.2, 0.0)
        return root.global_transform * (rig_to_local * eye)
    if truck.has_cinecam:
        return root.global_transform * (rig_to_local * truck.cinecam_position)
    return bounds.get_center() + Vector3(0.0, bounds.size.y * 0.2, 0.0)


## Rest bounds of the cab volume, in rig space.
##
## The glazing is the better subject than the body: a pickup's body part spans the bed as
## well as the cab, so a point can be inside it and still be out in the open air over the
## load bed. The windows enclose the cab and nothing else.
func _cabin_bounds(built: Dictionary) -> AABB:
    for subject: String in ["window", "body"]:
        var box: AABB = _part_bounds(built, subject)
        if box.size != Vector3.ZERO:
            return box
    return AABB()


func _part_bounds(built: Dictionary, subject: String) -> AABB:
    for part: SkinnedFlexbody in built["parts"] as Array[SkinnedFlexbody]:
        if not str(part.mesh_instance.name).to_lower().contains(subject):
            continue
        var box: AABB = AABB(part.rest_vertices[0], Vector3.ZERO)
        for vertex: Vector3 in part.rest_vertices:
            box = box.expand(vertex)
        return box
    return AABB()


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
