extends GateBase
## The terrain's ground is drawn from the material parameters its author shipped.
##
## This is a finding turned into a gate, and it currently fails. Written down in
## `docs/guides/hard-won-facts.md` and in PLAN §0.5: **Terrain3D is drawing the ground from the
## colour map and the heightmap, and the texture assets attached to it reach nothing.** Nine of
## them are built from La Paz's own splat textures, with the right names and images, and
## darkening a surface's albedo to a third, setting its `albedo_color` to white, or taking the
## normal map's depth to zero each changed the render by nothing at all, to four decimal places.
## What is visible as "surface" is the per-texel tint in the colour map.
##
## While that is true, every claim this project makes about how the ground looks is a claim about
## a colour map, the terrain's own imagery is thrown away, and the M2 ground material has nothing
## to stand on. So it gets a standing check rather than a paragraph.
##
## The measurement has its own negative control built in, which is why it is shaped this way:
## the same frame is rendered twice with one texture changed between them, so a render that does
## not move is the finding and a render that moves by the amount the change implies is the fix.
## Nothing here asserts what the ground should *look* like — only that it is drawn from the
## author's pixels rather than in spite of them.
##
## Two parameters are checked, because two findings were recorded against this same blank
## foundation and only one of them was collateral:
##
## - **Albedo**, the one above.
## - **Roughness.** "The per-surface values in `SurfaceCfg` reach the texture assets and,
##   measured, do not reach the picture." Terrain3D composes roughness as
##   `(color_map.a - 0.5) * 2 + normal_rough.a` plus a per-asset modifier
##   (`_texture_roughness_mod_array`), so the per-asset value *is* a shader input. It could not
##   have been seen before: all four of La Paz's assets are set to the same 0.9, so there was no
##   difference to observe even with working textures.
##
## **Normal maps are not checked, and that is not an omission.** La Paz ships `blank_NRM.dds` for
## all four of its layers — its normals really are flat. "Taking the normal map's depth to zero
## changed nothing" was a correct measurement of a blank normal map, not a symptom of the texture
## bug. A gate that perturbed it would be asserting that changing nothing changes something.

const TERRAIN_DIR: String = "assets/terrains/lapaz2"
const PRESET: String = "hero_3q"
const CONVERGE: int = 4
## Looking straight down, so the frame is ground and nothing else: a check that the ground
## changed must not be diluted by a sky that did not.
const CAMERA_HEIGHT_M: float = 120.0
## What the perturbed texture is multiplied by. A third is far outside anything a tonemapper or
## a filter could hide, and it is the figure the original finding used.
const DARKEN: float = 0.33
## How much the frame has to move. A third of the albedo over ground that fills the frame is a
## large change; this is set well below it so the gate is about whether the textures reach the
## picture at all, not about matching a predicted luma.
const MIN_LUMA_SHIFT: float = 0.02
## And how much a roughness sweep has to move it. Far smaller, because roughness changes the
## specular lobe rather than the diffuse albedo, and under a sky-dominated light a whole-terrain
## roughness sweep is a small fraction of the frame's luma. It is set to catch "nothing at all",
## which is what was recorded, not to assert a predicted amount.
const MIN_ROUGHNESS_SHIFT: float = 0.0005


static func meta() -> Dictionary:
    return {
        "name": "the_ground_draws_its_own_textures",
        "proves": "changing a terrain's own splat texture or its per-surface roughness changes the rendered ground, so the author's material parameters reach the picture",
        "builds_on": ["surfaces_are_visible"],
        "oracle": GateBase.ORACLE_INVARIANT,
        "threshold": (
            "multiplying one layer's albedo by %.2f moves the rendered ground by at least %.3f"
            % [DARKEN, MIN_LUMA_SHIFT] + " luma"
        ),
        "why": (
            "the texture assets attached to Terrain3D were measured to reach nothing: nine of"
            + " them, correctly built, and darkening one to a third changed the render by 0.0000."
            + " While that holds, every claim about how the ground looks is a claim about a"
            + " colour map and the terrain's own imagery is discarded. M2's ground material is"
            + " what makes this pass; until then it is a finding with a number on it rather"
            + " than a paragraph."
        ),
        "budget_s": 180.0,
        "needs_gpu": true,
        "milestone": "M2",
    }


