extends GateBase
## Every lamp is drawn with the artwork Rigs of Rods names for it, not with a generated blur.
##
## A `flares` row ends in a material. Where it names one — the hero truck asks for
## `tracks/redflare` on its rear lamps — that is the sprite. Where it says `default`, or says
## nothing, upstream picks by what kind of lamp it is: `tracks/brakeflare` for a brake light,
## `tracks/blinkflare` for an indicator, `tracks/greenflare` for a dashboard lamp,
## `tracks/redflare` for a tail light and `tracks/flare` for everything else.
##
## All five live in the game's own resources with their textures, and this project drew a
## generated radial gradient instead for every lamp on every vehicle. A session looked at it and
## called it "a fake light orb".
##
## The claim is that each lamp resolved to the game's artwork, and to the right piece of it.

const MOD_DIR: String = "assets/mods/ChevyS1023"
const TRUCK: String = "S10offroad.truck"
## What each lamp of the hero truck should resolve to, by flare index, and the size of the
## texture behind it. The front pair name no material and are headlights; the rear pair are `f`
## rows carrying `tracks/redflare`, which upstream reads as tail lights; the indicators,
## brake and reversing lamps name nothing and are chosen by type.
const EXPECTED: Dictionary = {
    "f": "tracks/flare",
    "t": "tracks/redflare",
    "b": "tracks/brakeflare",
    "l": "tracks/blinkflare",
    "r": "tracks/blinkflare",
    "R": "tracks/flare",
}
## The sprite is artwork off disk, so it has the size the file has. The generated fallback is
## 64 px square and so is `redflare.dds`, so size alone cannot tell them apart — the texture is
## compared against the fallback object instead, and this is the second, cheaper check.
const MIN_SPRITE_PX: int = 32


static func meta() -> Dictionary:
    return {
        "name": "a_lamp_draws_the_sprite_its_file_names",
        "proves": "every lamp on a vehicle is drawn with the flare artwork its file names, or the one upstream picks for its type, rather than with a generated sprite",
        "builds_on": ["lights_follow_the_controls"],
        "oracle": GateBase.ORACLE_INVARIANT,
        "threshold": "every lamp resolving to the material upstream picks for it, and none falling back to the generated sprite",
        "why": (
            "Rigs of Rods ships five flare textures and names one per lamp type in"
            + " ActorSpawner::AddBaseFlare. This project generated a radial gradient for every"
            + " lamp instead, which a session reported as a fake light orb, while the artwork sat"
            + " unread in the pinned checkout."
        ),
        "budget_s": 60.0,
        "needs_gpu": true,
        "milestone": "M1",
    }


func run(harness: Node) -> Dictionary:
    var mod_dir: String = SourceScan.repo_root().path_join(MOD_DIR)
    if not DirAccess.dir_exists_absolute(mod_dir):
        return ok("skipped: hero asset not present at %s" % MOD_DIR, 0)
    var err: String = harness.setup_for("hero_3q")
    if err != "":
        return fail(err)
    var built: Dictionary = VehicleBuilder.build(mod_dir, TRUCK)
    if (built.get("error", "") as String) != "":
        return fail(built["error"] as String)
    var truck: TruckParser = built["truck"] as TruckParser
    harness.world.add_child(built["root"] as Node3D)
    var lamps: Array[Node3D] = built["lamps"] as Array[Node3D]
    if lamps.is_empty():
        return fail("%s built no lamps: there is nothing to draw" % TRUCK)

    var dds_reader: RefCounted = ClassDB.instantiate("DdsReader") as RefCounted
    var scripts: Dictionary = RorContentPath.materials(mod_dir)
    var textures: Dictionary = {}
    var fallback: Texture2D = FlareSprite.fallback()
    var counted: Dictionary = {}
    for index: int in truck.flares.size():
        var flare: Dictionary = truck.flares[index]
        var type: String = flare["type"] as String
        # A row that names its own sprite gets it; one that leaves the choice open gets the
        # material upstream picks for its type.
        var named: String = flare["material"] as String
        var wanted: String = (
            EXPECTED.get(type, "") as String if FlareRows.is_default_material(named) else named
        )
        var chosen: String = FlareSprite.material_of(flare)
        if wanted != "" and chosen != wanted:
            return fail(
                "lamp %d is type '%s' with material '%s', so it should draw '%s' and draws '%s'"
                % [index, type, flare["material"], wanted, chosen], index
            )
        var sprite: Texture2D = FlareSprite.texture(
            flare, mod_dir, dds_reader, textures, scripts
        )
        if sprite == null:
            return fail(
                "lamp %d (type '%s') resolves to material '%s', which has no texture: it would"
                % [index, type, chosen] + " fall back to the generated sprite", index
            )
        if sprite == fallback:
            return fail("lamp %d (type '%s') drew the generated sprite" % [index, type], index)
        if mini(sprite.get_width(), sprite.get_height()) < MIN_SPRITE_PX:
            return fail(
                "lamp %d draws '%s' at %dx%d, which is too small to be the artwork"
                % [index, chosen, sprite.get_width(), sprite.get_height()], index
            )
        counted[chosen] = int(counted.get(chosen, 0)) + 1

    # And the lamp that is drawn is the one that was built: a sprite resolved here and a
    # different texture hung on the vehicle would pass everything above.
    for index: int in mini(lamps.size(), truck.flares.size()):
        var lens: MeshInstance3D = lamps[index].get_node_or_null(^"Lens") as MeshInstance3D
        if lens == null:
            continue
        var material: StandardMaterial3D = lens.material_override as StandardMaterial3D
        if material == null or material.albedo_texture == null:
            return fail("lamp %d has no sprite on it at all" % index, index)
        if material.albedo_texture == fallback:
            return fail(
                "lamp %d was built with the generated sprite, not with %s"
                % [index, FlareSprite.material_of(truck.flares[index])], index
            )
    var reported: PackedStringArray = PackedStringArray()
    for name: String in counted.keys():
        reported.append("%s x%d" % [name, counted[name]])
    return ok("%d lamps: %s" % [truck.flares.size(), ", ".join(reported)], truck.flares.size())
