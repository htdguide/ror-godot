class_name PlayShot
extends RefCounted
## A screenshot and everything needed to know what is in it.
##
## **Asked for 2026-10-03, and the reason is specific.** A screenshot of a fault is handed over to
## be acted on, and a picture alone does not say where it was taken, which way the camera was
## pointing, or which of a map's 667 object instances the untextured thing in the middle of the
## frame actually is. Three faults this week were reported as "that house has no texture", and
## every one of them cost a round trip to work out which house. The frame knows all of it, so the
## frame writes it down.
##
## A `.json` sidecar lands beside the `.png` with the same name. It has a one-line `summary` for
## reading at a glance and the rest for looking things up: the camera's position and bearing, the
## ground under it, what the view ray lands on, and **every object batch in the frustum with its
## distance and how far off centre it is**. That last list is the one that answers "which house":
## the thing being complained about is usually the thing nearest the middle.
##
## Nothing here is sampled from a renderer twice — the numbers come from the same frame that was
## written to the png, read after the capture rather than before.

## How far along the view ray to look for the ground, and how finely.
const RAY_LENGTH_M: float = 6000.0
const RAY_STEP_M: float = 2.0
## How many object batches to name. Beyond this the list stops being readable, and the ones that
## matter are the near and the central, which are what it is sorted by.
const LISTED_BATCHES: int = 14
## Compass points, one per 45 degrees from north.
const COMPASS: PackedStringArray = [
    "N", "NE", "E", "SE", "S", "SW", "W", "NW",
]


## Writes `path` and its sidecar. `context` carries the live scene: `viewport`, `camera`, `world`,
## `terrain` (a `RorTerrain` or null), `map`, `weather`, `mode`, and `drive` (a `PlayDrive` or
## null). Returns an error string, empty when both files are written.
static func save(path: String, context: Dictionary) -> String:
    var viewport: Viewport = context["viewport"] as Viewport
    var error: String = HarnessCapture.capture_png(viewport, path)
    if error != "":
        return error
    return HarnessCapture.write_manifest(path.get_basename() + ".json", _facts(context))


## One line that says where this was taken from and what is in the middle of it.
static func summary(facts: Dictionary) -> String:
    var camera: Dictionary = facts["camera"] as Dictionary
    var scene: Dictionary = facts["scene"] as Dictionary
    var centre: String = "nothing of the terrain's own"
    var batches: Array = facts["in_frame"] as Array
    if not batches.is_empty():
        var first: Dictionary = batches[0] as Dictionary
        centre = "%s %.0f m away, %.0f deg off centre" % [
            first["mesh"], first["nearest_m"], first["off_centre_deg"]
        ]
    return "%s, standing %.1f m above %s at %s, looking %s with %s in frame" % [
        scene["map"], camera["above_ground_m"], facts["surface_under_camera"],
        _place(facts), camera["bearing"], centre,
    ]


## Everything the sidecar holds.
static func _facts(context: Dictionary) -> Dictionary:
    var camera: Camera3D = context["camera"] as Camera3D
    var viewport: Viewport = context["viewport"] as Viewport
    var terrain: RorTerrain = context.get("terrain") as RorTerrain
    var at: Vector3 = camera.global_position
    var forward: Vector3 = -camera.global_transform.basis.z
    var ground: float = _ground_at(terrain, at.x, at.z)
    var facts: Dictionary = {
        "taken_at": Time.get_datetime_string_from_system(true, true),
        "commit": _commit(),
        "scene": _scene(context, terrain),
        "camera": {
            "position": _xyz(at),
            "ground_height_m": snappedf(ground, 0.01),
            "above_ground_m": snappedf(at.y - ground, 0.01),
            "bearing": _bearing(forward),
            "bearing_deg": snappedf(_bearing_degrees(forward), 0.1),
            "pitch_deg": snappedf(rad_to_deg(asin(clampf(forward.y, -1.0, 1.0))), 0.1),
            "forward": _xyz(forward),
            "fov_deg": snappedf(camera.fov, 0.1),
            "far_m": snappedf(camera.far, 0.1),
            "mode": context.get("mode", "") as String,
        },
        "looking_at": _looking_at(terrain, at, forward),
        "surface_under_camera": _surface(terrain, at),
        "in_frame": _batches(context["world"] as Node3D, camera),
        "vehicle": _vehicle(context, at),
        "render": _render(viewport),
    }
    facts["summary"] = summary(facts)
    return facts


