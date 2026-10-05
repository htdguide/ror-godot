extends GateBase
## A lamp bound to one of the vehicle's own materials lights that material's glass, not just the
## sprite in front of it.
##
## `materialflarebindings` ties a flare to a material the vehicle is built from, and Rigs of Rods
## switches that material's texture between two authored frames when the lamp goes on — frame 0
## the dark glass, frame 1 the same glass alight. The Mazda 626 ships both:
## `mazda626gf-sd-lights_0.dds` is its unlit headlamp, brake lenses and instrument cluster, and
## `_1.dds` is all three lit.
##
## A session looking at the hero truck asked for exactly this: "how the actual headlights look
## when they are on — now they don't change at all, we just put a fake light orb on them".
##
## **The sprites are taken away before the picture is taken.** A lamp's sprite stands in front of
## its glass and would brighten the same pixels, so measuring with it there proves nothing about
## the glass. What is measured is the vehicle's own surface, with the lamp switched on and off.

const MOD_DIR: String = "assets/mods/mazda626gf"
const CAR: String = "mazda626sd18i-mt.car"
const PRESET: String = "hero_3q"
const WEATHER: String = "golden_dusk"
const CONVERGE: int = 3
## How far in front of the vehicle the picture is taken from.
const VIEW_M: float = 5.0
## How far a pixel of the glass has to move when the lamp is switched on, and how bright the lit
## glass has to end up. A tenth of the range is a change a person sees across a lamp; the lit
## level is the same one `a_lit_lamp_shows_its_lens` holds a sprite to.
const MIN_CHANGE: float = 0.10
const MIN_LIT_LUMA: float = 0.30


static func meta() -> Dictionary:
    return {
        "name": "a_bound_lamp_lights_its_own_glass",
        "proves": "a flare bound to one of the vehicle's own materials switches that material to its lit frame, so the lamp's glass looks different when the lamp is on",
        "builds_on": ["a_lit_lamp_shows_its_lens"],
        "oracle": GateBase.ORACLE_INVARIANT,
        "threshold": (
            "a bound lamp's glass moving %.2f and reaching %.2f display luma with the lamp's"
            % [MIN_CHANGE, MIN_LIT_LUMA] + " own sprite and bulb removed"
        ),
        "why": (
            "a session reported that a lamp never changes how it looks, only gaining a glow in"
            + " front of it. Upstream lights the glass by switching the material's texture frame,"
            + " and the artwork for it ships with the mod. Measured with the sprite removed,"
            + " because the sprite covers the same pixels."
        ),
        "budget_s": 120.0,
        "needs_gpu": true,
        "milestone": "M1",
    }


