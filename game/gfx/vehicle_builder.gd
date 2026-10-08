class_name VehicleBuilder
extends RefCounted
## Builds a renderable vehicle from an unmodified Rigs of Rods mod.
##
## Reads the rig, places each flexbody mesh into rig space with upstream's construction,
## and gives it a material derived from the legacy `managedmaterials` declaration. The
## mod is not modified, converted or re-exported: this is the compatibility promise being
## exercised rather than described.
##
## Materials here are deliberately minimal — albedo, plus roughness from the specular map
## where the mod supplies one. The material classification of ADR 0001 lands in M2; this
## is the geometry and texture path it will build on.

const TEXTURE_CACHE_HINT: int = 0


static func build(mod_dir: String, truck_file: String) -> Dictionary:
    var truck: TruckParser = TruckParser.new()
    var error: String = truck.parse_file(mod_dir.path_join(truck_file))
    if error != "":
        return {"error": error}
    var mesh_reader: RefCounted = ClassDB.instantiate("OgreMeshReader") as RefCounted
    var dds_reader: RefCounted = ClassDB.instantiate("DdsReader") as RefCounted
    if mesh_reader == null or dds_reader == null:
        return {"error": "the GDExtension did not load"}

    var root: Node3D = Node3D.new()
    root.name = "Vehicle"
    # The actor frame is computed but NOT applied to the render path. Wiring it —  frame
    # on the root, bones and wheels in actor-local space — makes two wheels render out on
    # open ground, while vehicle_assembly measures every part and every wheel's drawn
    # geometry within a millimetre of its rig position. The gate and the image disagree,
    # so one of them is wrong, and the gate is the thing to fix first: a gate that passes
    # while the render is visibly broken is worse than no gate at all. See
    # docs/architecture/bridge.md.
    var actor: Transform3D = ActorFrame.of(truck.nodes, truck.camera_nodes)
    root.transform = actor
    var render_frame: Transform3D = actor
    var parts: Array[SkinnedFlexbody] = []
    var textures: Dictionary = {}
    # A vehicle declares some materials in its own file and the rest in an Ogre `.material`
    # script beside it. Read once here and handed down, because a mesh does not know which of
    # the two its material came from and should not have to.
    var scripts: Dictionary = RorContentPath.materials(mod_dir)
    var built: int = 0
    var skipped: PackedStringArray = PackedStringArray()

    for entry: Dictionary in truck.flexbodies:
        var mesh_path: String = RorContentPath.find(entry["mesh"] as String, mod_dir)
        if not FileAccess.file_exists(mesh_path):
            skipped.append("%s (missing)" % entry["mesh"])
            continue
        var result: Dictionary = mesh_reader.read_file(mesh_path)
        if (result.get("error", "") as String) != "":
            skipped.append("%s (%s)" % [entry["mesh"], result["error"]])
            continue
        var part: SkinnedFlexbody = _build_skinned_flexbody(
            root, result, truck, entry, render_frame, mod_dir, dds_reader, textures, scripts
        )
        if part == null:
            skipped.append("%s (no geometry)" % entry["mesh"])
            continue
        parts.append(part)
        built += 1

    # The body panels a vehicle draws from its own nodes. Most of this library declares them and
    # none of it drew them: for four vehicles they are the whole of the geometry, and for ten
    # more they are bodywork missing from something that otherwise looked built.
    var cab_parts: Array[SkinnedFlexbody] = CabBody.build(
        root, truck, render_frame, mod_dir, dds_reader, textures, scripts
    )
    parts.append_array(cab_parts)
    built += cab_parts.size()

    var prop_nodes: Array[Node3D] = []
    for entry: Dictionary in truck.props:
        var node: Node3D = _build_prop(
            entry, truck, render_frame, mod_dir, mesh_reader, dds_reader, textures, scripts
        )
        if node == null:
            skipped.append("prop %s" % entry["mesh"])
            continue
        node.name = "Prop_%d" % prop_nodes.size()
        root.add_child(node)
        prop_nodes.append(node)

    var lamps: Array[Node3D] = FlareBuilder.build(
        root, truck, render_frame, mod_dir, dds_reader, textures, scripts
    )
    # And the lamps that light their own glass rather than only glowing in front of it. Built
    # after the meshes, because what it binds to is the materials they were given.
    var lit_lenses: int = MaterialFlares.bind(
        root, truck, lamps, mod_dir, dds_reader, textures, scripts
    )

    var wheels_built: int = 0
    var wheel_nodes: Array[Node3D] = []
    for index: int in truck.wheels.size():
        var wheel: Dictionary = truck.wheels[index]
        var node: Node3D = VehicleWheels.build(
            wheel, truck, render_frame, mod_dir, mesh_reader, dds_reader, textures, scripts
        )
        if node == null:
            skipped.append("wheel %s" % wheel["mesh"])
            continue
        # Names must be unique or Godot discards them entirely, replacing the node name
        # with a generated one, and anything that finds nodes by name stops working.
        node.name = "Wheel_%d_%s" % [index, wheel["side"]]
        root.add_child(node)
        wheel_nodes.append(node)
        wheels_built += 1

    # Last, because it is sized to what everything above it drew.
    var probe: ReflectionProbe = ActorProbe.add(root)

    return {
        "error": "",
        "root": root,
        "probe": probe,
        "actor": actor,
        # How a rig-space point becomes a point in the vehicle's local space. Declared so
        # checks can place rig coordinates without knowing how the frame is wired.
        "rig_to_local": render_frame.affine_inverse(),
        # Where the frame's origin was when the vehicle was built, so a later pose can
        # tell the rig's own motion apart from where a caller has placed the vehicle.
        "frame_origin": render_frame.origin,
        "parts": parts,
        "cab_parts": cab_parts.size(),
        "wheel_nodes": wheel_nodes,
        "prop_nodes": prop_nodes,
        "lamps": lamps,
        "flares": lamps.size(),
        # How many of the vehicle's own materials are lamp glass, from `materialflarebindings`.
        "lit_lenses": lit_lenses,
        "props": prop_nodes.size(),
        "wheels": wheels_built,
        "truck": truck,
        "built": built,
        "skipped": skipped,
        "textures": textures.size(),
    }