## The map, by the name it was asked for and the name it calls itself.
static func _scene(context: Dictionary, terrain: RorTerrain) -> Dictionary:
    var out: Dictionary = {
        "map": context.get("map", "") as String,
        "weather": context.get("weather", "") as String,
    }
    if terrain == null:
        out["title"] = "no terrain: the blockout plane"
        return out
    out["title"] = terrain.name
    out["span_m"] = [
        snappedf(terrain.geometry["world_x"] as float, 0.1),
        snappedf(terrain.geometry["world_z"] as float, 0.1),
    ]
    out["start_position"] = _xyz(terrain.start_position())
    return out


## Where the view ray meets the ground, by marching it until it passes below the terrain.
##
## Marched rather than raycast because a terrain's scenery is not in Godot's physics world at all —
## it is static boxes in the solver — so a `PhysicsRayQueryParameters3D` would sail through every
## building on the map and report the floor behind it.
static func _looking_at(terrain: RorTerrain, at: Vector3, forward: Vector3) -> Dictionary:
    var travelled: float = 0.0
    while travelled < RAY_LENGTH_M:
        travelled += RAY_STEP_M
        var point: Vector3 = at + forward * travelled
        if point.y <= _ground_at(terrain, point.x, point.z):
            return {
                "ground_point": _xyz(point),
                "ground_distance_m": snappedf(travelled, 0.1),
                "surface": _surface(terrain, point),
            }
    return {
        "ground_point": null,
        "ground_distance_m": null,
        "surface": "the view ray does not meet the ground inside %.0f m" % RAY_LENGTH_M,
    }


## Every object batch with an instance in the frustum: what it is, how many, how near, and how far
## off the middle of the frame its nearest instance sits.
##
## Sorted by how central it is, because the thing somebody is reporting is the thing they are
## looking at. Grouped by the mesh resource, and named from the `mesh_file` the loader wrote on
## the node: one mesh is one batch per tile, so a map holds several siblings with the same name
## and Godot renames the duplicates. Read off `name`, La Paz's poles came back as
## `@MultiMeshInstance3D@3`.
static func _batches(world: Node3D, camera: Camera3D) -> Array:
    var groups: Dictionary = {}
    var stack: Array[Node] = [world]
    while not stack.is_empty():
        var node: Node = stack.pop_back()
        for child: Node in node.get_children():
            stack.append(child)
        var batch: MultiMeshInstance3D = node as MultiMeshInstance3D
        if batch == null or batch.multimesh == null or batch.multimesh.mesh == null:
            continue
        var key: int = batch.multimesh.mesh.get_instance_id()
        var seen: Dictionary = groups.get(key, {}) as Dictionary
        if seen.is_empty():
            seen = {"mesh": _mesh_name(batch), "in_frame": 0, "nearest_m": INF,
                    "off_centre_deg": 180.0}
            groups[key] = seen
        _measure(batch, camera, seen)
    var out: Array = []
    for key: int in groups.keys():
        var group: Dictionary = groups[key] as Dictionary
        if (group["in_frame"] as int) == 0:
            continue
        group["nearest_m"] = snappedf(group["nearest_m"] as float, 0.1)
        group["off_centre_deg"] = snappedf(group["off_centre_deg"] as float, 0.1)
        out.append(group)
    out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
        return (a["off_centre_deg"] as float) < (b["off_centre_deg"] as float)
    )
    return out.slice(0, LISTED_BATCHES)


## What file a batch was built from. The loader writes it on the node; vegetation and anything
## else that did not leaves its node name, which is the best there is.
static func _mesh_name(batch: MultiMeshInstance3D) -> String:
    if batch.has_meta("mesh_file"):
        return batch.get_meta("mesh_file") as String
    return String(batch.name)