func run(harness: Node) -> Dictionary:
    if not ClassDB.class_exists("Terrain3D"):
        return ok("skipped: Terrain3D is not installed. Run tools/build_terrain3d.sh", 0)
    var directory: String = SourceScan.repo_root().path_join(TERRAIN_DIR)
    if not DirAccess.dir_exists_absolute(directory):
        return ok("skipped: no terrain at %s" % TERRAIN_DIR, 0)
    var loaded: Dictionary = RorTerrain.load_from(directory)
    if (loaded["error"] as String) != "":
        return fail(loaded["error"] as String)
    var terrain_data: RorTerrain = loaded["terrain"] as RorTerrain

    var err: String = harness.setup_for(PRESET)
    if err != "":
        return fail(err)
    clear_fog(harness)
    var terrain: Node3D = TerrainWorld.create()
    harness.world.add_child(terrain)
    await harness.advance_frames(2, "static", "terrain")
    var built: String = harness.terrain.populate(terrain, terrain_data)
    if built != "":
        return fail(built)
    var ground: MeshInstance3D = harness.world.get_node_or_null(^"Ground") as MeshInstance3D
    if ground != null:
        ground.visible = false

    # Straight down over the middle of the map.
    var grid: Dictionary = terrain_data.lattice()
    var middle: float = 0.5 * float((grid["size"] as int) - 1) * (grid["spacing"] as float)
    var at: Vector3 = Vector3(middle, terrain_data.height_at_world(middle, middle), middle)
    harness.camera.look_at_from_position(
        at + Vector3(0.0, CAMERA_HEIGHT_M, 0.0), at, Vector3.FORWARD
    )

    var before: Dictionary = await _luma(harness, "ground_textures/before")
    if (before["error"] as String) != "":
        return fail(before["error"] as String)

    # The most-covered layer, so the change is where the camera is looking. Asked of the
    # terrain rather than assumed: which layer dominates is a property of what its author
    # painted.
    var layer: int = _widest_layer(terrain_data, middle)
    var changed: String = _darken_layer(terrain, layer)
    if changed != "":
        return fail(changed)
    await harness.advance_frames(2, "static", "terrain")

    var after: Dictionary = await _luma(harness, "ground_textures/after")
    if (after["error"] as String) != "":
        return fail(after["error"] as String)

    var shift: float = absf((before["luma"] as float) - (after["luma"] as float))
    if shift < MIN_LUMA_SHIFT:
        return fail(
            "layer %d's albedo was multiplied by %.2f and the ground moved by %.4f luma"
            % [layer, DARKEN, shift]
            + " (%.4f to %.4f): the terrain's own textures are not reaching the picture. See %s"
            % [before["luma"] as float, after["luma"] as float, before["png"] as String],
            shift
        )
    # Roughness, on the same frame, from the same direction: all assets to mirror, then all to
    # fully rough. A change either way means the per-asset value is a shader input.
    #
    # Measured on the terrain the albedo change left behind, deliberately: both halves of this
    # comparison see the same albedo, so the only thing that differs between them is roughness.
    # Restoring the albedo first would make the two numbers in the result read more naturally
    # and would add a state nothing else needs.
    var rough_shift: String = _set_roughness(terrain, 0.0)
    if rough_shift != "":
        return fail(rough_shift)
    await harness.advance_frames(2, "static", "terrain")
    var mirror: Dictionary = await _luma(harness, "ground_textures/mirror")
    if (mirror["error"] as String) != "":
        return fail(mirror["error"] as String)
    rough_shift = _set_roughness(terrain, 1.0)
    if rough_shift != "":
        return fail(rough_shift)
    await harness.advance_frames(2, "static", "terrain")
    var matte: Dictionary = await _luma(harness, "ground_textures/matte")
    if (matte["error"] as String) != "":
        return fail(matte["error"] as String)
    var roughness_moved: float = absf(
        (mirror["luma"] as float) - (matte["luma"] as float)
    )
    if roughness_moved < MIN_ROUGHNESS_SHIFT:
        return fail(
            "roughness from mirror to matte moved the ground %.5f luma (%.4f to %.4f), under"
            % [roughness_moved, mirror["luma"] as float, matte["luma"] as float]
            + " %.5f: the per-asset roughness is not a shader input" % MIN_ROUGHNESS_SHIFT,
            roughness_moved
        )
    return ok(
        "layer %d's albedo at %.2f moved the ground %.4f luma (%.4f to %.4f), and roughness from"
        % [layer, DARKEN, shift, before["luma"] as float, after["luma"] as float]
        + " mirror to matte moved it %.5f (%.4f to %.4f): the author's material parameters reach"
        % [roughness_moved, mirror["luma"] as float, matte["luma"] as float]
        + " the picture",
        shift
    )


