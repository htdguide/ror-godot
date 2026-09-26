class_name Tunnel
extends RefCounted
## Builds the tunnel: two walls, a roof, and a row of lamps under it.
##
## Deliberately plain geometry. What is being tested is the lighting transition — sun and sky
## outside, local lamps and no sky inside — and a detailed tunnel would only make it harder to
## see which part of the result came from the lighting.


## Returns the tunnel's root, to be added to the world.
static func build() -> Node3D:
    var root: Node3D = Node3D.new()
    root.name = "Tunnel"
    root.position = TunnelCfg.CENTRE

    var material: StandardMaterial3D = StandardMaterial3D.new()
    material.albedo_color = TunnelCfg.STRUCTURE_COLOUR
    material.roughness = TunnelCfg.STRUCTURE_ROUGHNESS
    # Seen from inside as well as outside: without this the roof vanishes from under the
    # vehicle and the lamps appear to hang in the open.
    material.cull_mode = BaseMaterial3D.CULL_DISABLED

    var half_width: float = TunnelCfg.WIDTH_M * 0.5
    var wall: Vector3 = Vector3(
        TunnelCfg.LENGTH_M, TunnelCfg.HEIGHT_M, TunnelCfg.WALL_THICKNESS_M
    )
    root.add_child(_box(
        "WallLeft", wall, Vector3(0.0, TunnelCfg.HEIGHT_M * 0.5, -half_width), material
    ))
    root.add_child(_box(
        "WallRight", wall, Vector3(0.0, TunnelCfg.HEIGHT_M * 0.5, half_width), material
    ))
    root.add_child(_box(
        "Roof",
        Vector3(
            TunnelCfg.LENGTH_M,
            TunnelCfg.ROOF_THICKNESS_M,
            TunnelCfg.WIDTH_M + TunnelCfg.WALL_THICKNESS_M
        ),
        Vector3(0.0, TunnelCfg.HEIGHT_M + TunnelCfg.ROOF_THICKNESS_M * 0.5, 0.0),
        material
    ))

    var lamps: int = maxi(int(TunnelCfg.LENGTH_M / TunnelCfg.LAMP_SPACING_M), 1)
    for i: int in lamps:
        # Spread evenly along the tunnel, inset by half a spacing so none sits on an opening.
        var along: float = (float(i) + 0.5) / float(lamps) * TunnelCfg.LENGTH_M
        root.add_child(_lamp(i, Vector3(
            along - TunnelCfg.LENGTH_M * 0.5, TunnelCfg.LAMP_HEIGHT_M, 0.0
        )))
    return root


static func _box(name: String, size: Vector3, at: Vector3, material: Material) -> MeshInstance3D:
    var mesh: BoxMesh = BoxMesh.new()
    mesh.size = size
    var instance: MeshInstance3D = MeshInstance3D.new()
    instance.name = name
    instance.mesh = mesh
    instance.position = at
    instance.material_override = material
    return instance


static func _lamp(index: int, at: Vector3) -> OmniLight3D:
    var light: OmniLight3D = OmniLight3D.new()
    light.name = "Lamp_%d" % index
    light.position = at
    light.light_color = TunnelCfg.LAMP_COLOUR
    light.light_energy = TunnelCfg.LAMP_ENERGY
    light.omni_range = TunnelCfg.LAMP_RANGE_M
    # Shadows on: a row of lamps over a vehicle is the case where their absence is most
    # obvious, and it is half of what this tunnel exists to show.
    light.shadow_enabled = true
    return light