func run(harness: Node) -> Dictionary:
    var mod_dir: String = SourceScan.repo_root().path_join(MOD_DIR)
    if not FileAccess.file_exists(mod_dir.path_join(CAR)):
        return ok("skipped: %s is not present" % CAR, 0)
    var err: String = harness.setup_for(PRESET, WEATHER)
    if err != "":
        return fail(err)
    clear_fog(harness)
    var built: Dictionary = VehicleBuilder.build(mod_dir, CAR)
    if (built.get("error", "") as String) != "":
        return fail(built["error"] as String)
    var truck: TruckParser = built["truck"] as TruckParser
    var root: Node3D = built["root"] as Node3D
    harness.world.add_child(root)
    var lamps: Array[Node3D] = built["lamps"] as Array[Node3D]
    if truck.material_flares.is_empty():
        return fail("%s declares no materialflarebindings, so there is nothing to bind" % CAR)
    if int(built.get("lit_lenses", 0)) == 0:
        return fail(
            "%s binds %d material(s) to its lamps and none of them was found on the vehicle"
            % [CAR, truck.material_flares.size()], 0
        )

    var glass: Array[MeshInstance3D] = _drawn_with(root, truck.material_flares.keys())
    if glass.is_empty():
        return fail("no surface on the vehicle is drawn with a bound material")
    # **Everything a lamp does except change its own glass is taken away.** The sprite stands in
    # front of the glass and the bulb lights the bodywork around it, and both move the same
    # pixels; with them gone the only thing left that can change the picture is the material.
    for lamp: Node3D in lamps:
        for child: Node in lamp.get_children():
            lamp.remove_child(child)
            child.queue_free()

    # Square on to the front of the vehicle, which is the end a bound lamp is on for everything in
    # this library.
    harness.camera.look_at_from_position(
        root.global_position - root.global_transform.basis.z * VIEW_M + Vector3(0.0, 1.0, 0.0),
        root.global_position + Vector3(0.0, 0.6, 0.0),
        Vector3.UP
    )
    await harness.advance_frames(1, "static", "glass")

    FlareBuilder.apply_state(lamps, truck, {})
    var dark: Dictionary = await _capture(harness, "dark")
    if (dark["error"] as String) != "":
        return fail(dark["error"] as String)
    FlareBuilder.apply_state(lamps, truck, {"headlights": true})
    var lit: Dictionary = await _capture(harness, "lit")
    if (lit["error"] as String) != "":
        return fail(lit["error"] as String)

    # **Whatever changed in this frame is the glass.** The lamps have no sprite and no bulb left,
    # so the only thing in the scene that the switch can still reach is the material the vehicle
    # bound to it. That makes the whole picture the measurement and spares it a guess about where
    # on the screen a skinned panel ended up.
    var found: Dictionary = _biggest_change(dark["image"] as Image, lit["image"] as Image)
    var changed: float = found["changed"] as float
    if changed < MIN_CHANGE:
        return fail(
            "%d surface(s) bound to a lamp and the picture is the same with it on: the most any"
            % glass.size()
            + " pixel moved is %.3f, under %.2f. See %s" % [changed, MIN_CHANGE, lit["png"]],
            changed
        )
    if (found["lit"] as float) <= (found["dark"] as float):
        return fail(
            "the glass changes with the lamp on but gets darker: %.3f to %.3f at %s. See %s"
            % [found["dark"], found["lit"], str(found["at"]), lit["png"]], changed
        )
    if (found["lit"] as float) < MIN_LIT_LUMA:
        return fail(
            "the lit glass reaches only %.3f display luma, under %.2f. See %s"
            % [found["lit"], MIN_LIT_LUMA, lit["png"]], changed
        )
    return ok(
        "%d bound surface(s): the glass moves %.3f at %s, %.3f to %.3f display luma"
        % [glass.size(), changed, str(found["at"]), found["dark"], found["lit"]], changed
    )


## The pixel that moved most between the two frames, and how bright it is in each.
func _biggest_change(dark: Image, lit: Image) -> Dictionary:
    var size: Vector2i = dark.get_size()
    var best: Dictionary = {"changed": 0.0, "dark": 0.0, "lit": 0.0, "at": Vector2i.ZERO}
    for y: int in size.y:
        for x: int in size.x:
            var before: Color = dark.get_pixel(x, y)
            var after: Color = lit.get_pixel(x, y)
            var moved: float = maxf(
                absf(after.r - before.r),
                maxf(absf(after.g - before.g), absf(after.b - before.b))
            )
            if moved > (best["changed"] as float):
                best = {
                    "changed": moved,
                    "dark": _luma(before),
                    "lit": _luma(after),
                    "at": Vector2i(x, y),
                }
    return best


## Every surface the vehicle draws with one of the bound materials.
func _drawn_with(root: Node3D, names: Array) -> Array[MeshInstance3D]:
    var out: Array[MeshInstance3D] = []
    for node: Node in _descendants(root):
        var instance: MeshInstance3D = node as MeshInstance3D
        if instance == null or instance.mesh == null:
            continue
        for surface: int in instance.mesh.get_surface_count():
            var material: BaseMaterial3D = (
                instance.get_active_material(surface) as BaseMaterial3D
            )
            if material == null:
                continue
            if names.has(str(material.get_meta("ogre_material", ""))) and not out.has(instance):
                out.append(instance)
    return out


func _descendants(node: Node) -> Array[Node]:
    var out: Array[Node] = [node]
    for child: Node in node.get_children():
        out.append_array(_descendants(child))
    return out


func _luma(colour: Color) -> float:
    return colour.r * 0.2126 + colour.g * 0.7152 + colour.b * 0.0722


func _capture(harness: Node, tag: String) -> Dictionary:
    var shot: Dictionary = await harness.capture_shot("glass/%s" % tag, "static", CONVERGE)
    if (shot["error"] as String) != "":
        return {"error": shot["error"] as String, "image": null, "png": ""}
    var image: Image = Image.load_from_file(shot["png"] as String)
    if image == null:
        return {
            "error": "the capture at %s could not be read" % shot["png"],
            "image": null, "png": shot["png"],
        }
    return {"error": "", "image": image, "png": shot["png"]}


