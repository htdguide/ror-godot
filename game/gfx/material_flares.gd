class_name MaterialFlares
extends RefCounted
## The lamp's own glass, lit.
##
## A `flares` row draws a sprite in front of the bodywork. `materialflarebindings` does the other
## half: it names one of the vehicle's **own materials** and ties it to a flare, so that switching
## the lamp on changes how the lamp itself looks. Upstream, in `GfxActor::SetMaterialFlareOn`:
##
##     Ogre::TextureUnitState* tus = p->getTextureUnitState(0);
##     if (tus->getNumFrames() < 2) continue;
##     tus->setCurrentFrame(state_on ? 1 : 0);
##     p->setSelfIllumination(state_on ? entry.emissive_color : ColourValue::ZERO);
##
## So the artwork is authored twice and the lamp picks a frame. The Mazda 626 is the example this
## was built against: `mazda626gf-sd-lights_0.dds` is its dark headlamp glass, its unlit brake
## lenses and a black instrument cluster, and `_1.dds` is the same three alight — a white-hot
## reflector, red lenses, green dials. Four of its flares are bound to that one material.
##
## **A vehicle that declares no bindings keeps the lamps it had**, and most of the library does
## not declare them, the hero truck included. That is upstream's behaviour too: without a binding
## nothing in Rigs of Rods changes the glass either, and the lamp is the sprite in front of it.
##
## One departure, deliberate: the lit frame is also used as an emission map. Ogre's self
## illumination is the lamp's declared `emissive` and a mod that declares none — the Mazda does
## not — would hand back a lit headlamp that is only as bright as the night around it. The lit
## frame is already a picture of a lamp that is on, so what it paints bright is exactly what
## should glow, and nothing else on the sheet does.

## How hard a lit lens glows, and what colour it glows when its material declares none. The
## figure is the cab's own backlight level — a lamp and an instrument face are the same kind of
## thing and reading two different numbers for them is how they stop matching.
const EMISSION_ENERGY: float = CockpitCfg.BACKLIGHT_ON
const DEFAULT_GLOW: Color = Color.WHITE
## Where the lamp's two frames are kept, per material, once they are found.
const OFF_FRAME: StringName = &"lens_off"
const ON_FRAME: StringName = &"lens_on"
const GLOW: StringName = &"lens_glow"
## And where a lamp keeps the materials it lights.
const LIT_BY_LAMP: StringName = &"lens_materials"


## Ties every bound material to the lamp that lights it. Returns how many materials were bound.
static func bind(
    root: Node3D,
    truck: TruckParser,
    lamps: Array[Node3D],
    mod_dir: String,
    dds_reader: RefCounted,
    textures: Dictionary,
    scripts: Dictionary
) -> int:
    if truck.material_flares.is_empty():
        return 0
    var built: Dictionary = _by_name(root)
    var bound: int = 0
    for name: String in truck.material_flares.keys():
        var materials: Array = built.get(name, []) as Array
        if materials.is_empty():
            continue
        var declared: Dictionary = truck.managed_materials.get(name, {}) as Dictionary
        if declared.is_empty():
            declared = scripts.get(name, {}) as Dictionary
        var lit: Texture2D = _lit_frame(declared, mod_dir, dds_reader, textures)
        var glow: Color = declared.get("emissive", Color.BLACK) as Color
        if lit == null and glow == Color.BLACK:
            # Named as a lamp, but authored with nothing to switch: one frame and no glow of its
            # own. Left exactly as the mesh built it rather than being guessed at.
            continue
        for material: StandardMaterial3D in materials:
            material.set_meta(OFF_FRAME, material.albedo_texture)
            material.set_meta(ON_FRAME, lit if lit != null else material.albedo_texture)
            material.set_meta(GLOW, DEFAULT_GLOW if glow == Color.BLACK else glow)
            bound += 1
        for index: int in truck.material_flares[name] as PackedInt32Array:
            if index < 0 or index >= lamps.size():
                continue
            var lamp: Node3D = lamps[index]
            var lights: Array = lamp.get_meta(LIT_BY_LAMP, []) as Array
            lights.append_array(materials)
            lamp.set_meta(LIT_BY_LAMP, lights)
    return bound


## Switches the glass a lamp lights. Does nothing for a lamp that lights none, which is most.
static func light(lamp: Node3D, lit: bool) -> void:
    for entry: Variant in lamp.get_meta(LIT_BY_LAMP, []) as Array:
        var material: StandardMaterial3D = entry as StandardMaterial3D
        if material == null:
            continue
        material.albedo_texture = material.get_meta(
            ON_FRAME if lit else OFF_FRAME
        ) as Texture2D
        material.emission_enabled = lit
        if not lit:
            continue
        material.emission = material.get_meta(GLOW, DEFAULT_GLOW) as Color
        material.emission_texture = material.get_meta(ON_FRAME) as Texture2D
        material.emission_energy_multiplier = EMISSION_ENERGY


## The second frame of a material's flipbook, which is the lamp alight. Null where the material
## declares one frame, or where the file it names cannot be read.
static func _lit_frame(
    declared: Dictionary, mod_dir: String, dds_reader: RefCounted, textures: Dictionary
) -> Texture2D:
    var frames: PackedStringArray = declared.get("frames", PackedStringArray())
    if frames.size() < 2 or dds_reader == null:
        return null
    return MeshAssembler.texture(
        RorContentPath.find(frames[1], mod_dir), dds_reader, textures
    )


## Every material a vehicle was built with, by the name it was declared under.
##
## A surface keeps that name in `ogre_material` — see `MeshAssembler.material_for` — because a
## binding names a material and by this point the meshes hold materials rather than names.
static func _by_name(root: Node3D) -> Dictionary:
    var out: Dictionary = {}
    for node: Node in _meshes(root):
        var instance: MeshInstance3D = node as MeshInstance3D
        var surfaces: int = instance.mesh.get_surface_count() if instance.mesh != null else 0
        for surface: int in surfaces:
            var material: StandardMaterial3D = (
                instance.get_active_material(surface) as StandardMaterial3D
            )
            if material == null or not material.has_meta("ogre_material"):
                continue
            var name: String = material.get_meta("ogre_material") as String
            var materials: Array = out.get(name, []) as Array
            if not materials.has(material):
                materials.append(material)
            out[name] = materials
    return out


static func _meshes(node: Node) -> Array[Node]:
    var out: Array[Node] = []
    if node is MeshInstance3D:
        out.append(node)
    for child: Node in node.get_children():
        out.append_array(_meshes(child))
    return out
