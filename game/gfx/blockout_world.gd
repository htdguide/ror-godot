class_name BlockoutWorld
extends RefCounted
## Builds the M0 blockout world in code.
##
## There is no .tscn for a world and there never will be: the scene_purity gate fails
## the build if a .tscn carries anything but structure. A world is therefore a diffable
## text file, which is the only way a CLI-only workflow can review a visual change.
##
## M0's world exists to give the harness something unambiguous to photograph: a ground
## grid for scale, a row of boxes for shadow and silhouette, and a sphere for specular.

const GRID_EXTENT: float = 64.0
const BOX_COUNT: int = 5
const BOX_SPACING: float = 3.0
const BOX_SIZE: float = 1.2
const SPHERE_RADIUS: float = 0.9
const CHECKER_PIXELS: int = 512
const CHECKER_CELLS: int = 16
const SHADOW_MAX_DISTANCE: float = 120.0


static func build(
    weather: Dictionary, include_props: bool = true, clouds: bool = false
) -> Node3D:
    var root: Node3D = Node3D.new()
    root.name = "BlockoutWorld"
    root.add_child(_build_environment(weather, clouds))
    root.add_child(_build_sun(weather))
    # The fill is always built, even where a preset asks for none, and hidden instead. A window
    # switches weather on a world that already exists, and a light that was never created cannot
    # be switched back on.
    root.add_child(_build_fill(weather))
    root.add_child(_build_ground())
    # A shot with a subject of its own wants an empty stage: the scale props are there to
    # give an empty frame something to measure, not to share the frame with a vehicle.
    if include_props:
        for node: Node3D in _build_props():
            root.add_child(node)
    return root


static func _build_environment(weather: Dictionary, clouds: bool) -> WorldEnvironment:
    var env: Environment = Environment.new()
    _grade_environment(env, weather, clouds)
    env.tonemap_mode = RenderCfg.TONEMAP as Environment.ToneMapper
    env.tonemap_white = RenderCfg.WHITE
    env.tonemap_exposure = RenderCfg.EXPOSURE
    var holder: WorldEnvironment = WorldEnvironment.new()
    holder.name = "WorldEnvironment"
    holder.environment = env
    return holder


## Everything about the environment that a weather preset decides — the sky above all, which the
## window never rebuilt, so switching to a clear noon from a dusk kept the dusk's atmosphere.
static func _grade_environment(env: Environment, weather: Dictionary, clouds: bool) -> void:
    if bool(weather.get("physical_sky", false)):
        env.background_mode = Environment.BG_SKY
        WorldSky.apply(env, weather, clouds)
        # The sky lights the scene: diffuse from its irradiance, specular from its
        # radiance map. This is what makes metal look like metal without a light rig.
        env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
        # How much of the ambient term is the sky's own irradiance, and how much is the stated
        # colour below it.
        #
        # **At 1.0 the ambient energy does nothing at all.** Godot blends the sky's irradiance
        # against `ambient_light_color * ambient_light_energy` by this fraction, so a preset
        # that leaves it at one has no way to say "a dark night under a sky I can still see":
        # dimming the ground means dimming the sky with it, and the only knob left was the
        # sky's own multiplier. Measured, 0.05 and 0.015 ambient energy gave the same frame to
        # four decimals. A night states a small fraction here and lights its ground with the
        # colour instead.
        env.ambient_light_sky_contribution = float(
            weather.get("ambient_from_sky", RenderCfg.AMBIENT_FROM_SKY)
        )
        env.ambient_light_color = weather.get("ambient_colour", Color.WHITE) as Color
        env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
    else:
        env.background_mode = Environment.BG_COLOR
        env.background_color = weather.get("bg_color", Color.BLACK) as Color
        env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
        env.ambient_light_color = weather.get("bg_color", Color.GRAY) as Color
    # **A stated ambient does not respond to the camera and a light does.** Measured on one
    # unchanged scene, a surface lit only by `ambient_light_color` photographed at 0.060669 at
    # ISO 16, 32, 64 and 128 — the same value to six decimals across three stops — while the same
    # surface lit by the sun doubled with every stop, because Godot's exposure normalisation
    # reaches physical lights and not the ambient term. An hour that opens the lens up has to
    # open it on everything, so the camera is applied here instead.
    env.set_meta(WorldSky.STATED_AMBIENT, float(weather.get("ambient_energy", 0.0)))
    env.ambient_light_energy = (
        float(weather.get("ambient_energy", 0.0)) * PhysicalCamera.exposure_scale(weather)
    )
    WorldAir.grade(env, weather)


static func _build_sun(weather: Dictionary) -> DirectionalLight3D:
    var sun: DirectionalLight3D = DirectionalLight3D.new()
    sun.name = "Sun"
    # Aimed by where the sun is, not by Euler angles. "Up and over the camera's shoulder"
    # is a thing anyone can reason about; the pitch and yaw that produce it are not.
    sun.shadow_enabled = true
    sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
    sun.directional_shadow_max_distance = SHADOW_MAX_DISTANCE
    _grade_sun(sun, weather)
    return sun


