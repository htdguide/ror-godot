extends GateBase
## A surface whose Ogre pass states its own fog is not buried in this project's.
##
## **Ogre's fog is a per-pass setting and Godot's belongs to the scene.** A Rigs of Rods terrain
## paints its distance twice: once as haze, and once as a backdrop — a horizon ring and a ground
## skirt, standing ten kilometres out, with the mountains and the dust already painted into the
## texture. Those passes say so in their own material: `fog_override true exp 0.71 0.81 0.87
## 0.00001 2000 3000` is a density of one part in a hundred thousand, which is 9.5% fog where
## they stand. This project's own haze is 0.0006, which is 99.8% at the same distance, and a
## surface at 99.8% fog is the fog colour and nothing else.
##
## **Reported from a window on La Paz**, in these words: "I can't see the sky with clouds on view
## distance 12000, it looks like there is a gray texture above me, and the more distance I set,
## the bigger is the gray thing; if I set 200 m view distance, I can't see it." Nothing was wrong
## with the sky. La Paz's horizon ring is 10,070 m out and 1,250 m tall, so it enters the frame
## only when the far plane passes about 7.3 km — and when it enters, it enters as a grey sheet
## standing between the camera and the sky.
##
## **Two claims, because either half alone passes while the map is wrong.** The first is that
## every pass in the library that states a clear fog of its own is built without the scene's: the
## oracle is the `.material` text, read here with no help from the parser under test. The second
## is that it shows — the horizon band of a frame taken from La Paz's own spawn at a view distance
## of 12 km has to vary more than the same band with the same surfaces buried again, which is the
## negative control and is measured in the same run.

## How far out a backdrop stands, for judging whether a pass's own fog would hide it. La Paz's
## horizon ring is at 10,070 m; this is the round number under it.
const REFERENCE_M: float = 10000.0
## What the camera can see when the fault shows. Below about 7.3 km the backdrop is clipped away
## and there is nothing to photograph.
const REACH_M: float = 12000.0
## The band of the frame the backdrop stands in, as a share of its height from the top.
const BAND_TOP: float = 0.3
const BAND_BOTTOM: float = 0.52
## How much more the band has to vary with the pass's own fog honoured than with it buried.
## Measured at 0.1735 against 0.0526, which is 3.3 times; half of that is the bound.
const MIN_RATIO: float = 2.0
## The map the photograph is taken on, because it is the one that reported this.
const PHOTOGRAPHED: String = "lapaz"
const CONVERGE: int = 6
const LISTED: int = 6


static func meta() -> Dictionary:
    return {
        "name": "a_backdrop_keeps_the_fog_its_material_states",
        "proves": (
            "every Ogre pass in the library that overrides fog with a clear one is read as"
            + " keeping it, the objects built from those materials are drawn without the scene's"
            + " distance haze, and the horizon backdrop they make is visible at a 12 km view"
            + " distance"
        ),
        "oracle": GateBase.ORACLE_EXTERNAL,
        "threshold": (
            "no material declaring a clear fog_override is built with fog, and the horizon band"
            + " varies at least twice as much as the same band with those passes buried"
        ),
        "why": (
            "Ogre states fog per pass and Godot states it per scene, so a horizon backdrop that"
            + " asks to be seen through ten kilometres is drawn at this project's 99.8% and"
            + " becomes a flat grey sheet between the camera and the sky. It appears only when"
            + " the far plane reaches it, which is why it read as a fault in the sky."
        ),
        "budget_s": 240.0,
        "needs_gpu": true,
        "milestone": "C2",
    }


func run(harness: Node) -> Dictionary:
    var declared: Dictionary = _declared()
    var problems: PackedStringArray = PackedStringArray()
    var checked: int = 0
    for path: String in declared.keys():
        var parsed: Dictionary = OgreMaterial.read(path)
        for name: String in declared[path] as PackedStringArray:
            checked += 1
            var material: Dictionary = parsed.get(name, {}) as Dictionary
            if material.is_empty():
                problems.append("%s: %s is declared and the reader did not return it"
                    % [path.get_file(), name])
            elif not (material.get("no_fog", false) as bool):
                problems.append("%s: %s states a clear fog_override and is built with fog"
                    % [path.get_file(), name])
    if problems.size() > 0:
        return fail(
            "%d of %d passes lose the fog setting their own material states: %s"
            % [problems.size(), checked, "; ".join(problems.slice(0, LISTED))],
            problems.size()
        )

    var shown: Dictionary = await _photograph(harness)
    if (shown["error"] as String) != "":
        return fail(shown["error"] as String)
    var honoured: float = shown["honoured"] as float
    var buried: float = shown["buried"] as float
    if honoured < buried * MIN_RATIO:
        return fail(
            "%s's horizon band varies %.4f with its own fog honoured and %.4f with it buried,"
            % [PHOTOGRAPHED, honoured, buried]
            + " which is %.1f times and not the %.1f required: the backdrop is still a flat sheet"
            % [honoured / maxf(buried, 0.0001), MIN_RATIO],
            honoured
        )
    return ok(
        "%d passes state a clear fog of their own and keep it; %s's horizon band varies %.4f"
        % [checked, PHOTOGRAPHED, honoured]
        + " at a %.0f m view distance against %.4f with the same surfaces buried"
        % [REACH_M, buried],
        checked
    )


