class_name VehicleWheels
extends RefCounted
## Building a wheel's drawn parts: the rim mesh the file names, and the tyre — a mesh of its own
## on a flexbody wheel, swept and painted on a mesh wheel.
##
## Split out of `VehicleBuilder` when that file went over the source cap, and it is a real seam:
## a wheel is the one part of a vehicle whose geometry can come from either the pack or this
## project, and the two mesh helpers here are what every part that hangs a mesh off the rig uses.


## The same mesh wrapped in a node, for the parts that need one.
static func mesh_node(
    name: String, truck: TruckParser, mod_dir: String, mesh_reader: RefCounted,
    dds_reader: RefCounted, textures: Dictionary, scripts: Dictionary
) -> MeshInstance3D:
    var mesh: ArrayMesh = named_mesh(
        name, truck, mod_dir, mesh_reader, dds_reader, textures, scripts
    )
    if mesh == null:
        return null
    var instance: MeshInstance3D = MeshInstance3D.new()
    instance.mesh = mesh
    return instance


static func named_mesh(
    name: String, truck: TruckParser, mod_dir: String, mesh_reader: RefCounted,
    dds_reader: RefCounted, textures: Dictionary, scripts: Dictionary
) -> ArrayMesh:
    if name == "":
        return null
    var path: String = RorContentPath.find(name, mod_dir)
    if not FileAccess.file_exists(path):
        return null
    var result: Dictionary = mesh_reader.read_file(path)
    if (result.get("error", "") as String) != "":
        return null
    return MeshAssembler.mesh_from(result, truck, mod_dir, dds_reader, textures, scripts)


## A wheel is a rim mesh posed by the axle nodes plus a tyre swept around them.
static func build(
    wheel: Dictionary,
    truck: TruckParser,
    render_frame: Transform3D,
    mod_dir: String,
    mesh_reader: RefCounted,
    dds_reader: RefCounted,
    textures: Dictionary,
    scripts: Dictionary
) -> Node3D:
    var holder: Node3D = Node3D.new()
    holder.transform = render_frame.affine_inverse() * WheelBuilder.rim_transform(
        truck.nodes, wheel
    )

    # A plain `wheels` row names no rim mesh at all. The instance is made only once there is a
    # mesh to put in it: made first and parented second, a rim with nothing to draw was left as an
    # orphan node per wheel, and `every_mod_car_builds` counted 36 of them across the library.
    var rim_mesh: ArrayMesh = named_mesh(
        wheel["mesh"] as String, truck, mod_dir, mesh_reader, dds_reader, textures, scripts
    )
    if rim_mesh != null:
        var rim: MeshInstance3D = MeshInstance3D.new()
        rim.name = "Rim"
        rim.mesh = rim_mesh
        holder.add_child(rim)

    # **A flexbody wheel's tyre is not drawn here.** It is a flexbody over the wheel's own nodes,
    # built with the rig and drawn with every other flexbody — see `WheelRig._tyre_flexbody`.
    # Upstream blanks the generated band for exactly these wheels, so there is nothing to sweep.
    if bool(wheel.get("flexbody", false)) and (wheel.get("tyre_mesh", "") as String) != "":
        return holder

    # A mesh wheel has its tyre swept around the tread and painted with the row's own material.
    var tyre: MeshInstance3D = MeshInstance3D.new()
    tyre.name = "Tyre"
    tyre.mesh = WheelBuilder.build_tyre(truck.nodes, wheel)
    tyre.material_override = MeshAssembler.material_for(
        wheel["material"] as String, truck, mod_dir, dds_reader, textures, scripts
    )
    holder.add_child(tyre)
    return holder