## World bounds of everything a built vehicle draws.
static func world_bounds(root: Node3D) -> AABB:
    var bounds: AABB = AABB()
    var started: bool = false
    for node: Node in _descendants(root):
        var mesh_instance: MeshInstance3D = node as MeshInstance3D
        if mesh_instance == null or mesh_instance.mesh == null:
            continue
        # The instance's own AABB, not the mesh's: a skinned part's mesh holds rest
        # positions in rig space, while what it draws is in actor-local space, and only
        # the instance knows the difference (SkinnedFlexbody keeps it up to date).
        var world: AABB = mesh_instance.global_transform * mesh_instance.get_aabb()
        bounds = world if not started else bounds.merge(world)
        started = true
    return bounds


static func _descendants(node: Node) -> Array[Node]:
    var out: Array[Node] = []
    for child: Node in node.get_children():
        out.append(child)
        out.append_array(_descendants(child))
    return out


## Drives the whole vehicle to a node pose: the frame on the root, deformation in the
## bones. This is the per-frame entry point the solver calls.
##
## `wheel_angles` spins the rims, one accumulated angle in radians per wheel. A wheel's
## drawn geometry is posed by its axle nodes, and an axle node does not rotate — so without
## this a vehicle drives along with its wheels standing perfectly still.
##
## **Two phases, timed separately.** Deform is arithmetic over the node positions — the actor
## frame, every part's bone transforms, every prop's, lamp's and wheel's placement — and submit is
## handing those to the renderer and the scene tree. Returns `{"deform_usec", "submit_usec"}`, which
## is what puts `deform_ms` and `submit_ms` beside `solver_ms` in `HARNESS_METRIC`.
static func apply_pose(
    built: Dictionary,
    truck: TruckParser,
    nodes: PackedVector3Array,
    wheel_angles: PackedFloat32Array = PackedFloat32Array()
) -> Dictionary:
    var began: int = Time.get_ticks_usec()
    var actor: Transform3D = ActorFrame.of(nodes, truck.camera_nodes)
    var to_local: Transform3D = actor.affine_inverse()
    var parts: Array[SkinnedFlexbody] = built["parts"] as Array[SkinnedFlexbody]
    var bones: Array = []
    for part: SkinnedFlexbody in parts:
        bones.append(part.local_bone_transforms(nodes, actor))
    var prop_nodes: Array[Node3D] = built["prop_nodes"] as Array[Node3D]
    var prop_frames: Array[Transform3D] = []
    for i: int in mini(prop_nodes.size(), truck.props.size()):
        prop_frames.append(to_local * FlexbodyBinder.placement(nodes, truck.props[i]))
    var wheel_nodes: Array[Node3D] = built["wheel_nodes"] as Array[Node3D]
    var wheel_frames: Array[Transform3D] = []
    for i: int in mini(wheel_nodes.size(), truck.wheels.size()):
        wheel_frames.append(to_local * WheelBuilder.rim_transform(nodes, truck.wheels[i]))
    var deformed: int = Time.get_ticks_usec()

    var root: Node3D = built["root"] as Node3D
    # Keep whatever the caller did to place the vehicle for a camera, and change only the
    # part of the transform the rig owns.
    var placement: Vector3 = root.transform.origin - built["frame_origin"] as Vector3
    root.transform = Transform3D(actor.basis, actor.origin + placement)
    built["frame_origin"] = actor.origin
    for i: int in parts.size():
        parts[i].submit(bones[i] as Array[Transform3D], actor, false)
    # Props are rigid: they ride their node triad rather than deforming with it.
    for i: int in prop_frames.size():
        prop_nodes[i].transform = prop_frames[i]
    FlareBuilder.apply_pose(built["lamps"] as Array[Node3D], truck, nodes, actor)
    # Wheels follow their own axle nodes, so suspension travel moves them.
    for i: int in wheel_frames.size():
        wheel_nodes[i].transform = wheel_frames[i]
        if i < wheel_angles.size():
            _spin_wheel(wheel_nodes[i], truck.wheels[i], wheel_angles[i])
    return {"deform_usec": deformed - began, "submit_usec": Time.get_ticks_usec() - deformed}


