class_name RorObjectMaterial
extends RefCounted
## The material one submesh of a terrain object draws with, built from the terrain's own `.material`
## scripts.
##
## Split out of `RorObjects` when that file went over the source cap, and it is a seam rather than a
## slice: everything here answers one question — what does this surface look like — and what is left
## in `RorObjects` is where the objects are and how they are batched.

## What Blender's Ogre exporter puts between a material's name and the texture it was painted
## with.
const TEXFACE_MARK: String = "/TEXFACE/"


## The material a submesh names, built from the terrain's own scripts.
static func of(
    terrain: RorTerrain, name: String, state: Dictionary
) -> StandardMaterial3D:
    var cache: Dictionary = state["textures"] as Dictionary
    if cache.has(name):
        return cache[name] as StandardMaterial3D
    var material: StandardMaterial3D = StandardMaterial3D.new()
    material.albedo_color = Color(0.72, 0.70, 0.68)
    var declared: Dictionary = (state["materials"] as Dictionary).get(name, {}) as Dictionary
    if declared.is_empty():
        # Blender's Ogre exporter names a material after the texture it was painted with:
        # `Material.005/TEXFACE/asphaltshingles.dds`. No `.material` script declares those — the
        # name *is* the declaration — and Starling Island ships meshes that use them, which drew
        # untextured while the houses beside them were fine.
        declared = _texface(name)
    if not declared.is_empty():
        var textures: PackedStringArray = declared["textures"] as PackedStringArray
        if textures.size() > 0:
            var texture: Texture2D = RorTerrainSkin.texture_of(
                RorContentPath.find(textures[0], terrain.directory),
                state["dds"] as RefCounted
            )
            if texture != null:
                material.albedo_texture = texture
                material.albedo_color = Color.WHITE
        elif declared["has_diffuse"] as bool:
            # No texture and a colour of its own: a fixed-function pass painted flat. Keeping the
            # placeholder here is what made Starling Island's dark structures read as light grey.
            material.albedo_color = declared["diffuse"] as Color
        # Ogre's texture_unit `scale` scales the texture rather than the coordinates, so a
        # scale of 0.04 means the texture tiles twenty-five times across what the mesh's own
        # UVs cover. La Paz's ground skirt is one 20 km quad and states exactly that; without
        # it the skirt is one stretched texture and reads as a beige wall at the horizon.
        var scale: Vector2 = declared["scale"] as Vector2
        if scale.x > 0.0 and scale.y > 0.0 and not scale.is_equal_approx(Vector2.ONE):
            material.uv1_scale = Vector3(1.0 / scale.x, 1.0 / scale.y, 1.0)
        if declared["alpha"] as bool:
            # Cut rather than blended: these are vegetation cards and horizon panels, and a
            # blended one both sorts wrongly against the terrain and writes no depth.
            material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
            material.cull_mode = BaseMaterial3D.CULL_DISABLED
        if not (declared["lit"] as bool):
            material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
        # **What the pass says about its own highlight.** `specular <r> <g> <b> <shininess>` is the
        # only thing the legacy format states about how polished a surface is, and every one of the
        # 31 specular lines in this checkout is on a terrain object rather than on a vehicle: a
        # chapel, a hall, a tree set, Starling's structures. The exponent converts exactly to a
        # roughness — see `MaterialClass.roughness_from_shininess` — and the colour is what Godot's
        # `specular` scales, so a pass stating a black specular gets no highlight at all, which is
        # what ten of those lines ask for.
        var shininess: float = float(declared.get("shininess", -1.0))
        if shininess >= 0.0:
            material.roughness = MaterialClass.roughness_from_shininess(shininess)
            # `metallic_specular` is what Godot 4 calls the dielectric's own reflectance — there
            # is no `specular` property on a `StandardMaterial3D` in 4.x, only a mode.
            material.metallic_specular = clampf(
                (declared.get("specular", Color.BLACK) as Color).get_luminance(), 0.0, 1.0
            )
        # **A pass that states its own fog is a backdrop, and a backdrop stands in the same air as
        # everything else.** These are horizon rings and ground skirts painted *as* a distance,
        # standing ten kilometres out, and they were taken out of the scene's haze entirely: at
        # the fog this project used to run — a visual range of 6.5 km — anything at ten was a flat
        # grey sheet, which is what a session saw instead of a sky. The haze is clear air now
        # (`RenderCfg.FOG_DENSITY`), so the mountains are a soft ridge behind the plain rather than
        # a crisp cut-out standing on top of it, which is what the next session reported. What the
        # pass asked for is kept as a note on the material rather than acted on, because it is the
        # author describing *their* fog and not ours.
        if declared.get("no_fog", false) as bool:
            material.set_meta(RorObjects.ASKED_FOR_NO_FOG, true)
    cache[name] = material
    return material


## A material named after its own texture, as Blender's Ogre exporter writes them, or empty.
static func _texface(name: String) -> Dictionary:
    var at: int = name.rfind(TEXFACE_MARK)
    if at < 0:
        return {}
    var file: String = name.substr(at + TEXFACE_MARK.length())
    if file.is_empty():
        return {}
    return {"textures": PackedStringArray([file]), "alpha": false, "lit": true,
            "scale": Vector2.ONE}
