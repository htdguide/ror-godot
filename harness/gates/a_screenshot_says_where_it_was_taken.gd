extends GateBase
## A screenshot's sidecar names the object in the middle of the frame.
##
## **Why this is worth a gate.** The sidecar exists so that "that house has no texture" can be
## acted on without a round trip, and a sidecar that names the wrong house is worse than none: it
## sends the next hour's work to the wrong mesh. Three faults this week arrived as a picture of an
## untextured surface, and every one of them cost a round trip to establish which surface. Metadata
## that is trusted has to be checked.
##
## **The oracle is the terrain's own object files.** The gate loads a shipped terrain, builds its
## scenery, picks the batch holding the most instances, aims the camera at one of them, and
## requires the sidecar to name *that* mesh as the most central thing in frame. Which mesh that is
## comes out of La Paz's object list at run time; nothing here is a name this project wrote down.
##
## The ground figures are checked the same way: the camera's height above ground and the surface
## under it are compared against the terrain's own heightmap and ground model, not against a
## number recorded from an earlier run.

## The terrain to photograph: the one Rigs of Rods itself ships, so this runs on a fresh clone.
const TERRAIN_DIR: String = "assets/terrains/lapaz2"
const PRESET: String = "hero_3q"
## Where the camera stands relative to the object it is aimed at.
const BACK_OFF_M: float = 40.0
const EYE_HEIGHT_M: float = 3.0
## How central the aimed-at mesh has to be. Aiming at an instance's own origin puts it at zero;
## this is slack for a second mesh belonging to the same object standing in the same place.
const MAX_OFF_CENTRE_DEG: float = 2.0
## How closely the sidecar's ground figures have to match the terrain's own.
const GROUND_TOLERANCE_M: float = 0.05


## **It builds on nothing.** `builds_on` means "running this exercises that, at least as
## hard", and the graph stops running what it implies — so an edge that only records which
## gate came first is an edge that silently retires a gate. This one aims a camera at one batch and checks none of the counts a placement gate checks.


static func meta() -> Dictionary:
    return {
        "name": "a_screenshot_says_where_it_was_taken",
        "proves": "the sidecar written beside a session screenshot names the object the camera is pointed at, and its ground figures match the terrain's own files",
        "oracle": GateBase.ORACLE_EXTERNAL,
        "threshold": (
            "the aimed-at mesh is the most central thing in frame, within %.0f degrees, and the"
            % MAX_OFF_CENTRE_DEG
            + " camera's height above ground matches the heightmap within %.0f mm"
            % (GROUND_TOLERANCE_M * 1000.0)
        ),
        "why": (
            "the sidecar exists so a reported fault can be acted on without a round trip, and one"
            + " that names the wrong mesh sends the next hour of work to the wrong place."
            + " Metadata that is trusted has to be checked."
        ),
        "budget_s": 180.0,
        "needs_gpu": true,
        "milestone": "C1",
    }


func run(harness: Node) -> Dictionary:
    var directory: String = SourceScan.repo_root().path_join(TERRAIN_DIR)
    if not DirAccess.dir_exists_absolute(directory):
        return ok("skipped: no terrain at %s" % TERRAIN_DIR, 0)
    var error: String = harness.setup_for(PRESET)
    if error != "":
        return fail(error)
    var loaded: Dictionary = RorTerrain.load_from(directory)
    if (loaded["error"] as String) != "":
        return fail(loaded["error"] as String)
    var terrain: RorTerrain = loaded["terrain"] as RorTerrain

    var objects: Node3D = RorObjects.build(terrain)
    harness.world.add_child(objects)
    var wanted: String = _most_placed_mesh(terrain)
    if wanted == "":
        return fail("the terrain's object files name no mesh to aim at")
    var aim: Dictionary = _instance_of(objects, wanted)
    if aim.is_empty():
        return fail("the terrain lists %s and built no batch for it" % wanted)

    # Stood off along +X so the camera looks back along -X, which is a bearing the sidecar has to
    # work out rather than read off a rotation this gate set.
    var target: Vector3 = aim["at"] as Vector3
    var eye: Vector3 = target + Vector3(BACK_OFF_M, EYE_HEIGHT_M, 0.0)
    harness.camera.look_at_from_position(eye, target, Vector3.UP)
    await harness.advance_frames(2, "static", "shot")

    var path: String = HarnessCapture.resolve_dir("gates").path_join("play_shot_gate.png")
    error = PlayShot.save(path, {
        "viewport": harness.camera.get_viewport(),
        "camera": harness.camera,
        "world": harness.world,
        "terrain": terrain,
        "map": terrain.cache_name(),
        "vehicle": "",
        "weather": PRESET,
        "mode": "GATE",
        "drive": null,
    })
    if error != "":
        return fail(error)
    var sidecar: String = path.get_basename() + ".json"
    var facts: Variant = JSON.parse_string(FileAccess.get_file_as_string(sidecar))
    if not (facts is Dictionary):
        return fail("the sidecar at %s is not readable JSON" % sidecar)
    return _judge(facts as Dictionary, terrain, aim, eye)


