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
    root.add_child(_build_ground())
    # A shot with a subject of its own wants an empty stage: the scale props are there to
    # give an empty frame something to measure, not to share the frame with a vehicle.
    if include_props:
        for node: Node3D in _build_props():
            root.add_child(node)
    return root


static func _build_environment(weather: Dictionary) -> WorldEnvironment:
    var env: Environment = Environment.new()
    env.background_mode = Environment.BG_COLOR
    env.background_color = weather.get("bg_color", Color.BLACK) as Color
    env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    env.ambient_light_color = weather.get("bg_color", Color.GRAY) as Color
    env.ambient_light_energy = float(weather.get("ambient_energy", 0.0))
    var holder: WorldEnvironment = WorldEnvironment.new()
    holder.name = "WorldEnvironment"
    holder.environment = env
    return holder


static func _build_sun(weather: Dictionary) -> DirectionalLight3D:
    var sun: DirectionalLight3D = DirectionalLight3D.new()
    sun.name = "Sun"
    var euler_deg: Vector3 = weather.get("sun_euler_deg", Vector3.ZERO) as Vector3
    sun.rotation = Vector3(
        deg_to_rad(euler_deg.x), deg_to_rad(euler_deg.y), deg_to_rad(euler_deg.z)
    )
    sun.light_energy = float(weather.get("sun_energy", 1.0))
    sun.light_color = weather.get("sun_color", Color.WHITE) as Color
    sun.shadow_enabled = true
    sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
    sun.directional_shadow_max_distance = SHADOW_MAX_DISTANCE
    return sun


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
