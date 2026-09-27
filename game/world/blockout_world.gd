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


static func build(weather: Dictionary, include_props: bool = true) -> Node3D:
    var root: Node3D = Node3D.new()
    root.name = "BlockoutWorld"
    root.add_child(_build_environment(weather))
    root.add_child(_build_sun(weather))
    var fill: DirectionalLight3D = _build_fill(weather)
    if fill != null:
        root.add_child(fill)
    root.add_child(_build_ground())
    # A shot with a subject of its own wants an empty stage: the scale props are there to
    # give an empty frame something to measure, not to share the frame with a vehicle.
    if include_props:
        for node: Node3D in _build_props():
            root.add_child(node)
    return root


static func _build_environment(weather: Dictionary) -> WorldEnvironment:
    var env: Environment = Environment.new()
    if bool(weather.get("physical_sky", false)):
        env.background_mode = Environment.BG_SKY
        env.sky = _build_sky(weather)
        # The sky lights the scene: diffuse from its irradiance, specular from its
        # radiance map. This is what makes metal look like metal without a light rig.
        env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
        env.ambient_light_sky_contribution = RenderCfg.AMBIENT_FROM_SKY
        env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
    else:
        env.background_mode = Environment.BG_COLOR
        env.background_color = weather.get("bg_color", Color.BLACK) as Color
        env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
        env.ambient_light_color = weather.get("bg_color", Color.GRAY) as Color
    env.ambient_light_energy = float(weather.get("ambient_energy", 0.0))
    # Distance haze, so a 4 km terrain has depth to it and a session can say how far it wants
    # to see. Not volumetric: that is a froxel grid with its own range and cost, and what a
    # driver wants is depth cueing to the horizon.
    env.fog_enabled = RenderCfg.FOG_ENABLED
    env.fog_density = RenderCfg.FOG_DENSITY
    env.fog_light_color = RenderCfg.FOG_COLOUR
    env.fog_sky_affect = RenderCfg.FOG_SKY_AFFECT
    env.tonemap_mode = RenderCfg.TONEMAP as Environment.ToneMapper
    env.tonemap_white = RenderCfg.WHITE
    env.tonemap_exposure = RenderCfg.EXPOSURE
    var holder: WorldEnvironment = WorldEnvironment.new()
    holder.name = "WorldEnvironment"
    holder.environment = env
    return holder


static func _build_sky(weather: Dictionary) -> Sky:
    # Clouds when the project asks for them, and the stated gradient underneath either way: the
    # cloud shader draws the same gradient, so the light a gate grades against does not move.
    if RenderCfg.CLOUDS_ENABLED:
        var clouded: ShaderMaterial = SkyClouds.material(weather)
        if clouded != null:
            var cloud_sky: Sky = Sky.new()
            cloud_sky.sky_material = clouded
            cloud_sky.radiance_size = RenderCfg.SKY_RADIANCE_SIZE as Sky.RadianceSize
            return cloud_sky
    var material: ProceduralSkyMaterial = ProceduralSkyMaterial.new()
    material.sky_top_color = weather.get("sky_top", RenderCfg.SKY_TOP) as Color
    material.sky_horizon_color = weather.get("sky_horizon", RenderCfg.SKY_HORIZON) as Color
    material.sky_curve = RenderCfg.SKY_CURVE
    material.ground_bottom_color = RenderCfg.GROUND_COLOR
    material.ground_horizon_color = RenderCfg.GROUND_HORIZON
    material.sun_angle_max = RenderCfg.SUN_ANGLE_MAX_DEG
    material.sun_curve = RenderCfg.SUN_CURVE
    material.energy_multiplier = float(weather.get("sky_energy", RenderCfg.SKY_ENERGY))
    var sky: Sky = Sky.new()
    sky.sky_material = material
    sky.radiance_size = RenderCfg.SKY_RADIANCE_SIZE as Sky.RadianceSize
    return sky


static func _build_sun(weather: Dictionary) -> DirectionalLight3D:
    var sun: DirectionalLight3D = DirectionalLight3D.new()
    sun.name = "Sun"
    # Aimed by where the sun is, not by Euler angles. "Up and over the camera's shoulder"
    # is a thing anyone can reason about; the pitch and yaw that produce it are not.
    var toward_sun: Vector3 = (weather.get("sun_from", Vector3.UP) as Vector3).normalized()
    sun.look_at_from_position(Vector3.ZERO, -toward_sun, Vector3.UP)
    sun.light_energy = float(weather.get("sun_energy", 1.0))
    sun.light_color = weather.get("sun_color", Color.WHITE) as Color
    sun.shadow_enabled = true
    sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
    sun.directional_shadow_max_distance = SHADOW_MAX_DISTANCE
    # A sun with an angular size softens its own shadow with distance from the contact, which is
    # what a shadow does; a point sun draws the same hard line a metre away and a hundred.
    sun.light_angular_distance = float(
        weather.get("sun_angular_deg", RenderCfg.SUN_ANGULAR_DEG)
    )
    # And the shadow is not a hole. Everything a session looks at lives on the side of the object
    # the sun is not on, so a shadow that removes all the light removes the subject with it.
    sun.shadow_opacity = float(weather.get("shadow_opacity", RenderCfg.SHADOW_OPACITY))
    return sun


## The fill: a second directional light from the opposite side, casting nothing.
##
## Ambient light has no direction, so it lifts a shaded surface without telling you anything about
## its shape. A fill does both — it is the oldest trick in lighting a subject, and the reason one
## side of this scene read as black without it. It casts no shadow, so it costs a pass and nothing
## else.
static func _build_fill(weather: Dictionary) -> DirectionalLight3D:
    var energy: float = float(weather.get("fill_energy", RenderCfg.FILL_ENERGY))
    if energy <= 0.0:
        return null
    var fill: DirectionalLight3D = DirectionalLight3D.new()
    fill.name = "Fill"
    # Opposite the sun and lower, so it reaches the side the sun cannot.
    var toward_sun: Vector3 = (weather.get("sun_from", Vector3.UP) as Vector3).normalized()
    var toward_fill: Vector3 = Vector3(-toward_sun.x, maxf(toward_sun.y * 0.45, 0.2),
        -toward_sun.z).normalized()
    fill.look_at_from_position(Vector3.ZERO, -toward_fill, Vector3.UP)
    fill.light_energy = energy
    fill.light_color = weather.get("fill_colour", RenderCfg.FILL_COLOUR) as Color
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