## What the sidecar has to get right about a frame whose contents are known.
func _judge(
    facts: Dictionary, terrain: RorTerrain, aim: Dictionary, eye: Vector3
) -> Dictionary:
    var in_frame: Array = facts["in_frame"] as Array
    if in_frame.is_empty():
        return fail(
            "the camera is %.0f m from %d instances of %s and the sidecar reports nothing in frame"
            % [BACK_OFF_M, aim["instances"], aim["mesh"]]
        )
    var first: Dictionary = in_frame[0] as Dictionary
    if (first["mesh"] as String) != (aim["mesh"] as String):
        return fail(
            "the camera is pointed at %s and the sidecar calls %s the most central thing in"
            % [aim["mesh"], first["mesh"]]
            + " frame, %.1f degrees off" % (first["off_centre_deg"] as float)
        )
    if (first["off_centre_deg"] as float) > MAX_OFF_CENTRE_DEG:
        return fail(
            "%s is dead centre and the sidecar puts it %.1f degrees off"
            % [aim["mesh"], first["off_centre_deg"]],
            first["off_centre_deg"]
        )

    var camera: Dictionary = facts["camera"] as Dictionary
    var ground: float = terrain.height_at_world(eye.x, eye.z)
    var above: float = camera["above_ground_m"] as float
    if absf(above - (eye.y - ground)) > GROUND_TOLERANCE_M:
        return fail(
            "the camera stands %.3f m above the heightmap and the sidecar says %.3f m"
            % [eye.y - ground, above],
            above
        )
    var surface: String = terrain.ground_models().name_of(
        terrain.surface_at_world(eye.x, eye.z)
    )
    if (facts["surface_under_camera"] as String) != surface:
        return fail(
            "the ground under the camera is %s and the sidecar says %s"
            % [surface, facts["surface_under_camera"]]
        )
    if (facts["looking_at"] as Dictionary)["ground_distance_m"] == null:
        return fail("the camera looks down at the ground and the sidecar found none")
    if (facts["commit"] as String) == "unknown":
        return fail("the sidecar could not say which commit the picture was taken on")
    return ok(
        "%d batches in frame, %s most central at %.1f degrees; %s"
        % [in_frame.size(), first["mesh"], first["off_centre_deg"], facts["summary"]],
        in_frame.size()
    )


## The mesh the terrain places more often than any other, read from its own files: the object
## list says which definition is placed most, and that definition's header says which mesh it is.
##
## Read from the content rather than from the scene, so what the sidecar is held to is a fact
## about La Paz and not a fact about this project's scene graph. The most-placed one is used
## because an object placed once may be the horizon card, which is 6 km wide and never central.
func _most_placed_mesh(terrain: RorTerrain) -> String:
    var counts: Dictionary = {}
    for placement: Dictionary in RorObjects.placements(terrain):
        var name: String = placement["name"] as String
        counts[name] = (counts.get(name, 0) as int) + 1
    var best: String = ""
    for name: String in counts.keys():
        if best == "" or (counts[name] as int) > (counts[best] as int):
            best = name
    if best == "":
        return ""
    var odef: Dictionary = Odef.read(terrain.directory.path_join("%s.odef" % best))
    var meshes: PackedStringArray = odef["meshes"] as PackedStringArray
    return "" if meshes.is_empty() else meshes[0]


## Where one instance of a named mesh stands in the built scene, and how many there are.
func _instance_of(objects: Node3D, mesh_file: String) -> Dictionary:
    var instances: int = 0
    var at: Vector3 = Vector3.ZERO
    for child: Node in objects.get_children():
        var batch: MultiMeshInstance3D = child as MultiMeshInstance3D
        if batch == null or batch.multimesh == null:
            continue
        if not batch.has_meta("mesh_file") or batch.get_meta("mesh_file") != mesh_file:
            continue
        if instances == 0 and batch.multimesh.instance_count > 0:
            at = batch.multimesh.get_instance_transform(0).origin
        instances += batch.multimesh.instance_count
    if instances == 0:
        return {}
    return {"mesh": mesh_file, "instances": instances, "at": at}