## Folds one batch's visible instances into its group's tally.
static func _measure(batch: MultiMeshInstance3D, camera: Camera3D, into: Dictionary) -> void:
    var frame: Transform3D = batch.global_transform
    var eye: Vector3 = camera.global_position
    var forward: Vector3 = -camera.global_transform.basis.z
    for index: int in batch.multimesh.instance_count:
        var where: Vector3 = (frame * batch.multimesh.get_instance_transform(index)).origin
        if not camera.is_position_in_frustum(where):
            continue
        into["in_frame"] = (into["in_frame"] as int) + 1
        var away: float = eye.distance_to(where)
        var off: float = rad_to_deg(forward.angle_to(where - eye))
        if away < (into["nearest_m"] as float):
            into["nearest_m"] = away
            into["off_centre_deg"] = off


## The vehicle, where it is and how fast, and how far the camera is from it.
static func _vehicle(context: Dictionary, at: Vector3) -> Variant:
    var drive: PlayDrive = context.get("drive") as PlayDrive
    if drive == null:
        return null
    var root: Node3D = drive.vehicle_root()
    var where: Vector3 = at if root == null else root.global_position
    return {
        "name": context.get("vehicle", "") as String,
        "position": _xyz(where),
        "camera_distance_m": snappedf(at.distance_to(where), 0.1),
        "hud": drive.hud_line(),
    }


## What the frame cost, from the same frame that was written.
static func _render(viewport: Viewport) -> Dictionary:
    var rid: RID = viewport.get_viewport_rid()
    var size: Vector2 = viewport.get_visible_rect().size
    return {
        "resolution": [int(size.x), int(size.y)],
        "fps": snappedf(Performance.get_monitor(Performance.TIME_FPS), 0.1),
        "frame_ms": snappedf(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, 0.01),
        "draw_calls": RenderingServer.viewport_get_render_info(
            rid, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE,
            RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME
        ),
        "primitives": RenderingServer.viewport_get_render_info(
            rid, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE,
            RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME
        ),
        "video_mb": snappedf(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)
            / 1048576.0, 0.1),
    }


## Where this is on the map, said the way a person would: a position and a share of the span.
static func _place(facts: Dictionary) -> String:
    var camera: Dictionary = facts["camera"] as Dictionary
    var at: Array = camera["position"] as Array
    var scene: Dictionary = facts["scene"] as Dictionary
    if not scene.has("span_m"):
        return "(%.0f, %.0f)" % [at[0], at[2]]
    var span: Array = scene["span_m"] as Array
    return "(%.0f, %.0f), %.0f%% across and %.0f%% along a %.0f by %.0f m map" % [
        at[0], at[2],
        100.0 * (at[0] as float) / maxf(span[0] as float, 1.0),
        100.0 * (at[2] as float) / maxf(span[1] as float, 1.0),
        span[0], span[1],
    ]


## The ground height at a world position, or zero where there is no terrain.
static func _ground_at(terrain: RorTerrain, x: float, z: float) -> float:
    return 0.0 if terrain == null else terrain.height_at_world(x, z)


## What the ground is made of underfoot, by the terrain's own ground model.
static func _surface(terrain: RorTerrain, at: Vector3) -> String:
    if terrain == null:
        return "the blockout plane"
    return terrain.ground_models().name_of(terrain.surface_at_world(at.x, at.z))


## Which way the camera faces, as a compass point. North is -Z, which is where a Godot camera
## looks with no rotation.
static func _bearing(forward: Vector3) -> String:
    var degrees: float = _bearing_degrees(forward)
    return COMPASS[int(roundf(degrees / 45.0)) % COMPASS.size()]


static func _bearing_degrees(forward: Vector3) -> float:
    return fposmod(rad_to_deg(atan2(forward.x, -forward.z)), 360.0)


static func _xyz(at: Vector3) -> Array:
    return [snappedf(at.x, 0.01), snappedf(at.y, 0.01), snappedf(at.z, 0.01)]


## The commit this was taken on, read out of the repository rather than shelled out for.
static func _commit() -> String:
    var head: String = FileAccess.get_file_as_string(
        SourceScan.repo_root().path_join(".git/HEAD")
    ).strip_edges()
    if head.begins_with("ref: "):
        head = FileAccess.get_file_as_string(
            SourceScan.repo_root().path_join(".git").path_join(head.substr(5))
        ).strip_edges()
    return head.substr(0, 12) if head.length() >= 12 else "unknown"
