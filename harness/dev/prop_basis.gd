extends SceneTree
## Whether this project's prop frame is the one upstream builds, or a mirror of it.
##
## Upstream: `orientation = Quaternion(refx, normal, refy) * pp_rot`, with those three as the
## basis's columns. A mirrored frame turns every rotation applied after it the other way, which is
## what a steering wheel spinning backwards looks like.


func _initialize() -> void:
    var argv: PackedStringArray = OS.get_cmdline_user_args()
    var truck: TruckParser = TruckParser.new()
    if truck.parse_file(argv[0].path_join(argv[1])) != "":
        quit(1)
        return
    for index: int in truck.props.size():
        var prop: Dictionary = truck.props[index]
        if (prop["steering_mesh"] as String).is_empty():
            continue
        var ours: Transform3D = FlexbodyBinder.placement(truck.nodes, prop)
        # Upstream's own construction, written out here rather than reused.
        var origin: Vector3 = truck.nodes[prop["ref"] as int]
        var diff_x: Vector3 = truck.nodes[prop["nx"] as int] - origin
        var diff_y: Vector3 = truck.nodes[prop["ny"] as int] - origin
        var normal: Vector3 = diff_y.cross(diff_x).normalized()
        var ref_x: Vector3 = diff_x.normalized()
        var ref_y: Vector3 = ref_x.cross(normal)
        # Columns, as Ogre's `Quaternion(xaxis, yaxis, zaxis)` builds them. Godot's
        # `Basis(a, b, c)` sets ROWS, so the transpose of that is the same matrix.
        # Columns, as Ogre's `Quaternion(xaxis, yaxis, zaxis)` builds them. Godot's
        # `Basis(a, b, c)` sets ROWS, so the transpose of that is the same matrix. Then the
        # authored rotation, composed Z then Y then X as `ActorSpawner.cpp:1681` composes it.
        var rot: Vector3 = prop["rot_deg"] as Vector3
        # `Basis(a, b, c)` sets the columns in GDScript — `Basis.x/.y/.z` are the axes — which is
        # what Ogre's `Quaternion(xaxis, yaxis, zaxis)` builds, so no transpose.
        var upstream: Basis = Basis(ref_x, normal, ref_y) * (
            Basis(Vector3.BACK, deg_to_rad(rot.z))
            * Basis(Vector3.UP, deg_to_rad(rot.y))
            * Basis(Vector3.RIGHT, deg_to_rad(rot.x))
        )
        print("%s prop %d: ours det %+.3f, upstream det %+.3f, rotation %v" % [
            argv[1], index, ours.basis.determinant(), upstream.determinant(),
            prop["rot_deg"] as Vector3])
        # How far apart the two frames are, as the angle of the rotation taking one to the other.
        var between: Basis = upstream.inverse() * ours.basis.orthonormalized()
        print("    the two frames differ by %.1f degrees" % rad_to_deg(
            between.get_rotation_quaternion().get_angle()))
    quit(0)