## Turns one wheel's drawn geometry about its axle.
##
## The angle comes from the solver, which measures tread speed about the axle it was given:
## the axle nodes ordered so the first has the smaller z. The rim frame points its own X
## outward instead, which is the opposite direction on the left of the vehicle to the right,
## so the sign follows the side the wheel is on and not the angle.
##
## Which way round the pair goes is measured, not derived: `wheels_roll_on_screen` tracks a
## tread vertex and requires the contact patch to be the slowest part of the tyre. Inverted,
## it read 2583% instead of the 4% it reads now.
static func _spin_wheel(holder: Node3D, wheel: Dictionary, angle: float) -> void:
    var sign: float = 1.0 if (wheel["side"] as String) == "r" else -1.0
    var spin: Transform3D = Transform3D(Basis(Vector3.RIGHT, angle * sign), Vector3.ZERO)
    for child: Node in holder.get_children():
        var mesh: MeshInstance3D = child as MeshInstance3D
        if mesh != null:
            mesh.transform = spin


## One flexbody, bound to its locator triads and skinned.
static func _build_skinned_flexbody(
    root: Node3D,
    result: Dictionary,
    truck: TruckParser,
    entry: Dictionary,
    actor: Transform3D,
    mod_dir: String,
    dds_reader: RefCounted,
    textures: Dictionary,
    scripts: Dictionary
) -> SkinnedFlexbody:
    var placement: Transform3D = FlexbodyBinder.placement(truck.nodes, entry, true)
    var vertices: PackedVector3Array = PackedVector3Array()
    var indices: PackedInt32Array = PackedInt32Array()
    var uvs: PackedVector2Array = PackedVector2Array()
    var normals: PackedVector3Array = PackedVector3Array()
    var material: Material = null
    # One group per submesh, so each keeps the material its own file gives it. See
    # `SkinnedFlexbody.build`.
    var groups: Array[Dictionary] = []
    for submesh: Dictionary in result["submeshes"] as Array:
        var positions: PackedVector3Array = submesh["positions"] as PackedVector3Array
        if positions.is_empty():
            continue
        var offset: int = vertices.size()
        for vertex: Vector3 in positions:
            vertices.append(placement * vertex)
        for index: int in submesh["indices"] as PackedInt32Array:
            indices.append(index + offset)
        var submesh_uvs: PackedVector2Array = submesh["uvs"] as PackedVector2Array
        var submesh_normals: PackedVector3Array = submesh["normals"] as PackedVector3Array
        for i: int in positions.size():
            uvs.append(submesh_uvs[i] if i < submesh_uvs.size() else Vector2.ZERO)
            # A locator placement is a rotation, so the basis carries normals correctly
            # without the inverse transpose a scaled or sheared one would need.
            normals.append(
                (placement.basis * submesh_normals[i]).normalized()
                if i < submesh_normals.size()
                else Vector3.UP
            )
        var own: Material = MeshAssembler.material_for(
            submesh["material"] as String, truck, mod_dir, dds_reader, textures, scripts
        )
        if material == null:
            material = own
        groups.append({
            "first": offset,
            "count": positions.size(),
            "indices": submesh["indices"] as PackedInt32Array,
            "material": own,
        })
    if vertices.is_empty():
        return null

    var part: SkinnedFlexbody = SkinnedFlexbody.new()
    var error: String = part.build(
        root,
        truck.nodes,
        entry["forset"] as PackedInt32Array,
        vertices,
        indices,
        material,
        uvs,
        normals,
        groups
    )
    if error != "":
        return null
    part.mesh_instance.name = (entry["mesh"] as String).get_basename()
    part.set_pose(truck.nodes, actor, false)
    return part