## The fill: a second directional light from the opposite side, casting nothing.
##
## Ambient light has no direction, so it lifts a shaded surface without telling you anything about
## its shape. A fill does both — it is the oldest trick in lighting a subject, and the reason one
## side of this scene read as black without it. It casts no shadow, so it costs a pass and nothing
## else.
static func _build_fill(weather: Dictionary) -> DirectionalLight3D:
    var fill: DirectionalLight3D = DirectionalLight3D.new()
    fill.name = "Fill"
    _grade_fill(fill, weather)
    # The fill casts shadows too, and that is not a luxury: a shadowless directional light shines
    # straight through a roof, and `tunnel_lighting_changes` caught exactly that — with the fill
    # unshadowed the tunnel's own lamps supplied a quarter of the light inside it instead of
    # nearly half. It is a cheaper shadow than the sun's: half the range and softer.
    fill.shadow_enabled = true
    fill.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
    fill.directional_shadow_max_distance = SHADOW_MAX_DISTANCE * 0.5
    fill.shadow_opacity = float(weather.get("shadow_opacity", RenderCfg.SHADOW_OPACITY))
    fill.light_angular_distance = float(
        weather.get("sun_angular_deg", RenderCfg.SUN_ANGULAR_DEG)
    ) * 2.0
    return fill


## Puts a weather preset onto a world that already exists.
##
## **The window used to do this itself, and only partly.** `PlayRig._apply_weather` aimed the sun,
## set its `light_energy` and colour, and changed the environment's ambient colour and energy —
## and that was all. It never touched `light_intensity_lux`, which is what actually sets a light's
## brightness under physical units; it never touched the fill, so a 12 000 lux cool light kept
## burning through a night preset; and it never rebuilt the sky, so the atmosphere stayed at
## whatever the world was built with. Cycling to a dark preset left a scene lit by three things
## that had not been told.
##
## One function now, called by `build` and by the window, so the two cannot drift. Everything a
## preset can say is applied here or nowhere.
static func apply_weather(root: Node3D, weather: Dictionary, clouds: bool = false) -> void:
    var holder: WorldEnvironment = root.get_node_or_null(^"WorldEnvironment") as WorldEnvironment
    if holder != null and holder.environment != null:
        _grade_environment(holder.environment, weather, clouds)
    var sun: DirectionalLight3D = root.get_node_or_null(^"Sun") as DirectionalLight3D
    if sun != null:
        _grade_sun(sun, weather)
    var fill: DirectionalLight3D = root.get_node_or_null(^"Fill") as DirectionalLight3D
    if fill != null:
        _grade_fill(fill, weather)
    dim_unlit(root, float(weather.get("unlit_dim", 1.0)))


## Takes every unlit surface in the scene down with the hour.
##
## **A surface with `lighting off` does not know what time it is.** A Rigs of Rods terrain paints
## its horizon on one — La Paz's backdrop ring is a photograph of mountains with the daylight
## already in it — and upstream draws those unshaded so that they read as distance rather than as
## geometry. Under a day that moves, they are the one thing that does not: at midnight the world
## goes black and a band of bright grey mountains stays up around it.
##
## Nothing can light them correctly, because what they are is a picture of being lit. So they are
## scaled by how much of the day it is, which is the same number the sky's own brightness follows.
## A lamp's lens is exempt — it is unlit because it is a light, and a headlight at midnight is the
## one thing that should not dim — and says so with `keeps_its_own_light` on its material.
static func dim_unlit(root: Node, factor: float) -> void:
    for child: Node in root.get_children():
        dim_unlit(child, factor)
        var instance: GeometryInstance3D = child as GeometryInstance3D
        if instance == null:
            continue
        var mesh: Mesh = null
        if instance is MultiMeshInstance3D:
            var multimesh: MultiMesh = (instance as MultiMeshInstance3D).multimesh
            mesh = null if multimesh == null else multimesh.mesh
        elif instance is MeshInstance3D:
            mesh = (instance as MeshInstance3D).mesh
        if mesh == null:
            continue
        for surface: int in mesh.get_surface_count():
            _dim_one(mesh.surface_get_material(surface) as StandardMaterial3D, factor)


static func _dim_one(material: StandardMaterial3D, factor: float) -> void:
    if material == null or material.shading_mode != BaseMaterial3D.SHADING_MODE_UNSHADED:
        return
    if bool(material.get_meta("keeps_its_own_light", false)):
        return
    # The colour the material was built with, kept once so that dimming and undimming are not
    # a product of every hour this session has been through.
    if not material.has_meta("daylight_albedo"):
        material.set_meta("daylight_albedo", material.albedo_color)
    var base: Color = material.get_meta("daylight_albedo") as Color
    material.albedo_color = Color(
        base.r * factor, base.g * factor, base.b * factor, base.a
    )


