class_name FlareSprite
extends RefCounted
## What a lamp is *seen* as: the sprite drawn in front of its glass when it is on.
##
## **Rigs of Rods ships the artwork for this and names it per lamp.** A `flares` row ends in a
## material, and where it does not — or where it says `default` — upstream picks one by what kind
## of lamp it is, in `ActorSpawner::AddBaseFlare`:
##
##     if (using_default_material)
##     {
##         if      (type == BRAKE_LIGHT)   material_name = "tracks/brakeflare";
##         else if (type == BLINKER_*)     material_name = "tracks/blinkflare";
##         else if (type == DASHBOARD)     material_name = "tracks/greenflare";
##         else if (type == TAIL_LIGHT)    material_name = "tracks/redflare";
##         else                            material_name = "tracks/flare";
##     }
##
## Those five materials are in the game's own resources and so are their textures: `flare.dds` is
## a white starburst with rays, `redflare.dds` a red one, `brakeflare.dds` a deeper red,
## `blinkflare.dds` amber and `greenflare.dds` green. A lamp drawn with them looks like a lamp.
## This project drew a generated radial blur instead and a session called it what it was — "a fake
## light orb" — while the artwork it should have been drawing was in the pinned checkout the
## whole time.
##
## The mod's own material wins where it names one: the hero truck asks for `tracks/redflare` on
## its rear lamps and the Mazda ships flare sprites of its own.

## Which of the game's flare materials a lamp gets when its row leaves the choice open.
const BY_TYPE: Dictionary = {
    FlareRows.BRAKE_LIGHT: "tracks/brakeflare",
    FlareRows.BLINKER_LEFT: "tracks/blinkflare",
    FlareRows.BLINKER_RIGHT: "tracks/blinkflare",
    FlareRows.DASHBOARD: "tracks/greenflare",
    FlareRows.TAIL_LIGHT: "tracks/redflare",
}
## And what every other kind of lamp gets.
const ANY_LAMP: String = "tracks/flare"
## The fallback sprite: how big the bright core is and how strong the halo around it, for a lamp
## whose material resolves to no texture at all.
const GLOW_TEXTURE_PX: int = 64
const GLOW_CORE: float = 0.45
const GLOW_HALO: float = 0.55

## The generated fallback sprite, built on first use and never changed after.
##
## The one `static var` D0 allows, and it is allowed because it is a memo and not state: it is
## derived from constants, it is written once, and no observable behaviour depends on whether it
## was built by this gate or an earlier one. `static_state` knows about it by name — an exemption
## a human granted for a stated reason, not a pattern the lint waves through.
##
## It does outlive a gate container, which means one texture stays allocated for the life of the
## process. That is bounded at one and deliberate: rebuilding a 64 px radial gradient per
## container would be slower and would prove nothing.
static var _glow_sprite: Texture2D = null


## Which material a lamp's sprite is drawn with, by upstream's rule.
static func material_of(flare: Dictionary) -> String:
    var material: String = flare.get("material", "") as String
    if not FlareRows.is_default_material(material):
        return material
    return BY_TYPE.get(flare["type"] as String, ANY_LAMP) as String


## The sprite texture for a lamp, or null when nothing the row names can be found.
##
## `scripts` is the pack's material declarations merged over the game's own, from
## `RorContentPath.materials`, so `tracks/flare` resolves for a mod that ships no flare artwork of
## its own and a mod that does gets its own.
static func texture(
    flare: Dictionary,
    mod_dir: String,
    dds_reader: RefCounted,
    cache: Dictionary,
    scripts: Dictionary
) -> Texture2D:
    if dds_reader == null:
        return null
    var declared: Dictionary = scripts.get(material_of(flare), {}) as Dictionary
    var files: PackedStringArray = declared.get("textures", PackedStringArray())
    if files.is_empty():
        return null
    return MeshAssembler.texture(
        RorContentPath.find(files[0], mod_dir), dds_reader, cache
    )


## The sprite every lens falls back to: white in the middle, fading to nothing at the edge.
##
## A radial falloff rather than a disc, because an additive disc has an edge and an edge is what
## makes a lamp look like a sticker.
static func fallback() -> Texture2D:
    if _glow_sprite != null:
        return _glow_sprite
    var image: Image = Image.create_empty(
        GLOW_TEXTURE_PX, GLOW_TEXTURE_PX, false, Image.FORMAT_RGBAF
    )
    var centre: float = float(GLOW_TEXTURE_PX - 1) * 0.5
    for y: int in GLOW_TEXTURE_PX:
        for x: int in GLOW_TEXTURE_PX:
            var away: float = Vector2(float(x) - centre, float(y) - centre).length() / centre
            # A bright core inside a wider halo, which is what a lamp at night looks like.
            var core: float = pow(clampf(1.0 - away / GLOW_CORE, 0.0, 1.0), 2.0)
            var halo: float = pow(clampf(1.0 - away, 0.0, 1.0), 3.0)
            var value: float = clampf(core + halo * GLOW_HALO, 0.0, 1.0)
            image.set_pixel(x, y, Color(value, value, value, value))
    if not image.is_compressed():
        image.generate_mipmaps()
    _glow_sprite = ImageTexture.create_from_image(image)
    return _glow_sprite