## The horizon band of a frame from the reporting map's own spawn, with the backdrop's fog
## setting honoured and with it buried. Returns `{"error", "honoured", "buried"}`.
func _photograph(harness: Node) -> Dictionary:
    var out: Dictionary = {"error": "", "honoured": 0.0, "buried": 0.0}
    var loaded: Dictionary = RorTerrainLibrary.load_named(PHOTOGRAPHED)
    if (loaded.get("error", "") as String) != "":
        out["error"] = loaded["error"] as String
        return out
    var terrain: RorTerrain = loaded["terrain"] as RorTerrain
    var error: String = harness.setup_for("hero_3q")
    if error != "":
        out["error"] = error
        return out
    var objects: Node3D = RorObjects.build(terrain)
    harness.world.add_child(objects)
    var unfogged: Array[StandardMaterial3D] = _unfogged(objects)
    if unfogged.is_empty():
        out["error"] = "%s builds no surface that states a fog of its own" % PHOTOGRAPHED
        return out
    harness.camera.far = REACH_M
    # Standing at the spawn looking level along the map, which is where the backdrop stands.
    var at: Vector3 = terrain.start_position() + Vector3(0.0, 2.0, 0.0)
    harness.camera.look_at_from_position(at, at + Vector3(1.0, 0.0, 0.0), Vector3.UP)
    for keep: bool in [true, false]:
        for material: StandardMaterial3D in unfogged:
            material.disable_fog = keep
        var shot: Dictionary = await harness.capture_shot(
            "backdrop/%s" % ("honoured" if keep else "buried"), "static", CONVERGE
        )
        if (shot["error"] as String) != "":
            out["error"] = shot["error"] as String
            return out
        out["honoured" if keep else "buried"] = _spread(shot["png"] as String)
    harness.world.remove_child(objects)
    objects.queue_free()
    return out


## Every material of a built scene that asked to keep its own fog.
func _unfogged(root: Node) -> Array[StandardMaterial3D]:
    var out: Array[StandardMaterial3D] = []
    for node: Node in root.get_children():
        for found: StandardMaterial3D in _unfogged(node):
            if not out.has(found):
                out.append(found)
        var mesh: Mesh = _mesh_of(node)
        if mesh == null:
            continue
        for surface: int in mesh.get_surface_count():
            var material: StandardMaterial3D = (
                mesh.surface_get_material(surface) as StandardMaterial3D
            )
            if material != null and material.disable_fog and not out.has(material):
                out.append(material)
    return out


static func _mesh_of(node: Node) -> Mesh:
    if node is MultiMeshInstance3D:
        var multimesh: MultiMesh = (node as MultiMeshInstance3D).multimesh
        return null if multimesh == null else multimesh.mesh
    if node is MeshInstance3D:
        return (node as MeshInstance3D).mesh
    return null


## How much the horizon band of a frame varies, as the standard deviation of pixel luminance.
## A band drowned in fog is one colour and reads near zero; a painted horizon reads far above it.
func _spread(png: String) -> float:
    var image: Image = Image.load_from_file(png)
    if image == null:
        return 0.0
    var values: PackedFloat32Array = PackedFloat32Array()
    var total: float = 0.0
    for y: int in range(int(image.get_height() * BAND_TOP), int(image.get_height() * BAND_BOTTOM), 2):
        for x: int in range(0, image.get_width(), 4):
            var pixel: Color = image.get_pixel(x, y)
            var luma: float = pixel.r * 0.2126 + pixel.g * 0.7152 + pixel.b * 0.0722
            values.append(luma)
            total += luma
    if values.is_empty():
        return 0.0
    var mean: float = total / float(values.size())
    var sum: float = 0.0
    for value: float in values:
        sum += (value - mean) * (value - mean)
    return sqrt(sum / float(values.size()))


## Which materials in the library state a fog of their own that leaves them visible, as
## path -> names. The oracle: the `.material` text, walked here rather than asked of the reader.
func _declared() -> Dictionary:
    var out: Dictionary = {}
    var files: PackedStringArray = PackedStringArray()
    _collect(SourceScan.repo_root().path_join("assets"), files)
    for path: String in files:
        var names: PackedStringArray = PackedStringArray()
        var current: String = ""
        for raw: String in RorText.read(path).split("\n"):
            var line: String = RorText.strip_comment(raw)
            if line.to_lower().begins_with("material "):
                current = line.substr(9).get_slice(":", 0).strip_edges()
                continue
            var words: PackedStringArray = line.replace("\t", " ").split(" ", false)
            if words.size() < 2 or words[0].to_lower() != "fog_override":
                continue
            if words[1].to_lower() != "true" or current == "":
                continue
            # `fog_override true` with nothing after it is Ogre's "no fog on this pass"; a type
            # of `none` says the same outright. A stated curve is read for its density.
            if words.size() == 2 or words[2].to_lower() == "none":
                if not names.has(current):
                    names.append(current)
                continue
            if _clear(words) and not names.has(current):
                names.append(current)
        if names.size() > 0:
            out[path] = names
    return out


## Whether a stated fog curve leaves a surface at `REFERENCE_M` visible.
func _clear(words: PackedStringArray) -> bool:
    var numbers: PackedFloat32Array = PackedFloat32Array()
    for at: int in range(3, words.size()):
        if words[at].is_valid_float():
            numbers.append(words[at].to_float())
    if words[2].to_lower() == "linear":
        return numbers.size() < 2 or numbers[numbers.size() - 1] >= REFERENCE_M
    for at: int in range(mini(3, numbers.size()), numbers.size()):
        if numbers[at] > 0.0 and numbers[at] < 1.0:
            return 1.0 - exp(-numbers[at] * REFERENCE_M) < 0.5
    return true


func _collect(directory: String, into: PackedStringArray) -> void:
    for file: String in DirAccess.get_files_at(directory):
        if file.get_extension().to_lower() == "material":
            into.append(directory.path_join(file))
    for child: String in DirAccess.get_directories_at(directory):
        _collect(directory.path_join(child), into)
