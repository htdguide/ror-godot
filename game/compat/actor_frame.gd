class_name ActorFrame
extends RefCounted
## The vehicle's own rigid frame, built from the reference nodes upstream declares in its
## `cameras` section.
##
## Rigs of Rods gives its scene node a position and never an orientation, so today every
## bit of a vehicle's rotation is baked into vertex positions. That is invisible in a
## still image and fatal for temporal effects: a truck turning across the screen produces
## no motion in its instance transform, so motion vectors report nothing moving and TAA
## smears exactly the object being looked at.
##
## The frame is deliberately rigid — orthonormalised, no scale, no shear. Deformation
## belongs in the bone transforms; the frame carries only where the vehicle is and which
## way it faces, which is what the renderer needs to reason about motion.

## Returns the actor's world frame. `camera_nodes` is {centre, dir, roll}.
static func of(nodes: PackedVector3Array, camera_nodes: Dictionary) -> Transform3D:
    if camera_nodes.is_empty():
        return Transform3D.IDENTITY
    var origin: Vector3 = nodes[camera_nodes["centre"] as int]
    var forward: Vector3 = nodes[camera_nodes["dir"] as int] - origin
    var side: Vector3 = nodes[camera_nodes["roll"] as int] - origin
    if forward.length_squared() == 0.0 or side.length_squared() == 0.0:
        return Transform3D(Basis.IDENTITY, origin)

    # Gram-Schmidt: keep the direction node's axis exactly, take the roll node only for
    # the plane it defines. A frame built by normalising three node deltas directly would
    # inherit the rig's shear, and the whole point of this frame is that it has none.
    # Upstream's cameras section names a centre, a node behind it, and a node to its
    # left. Godot's +Z points backwards and +X points right, so the direction node gives
    # +Z directly while the roll node must be negated: taking it as +X leaves a
    # right-handed basis that is rotated half a turn, and the vehicle renders upside down.
    var z: Vector3 = forward.normalized()
    var x: Vector3 = -(side - z * side.dot(z)).normalized()
    if x.length_squared() == 0.0:
        return Transform3D(Basis.IDENTITY, origin)
    return Transform3D(Basis(x, z.cross(x), z), origin)