## Everything about the sun that a weather preset decides.
static func _grade_sun(sun: DirectionalLight3D, weather: Dictionary) -> void:
    # Aimed by where the sun is, not by Euler angles. "Up and over the camera's shoulder"
    # is a thing anyone can reason about; the pitch and yaw that produce it are not.
    var toward_sun: Vector3 = (weather.get("sun_from", Vector3.UP) as Vector3).normalized()
    sun.look_at_from_position(sun.position, sun.position - toward_sun, Vector3.UP)
    # Real illuminance. `light_energy` stays as a trim on top, which is what a weather preset's
    # `sun_energy` now is: how much of a clear midday sun this hour gets. The window used to set
    # the trim and leave the lux, which changes a sun by a few per cent and looks like nothing.
    sun.light_intensity_lux = float(weather.get("sun_lux", RenderCfg.SUN_LUX_NOON))
    sun.light_energy = float(weather.get("sun_energy", 1.0))
    sun.light_color = weather.get("sun_color", Color.WHITE) as Color
    # A sun with an angular size softens its own shadow with distance from the contact, which is
    # what a shadow does; a point sun draws the same hard line a metre away and a hundred.
    sun.light_angular_distance = float(
        weather.get("sun_angular_deg", RenderCfg.SUN_ANGULAR_DEG)
    )
    # And the shadow is not a hole. Everything a session looks at lives on the side of the object
    # the sun is not on, so a shadow that removes all the light removes the subject with it.
    sun.shadow_opacity = float(weather.get("shadow_opacity", RenderCfg.SHADOW_OPACITY))


## Everything about the fill that a weather preset decides.
static func _grade_fill(fill: DirectionalLight3D, weather: Dictionary) -> void:
    var energy: float = float(weather.get("fill_energy", RenderCfg.FILL_ENERGY))
    # Hidden rather than absent where a preset wants no fill, so it can come back.
    fill.visible = energy > 0.0
    # Opposite the sun and lower, so it reaches the side the sun cannot.
    var toward_sun: Vector3 = (weather.get("sun_from", Vector3.UP) as Vector3).normalized()
    var toward_fill: Vector3 = Vector3(-toward_sun.x, maxf(toward_sun.y * 0.45, 0.2),
        -toward_sun.z).normalized()
    fill.look_at_from_position(Vector3.ZERO, -toward_fill, Vector3.UP)
    fill.light_intensity_lux = float(weather.get("fill_lux", RenderCfg.FILL_LUX))
    fill.light_energy = energy
    fill.light_color = weather.get("fill_colour", RenderCfg.FILL_COLOUR) as Color
    fill.shadow_opacity = float(weather.get("shadow_opacity", RenderCfg.SHADOW_OPACITY))
    fill.light_angular_distance = float(
        weather.get("sun_angular_deg", RenderCfg.SUN_ANGULAR_DEG)
    ) * 2.0


static func _build_ground() -> MeshInstance3D:
    var plane: PlaneMesh = PlaneMesh.new()
    plane.size = Vector2(GRID_EXTENT, GRID_EXTENT)
    var ground: MeshInstance3D = MeshInstance3D.new()
    ground.name = "Ground"
    ground.mesh = plane
    ground.material_override = _checker_material()
    return ground


## A generated checkerboard, not an imported texture. It gives scale, makes filtering
## and mip selection visible, and keeps M0 free of any asset dependency.
static func _checker_material() -> StandardMaterial3D:
    var image: Image = Image.create(CHECKER_PIXELS, CHECKER_PIXELS, false, Image.FORMAT_RGB8)
    var cell: int = CHECKER_PIXELS / CHECKER_CELLS
    for y: int in CHECKER_PIXELS:
        for x: int in CHECKER_PIXELS:
            var dark: bool = ((x / cell) + (y / cell)) % 2 == 0
            image.set_pixel(x, y, Color(0.22, 0.22, 0.24) if dark else Color(0.58, 0.58, 0.6))
    var material: StandardMaterial3D = StandardMaterial3D.new()
    material.albedo_texture = ImageTexture.create_from_image(image)
    material.uv1_scale = Vector3(GRID_EXTENT / float(CHECKER_CELLS), GRID_EXTENT / float(CHECKER_CELLS), 1.0)
    material.roughness = 0.85
    return material


static func _build_props() -> Array[Node3D]:
    var out: Array[Node3D] = []
    var box_mesh: BoxMesh = BoxMesh.new()
    box_mesh.size = Vector3(BOX_SIZE, BOX_SIZE, BOX_SIZE)
    for i: int in BOX_COUNT:
        var box: MeshInstance3D = MeshInstance3D.new()
        box.name = "Box%d" % i
        box.mesh = box_mesh
        box.position = Vector3(
            (float(i) - float(BOX_COUNT - 1) * 0.5) * BOX_SPACING, BOX_SIZE * 0.5, 0.0
        )
        out.append(box)

    var sphere_mesh: SphereMesh = SphereMesh.new()
    sphere_mesh.radius = SPHERE_RADIUS
    sphere_mesh.height = SPHERE_RADIUS * 2.0
    var sphere: MeshInstance3D = MeshInstance3D.new()
    sphere.name = "Sphere"
    sphere.mesh = sphere_mesh
    sphere.position = Vector3(0.0, SPHERE_RADIUS, -3.0)
    out.append(sphere)
    return out