## A prop is a rigid mesh riding a node triad: the dashboard, the steering wheel, the
## seatbelts. Nothing about it deforms, so it needs no skinning — only the same triad
## placement a flexbody starts from, re-applied each pose.
static func _build_prop(
    entry: Dictionary,
    truck: TruckParser,
    render_frame: Transform3D,
    mod_dir: String,
    mesh_reader: RefCounted,
    dds_reader: RefCounted,
    textures: Dictionary,
    scripts: Dictionary
) -> Node3D:
    var holder: Node3D = Node3D.new()
    holder.transform = render_frame.affine_inverse() * FlexbodyBinder.placement(
        truck.nodes, entry
    )
    var body: MeshInstance3D = VehicleWheels.mesh_node(
        entry["mesh"] as String, truck, mod_dir, mesh_reader, dds_reader, textures, scripts
    )
    if body != null:
        body.name = "Mesh"
        holder.add_child(body)
    # A dashboard carries the steering wheel as a second mesh, placed in the dashboard's
    # own space and turned about its column.
    var steering: MeshInstance3D = VehicleWheels.mesh_node(
        entry["steering_mesh"] as String, truck, mod_dir, mesh_reader, dds_reader, textures,
        scripts
    )
    if steering != null:
        steering.name = "SteeringWheel"
        # Rake only. The file's last number is degrees of wheel rotation per unit of
        # steering input, which is zero at rest; it belongs to the steering animation,
        # not to the wheel's resting pose.
        steering.transform = Transform3D(
            Cockpit.steering_basis(0.0), entry["steering_offset"] as Vector3
        )
        holder.add_child(steering)
    if body == null and steering == null:
        holder.queue_free()
        return null
    return holder


## One named mesh from the pack, or null when it is not named or not there. Every part that hangs
## a mesh off the rig — a prop, a rim, a flexbody tyre — reads it through here.
static func _build_flexbody(
    result: Dictionary,
    truck: TruckParser,
    entry: Dictionary,
    mod_dir: String,
    dds_reader: RefCounted,
    textures: Dictionary,
    scripts: Dictionary
) -> MeshInstance3D:
    var mesh: ArrayMesh = MeshAssembler.mesh_from(result, truck, mod_dir, dds_reader, textures, scripts)
    if mesh == null:
        return null
    var node: MeshInstance3D = MeshInstance3D.new()
    node.name = (entry["mesh"] as String).get_basename()
    node.mesh = mesh
    node.transform = FlexbodyBinder.placement(truck.nodes, entry, true)
    return node


