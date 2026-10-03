class_name RorWater
extends RefCounted
## The sea a terrain declares, at the height it declares it.
##
## **Two lines in a `.terrn2` and nothing has ever read them.** `Water=1` and `WaterLine=254` are
## the whole of what a terrain says about its sea, and they have been parsed and ignored since
## the parser was written. Port Starling is a port: its spawn sits at 258 m, four metres above
## its own waterline, and the harbour it is named for has been a dry pit. Reported from a window
## in those words — "no water on the map" — and `simple2_w` declares water at 100 m and renders
## dry for the same reason.
##
## **A flat plane, because a height is all the file gives.** A wave would be this project
## inventing content. What makes the plane read as water rather than as coloured glass is the
## shader: it fades where the ground rises through it, so a beach is a gradient instead of a cut
## line, and it keeps a specular highlight so the sun is on it.
##
## **It reaches past the map on purpose.** An island's sea has to meet the horizon, not stop at
## the terrain's edge in a visible square, and upstream draws it the same way. The plane is
## `REACH` times the map across, centred on the map.
##
## `height_at` is the seam the plan asks for: buoyancy and an FFT surface both need one place to
## ask how high the water is, and everything that wants to know asks here rather than reading a
## config key of its own.

## How far past the map the sea reaches, as a multiple of the map's own width.
const REACH: float = 4.0
const SHADER: String = "res://game/shaders/water.gdshader"
## What the surface is called in the scene, so a gate and a session can find it.
const NODE_NAME: String = "RorWater"


## The terrain's sea as a node, and never null: a terrain that declares no water gets an empty
## one, so a caller never has to ask twice.
static func build(terrain: RorTerrain) -> Node3D:
    var root: Node3D = Node3D.new()
    root.name = NODE_NAME
    if not declares_water(terrain):
        return root
    var across: float = width_of(terrain)
    var plane: PlaneMesh = PlaneMesh.new()
    plane.size = Vector2(across * REACH, across * REACH)
    # One quad. There is no displacement to subdivide for, and a flat plane with a million
    # vertices is a million vertices doing nothing.
    plane.subdivide_width = 0
    plane.subdivide_depth = 0
    var surface: MeshInstance3D = MeshInstance3D.new()
    surface.name = "Surface"
    surface.mesh = plane
    surface.material_override = _material()
    # Centred on the map, at the height the file states. A RoR terrain starts at the origin and
    # runs positive, so its middle is half its width out along both axes.
    surface.position = Vector3(across * 0.5, height_at(terrain), across * 0.5)
    # The sea is drawn whatever the camera is doing: it is the size of the world and its own
    # bounding box is meaningless to a frustum test done per object.
    surface.extra_cull_margin = across * REACH
    # It casts no shadow. A plane the size of the world between the sun and the sea bed puts the
    # whole map in shade, which is what happened the first time this was built.
    surface.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    root.add_child(surface)
    return root


## Whether a terrain asks for a sea at all. Upstream reads `Water` as a flag and a zero there
## means no water whatever the waterline says.
static func declares_water(terrain: RorTerrain) -> bool:
    return terrain.config["water"] as bool


## How high the water is, in world metres. The one place anything asks.
static func height_at(terrain: RorTerrain) -> float:
    return terrain.config["water_line"] as float


## How wide the map is, in metres.
static func width_of(terrain: RorTerrain) -> float:
    var grid: Dictionary = terrain.lattice()
    return (grid["spacing"] as float) * float(grid["size"] as int)


static func _material() -> ShaderMaterial:
    var material: ShaderMaterial = ShaderMaterial.new()
    material.shader = load(SHADER) as Shader
    material.render_priority = 1
    return material
