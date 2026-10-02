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


## Everything about the environment that a weather preset decides — the sky above all, which the
## window never rebuilt, so switching to a clear noon from a dusk kept the dusk's atmosphere.
static func _grade_environment(env: Environment, weather: Dictionary, clouds: bool) -> void:
    if bool(weather.get("physical_sky", false)):
        env.background_mode = Environment.BG_SKY
        env.sky = _build_sky(weather, clouds)
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


## Whether this world's sky has weather in it.
##
## Off by default, and a session turns it on. The reason is the light: a cloud sky is a different
## sky, and every lighting gate in this project is graded against the stated gradient — measured,
## swapping the sky under them took the hero truck from 2.27x brighter lit from the front to
## 1.02x and stopped the tunnel being darker inside than out. So the gates keep the sky they were
## written against, the window gets the one with weather in it, and `the_sky_has_weather_in_it`
## asks for clouds explicitly. That the two are not the same sky is a real gap, and it is the
## same gap as the project's sun-to-sky balance: both want the HDRI work in M2.
##
## Threaded as a parameter rather than held in a `static var`, which is what it was: a build
## option smuggled through process-global state, so the sky a world got depended on what the
## last world to be built had asked for. Invisible with one world per process and an
## order-dependent bug the moment there is not — which is what D0's containers exist to stop.
static func _build_sky(weather: Dictionary, clouds: bool) -> Sky:
    if clouds and RenderCfg.CLOUDS_ENABLED:
        var clouded: ShaderMaterial = SkyClouds.material(weather)
        if clouded != null:
            return _new_sky(clouded)
    return _new_sky(
        _physical_sky(weather) if bool(weather.get("physical_sky", false))
        else _gradient_sky(weather)
    )


## A sky with its radiance map built once and built properly.
##
## **`process_mode` is the whole of this function's reason to exist.** Left at its default the
## radiance map is approximated across frames, and a scene that is not moving at all then renders
## two different images on alternate frames: measured on the hero truck's drop, a band of distant
## ground alternated between 0.6703 and 0.9906 luminance — the far half of the checker washing to
## pure white and back, every other frame, long after the truck had come to rest. The ground is
## rough and takes its specular from the sky's radiance map, so an unconverged map lands there
## first and lands hardest at grazing angles, which is why it was the distance that flickered.
##
## It was reported by eye before any gate caught it, and both skies had the same omission — the
## clouded one built its own `Sky` — which is why they now share one constructor.
static func _new_sky(material: Material) -> Sky:
    var sky: Sky = Sky.new()
    sky.process_mode = Sky.PROCESS_MODE_QUALITY
    sky.radiance_size = RenderCfg.SKY_RADIANCE_SIZE as Sky.RadianceSize
    sky.sky_material = material
    return sky


## A clear sky from an atmosphere model: Rayleigh scattering for the blue and the pale horizon,
## Mie for the haze around the sun, turbidity for how clean the air is.
##
## This is what `physical_sky` in a weather preset has always claimed and did not do — the flag
## selected a two-colour gradient. The difference that matters is not the look, it is where the
## irradiance comes from: a gradient's is whatever its colours integrate to, so the sun-to-sky
## balance was two numbers somebody chose, and it came out around 3:1 where clear daylight is
## nearer 14:1. A model produces the ratio rather than being told it.
##
## The sun direction is not set here. `PhysicalSkyMaterial` takes it from the first
## `DirectionalLight3D` in the world, which is `_build_sun`'s, so the sky and the sun agree about
## where the sun is by construction instead of by two configs matching.
static func _physical_sky(weather: Dictionary) -> PhysicalSkyMaterial:
    var material: PhysicalSkyMaterial = PhysicalSkyMaterial.new()
    material.rayleigh_coefficient = RenderCfg.RAYLEIGH_COEFFICIENT
    material.rayleigh_color = RenderCfg.RAYLEIGH_COLOR
    material.mie_coefficient = RenderCfg.MIE_COEFFICIENT
    material.mie_eccentricity = RenderCfg.MIE_ECCENTRICITY
    material.mie_color = RenderCfg.MIE_COLOR
    material.turbidity = float(weather.get("turbidity", RenderCfg.TURBIDITY))
    material.sun_disk_scale = RenderCfg.SUN_DISK_SCALE
    material.ground_color = RenderCfg.SKY_GROUND_COLOR
    material.energy_multiplier = float(weather.get("sky_energy", RenderCfg.SKY_ENERGY))
    return material


## The two-colour gradient, kept for the presets that are not a clear daylight sky — a night or a
## stated-colour preset has no atmosphere to model and a gradient is the honest way to say so.
static func _gradient_sky(weather: Dictionary) -> ProceduralSkyMaterial:
    var material: ProceduralSkyMaterial = ProceduralSkyMaterial.new()
    material.sky_top_color = weather.get("sky_top", RenderCfg.SKY_TOP) as Color
    material.sky_horizon_color = weather.get("sky_horizon", RenderCfg.SKY_HORIZON) as Color
    material.sky_curve = RenderCfg.SKY_CURVE
    material.ground_bottom_color = RenderCfg.GROUND_COLOR
    material.ground_horizon_color = RenderCfg.GROUND_HORIZON
    material.sun_angle_max = RenderCfg.SUN_ANGLE_MAX_DEG
    material.sun_curve = RenderCfg.SUN_CURVE
    material.energy_multiplier = float(weather.get("sky_energy", RenderCfg.SKY_ENERGY))
    return material


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