## Sets every layer's roughness modifier and repacks, the same way the albedo change does.
func _set_roughness(terrain: Node3D, roughness: float) -> String:
    var assets: Object = terrain.get("assets")
    if assets == null:
        return "the terrain has no asset set to change"
    for asset: Object in assets.get("texture_list") as Array:
        asset.set("roughness", roughness)
    assets.call("update_texture_list")
    return ""


## Mean luma of a captured frame.
func _luma(harness: Node, out_dir: String) -> Dictionary:
    var shot: Dictionary = await harness.capture_shot(out_dir, "static", CONVERGE)
    if (shot["error"] as String) != "":
        return {"error": shot["error"], "luma": 0.0, "png": ""}
    var image: Image = Image.load_from_file(shot["png"] as String)
    if image == null:
        return {"error": "the capture at %s could not be read" % shot["png"], "luma": 0.0, "png": ""}
    var total: float = 0.0
    var counted: int = 0
    for y: int in range(0, image.get_height(), 4):
        for x: int in range(0, image.get_width(), 4):
            total += image.get_pixel(x, y).get_luminance()
            counted += 1
    return {"error": "", "luma": total / float(maxi(counted, 1)), "png": shot["png"]}


## Which splat layer covers the most ground under the camera.
func _widest_layer(terrain_data: RorTerrain, middle: float) -> int:
    var coverage: PackedFloat32Array = terrain_data.layer_coverage_at(middle, middle)
    var widest: int = 0
    for index: int in coverage.size():
        if coverage[index] > coverage[widest]:
            widest = index
    return widest


## Multiplies one layer's albedo texture by `DARKEN` and hands the terrain a whole new asset
## set.
##
## Changed in place and then repacked, through the same `update_texture_list` Terrain3D calls
## itself. Reassigning a whole new asset set was tried first and does nothing visible, which is
## worth knowing: `Terrain3D::set_assets` only reinitialises while the node is inside a world,
## and an array that is already packed stays packed.
func _darken_layer(terrain: Node3D, layer: int) -> String:
    var assets: Object = terrain.get("assets")
    if assets == null:
        return "the terrain has no asset set to change"
    var textures: Array = assets.get("texture_list") as Array
    if layer >= textures.size():
        return "the terrain has %d texture assets, not %d" % [textures.size(), layer + 1]
    var asset: Object = textures[layer] as Object
    var albedo: Texture2D = asset.get("albedo_texture") as Texture2D
    if albedo == null:
        return "layer %d has no albedo texture to change" % layer
    var image: Image = albedo.get_image()
    if image == null:
        return "layer %d's albedo has no readable image" % layer
    image = image.duplicate() as Image
    if image.is_compressed():
        image.decompress()
    for y: int in image.get_height():
        for x: int in image.get_width():
            var pixel: Color = image.get_pixel(x, y)
            image.set_pixel(x, y, Color(
                pixel.r * DARKEN, pixel.g * DARKEN, pixel.b * DARKEN, pixel.a
            ))
    # Mipmaps kept, because Terrain3D packs the array from them and a texture without a chain
    # is not the same input as one with.
    image.generate_mipmaps()
    asset.set("albedo_texture", ImageTexture.create_from_image(image))
    # Terrain3D packs its textures into an array when the asset list is initialised, so a change
    # to an asset afterwards is invisible until the array is repacked. `update_texture_list` is
    # the call Terrain3D makes itself; reassigning the whole set is not, and it silently did
    # nothing here.
    if not assets.has_method("update_texture_list"):
        return "this Terrain3D cannot repack its texture array from script"
    assets.call("update_texture_list")
    return ""
