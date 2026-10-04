class_name CollisionView
extends RefCounted
## Draws what a terrain is solid as, so a person can point at a place where there is something to
## hit and nothing to see.
##
## **Collision and geometry come from different files and nothing has ever compared them.** A
## `.odef` may ship a `beginmesh` hull or a `beginbox`, the visual mesh is separate, and where the
## two disagree the result is a wall you bounce off that is not there, or a ramp you can walk
## through. Asked for from a window, in those words: "there are vertical textures of a ramp or a
## pavement without the top surface, so you can fall inside of something that doesn't exist" —
## and then, as a way to find more of them, point at the place where there is collision and no
## texture.
##
## So this draws the solver's own boxes — the same `RorObjectCollision.boxes` the solver is given,
## not a second opinion about them — as translucent shells that show through whatever is in front.
## Where a box hangs in the air with nothing drawn in it, the geometry is missing. Where drawn
## geometry has no box around it, nothing will stop a vehicle.
##
## A diagnostic dress, like the facing paint. `--collision` turns it on and it is never part of a
## measured frame.

## What the shells are painted. Nothing in a terrain's palette is this, and it reads against both
## sky and ground.
const SOLID: Color = Color(0.1, 0.95, 0.85, 0.22)
## How many boxes to draw before giving up. Port Starling is solid in 5343 parts and every one is
## a draw call unless they are batched, which they are — this is the bound on the batch.
const MAX_BOXES: int = 20000
const NODE_NAME: String = "CollisionView"


## Every solid box of a terrain, as one multimesh. Never null; empty when the terrain is solid in
## nothing.
static func build(terrain: RorTerrain) -> Node3D:
    var root: Node3D = Node3D.new()
    root.name = NODE_NAME
    var boxes: Array[Dictionary] = RorObjectCollision.boxes(terrain)
    if boxes.is_empty():
        return root
    # One mesh, instanced. A box per node is 5343 nodes and 5343 draw calls, which changes the
    # frame time enough that a person looking for a visual fault finds a performance one instead.
    var unit: BoxMesh = BoxMesh.new()
    unit.size = Vector3.ONE
    unit.material = _material()
    var multimesh: MultiMesh = MultiMesh.new()
    multimesh.transform_format = MultiMesh.TRANSFORM_3D
    multimesh.mesh = unit
    var drawn: int = mini(boxes.size(), MAX_BOXES)
    multimesh.instance_count = drawn
    for index: int in drawn:
        var box: Dictionary = boxes[index]
        var at: Transform3D = box["transform"] as Transform3D
        # `half` is a half-extent and the unit box is one metre across, so the scale is the whole
        # extent.
        multimesh.set_instance_transform(index, _sized(at, box["half"] as Vector3))
    var node: MultiMeshInstance3D = MultiMeshInstance3D.new()
    node.name = "Solid"
    node.multimesh = multimesh
    node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    root.add_child(node)
    return root


## How many boxes a terrain is solid in, without building anything. For the line a session prints.
static func count(terrain: RorTerrain) -> int:
    return RorObjectCollision.boxes(terrain).size()


## One object's own boxes, in the object's frame rather than the world's, for looking at it on a
## stage beside its mesh.
##
## **Taken from the terrain's own list rather than rebuilt.** The point of looking is to see what
## the solver was given; a second derivation of it could differ and would be the wrong thing to
## judge. The boxes of the object's first placement are lifted back into its local frame by that
## placement's own transform.
static func for_object(terrain: RorTerrain, name: String, state: Dictionary) -> Node3D:
    var root: Node3D = Node3D.new()
    root.name = "Boxes"
    var placement: Dictionary = {}
    for candidate: Dictionary in RorObjects.placements(terrain):
        if (candidate["name"] as String) == name:
            placement = candidate
            break
    if placement.is_empty():
        return root
    var odef: Dictionary = RorObjects.definition(terrain, name, state)
    if (odef.get("error", "") as String) != "":
        return root
    var frame: Transform3D = RorObjects.transform_of(placement, odef["scale"] as Vector3)
    var inverse: Transform3D = frame.affine_inverse()
    var unit: BoxMesh = BoxMesh.new()
    unit.size = Vector3.ONE
    unit.material = _material()
    for box: Dictionary in RorObjectCollision.boxes(terrain):
        if (box.get("name", "") as String) != name:
            continue
        var at: Transform3D = box["transform"] as Transform3D
        # Only this placement's: the same object stands all over the map.
        if (at.origin - frame.origin).length() > 40.0:
            continue
        var shell: MeshInstance3D = MeshInstance3D.new()
        shell.mesh = unit
        shell.transform = inverse * _sized(at, box["half"] as Vector3)
        shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
        root.add_child(shell)
    return root


## How many boxes each object has, for ordering a review by how wrong it might be.
##
## One pass. Asking per object instead rebuilds every box on the terrain once per name — ninety
## rebuilds of five thousand boxes, which hangs a window before it opens.
static func counts(terrain: RorTerrain) -> Dictionary:
    var out: Dictionary = {}
    for box: Dictionary in RorObjectCollision.boxes(terrain):
        var name: String = box.get("name", "") as String
        if name != "":
            out[name] = (out.get(name, 0) as int) + 1
    return out


## A unit box sized to one box's own extents, in the box's own axes.
##
## **`scaled` is the wrong one and it lied about every box on the map.** `Basis.scaled` applies
## the scale in the parent's axes — after the rotation — so a box whose own z is its height came
## out with that height along world z: lying on its side, in the air. Reported from a window as
## "they are all flipped, they need 90 degrees to stand up", and the collision data was right the
## whole time. `scaled_local` applies it before the rotation, which is what a half-extent in the
## box's own frame means.
static func _sized(at: Transform3D, half: Vector3) -> Transform3D:
    return Transform3D(at.basis.orthonormalized().scaled_local(half * 2.0), at.origin)


static func _material() -> StandardMaterial3D:
    var material: StandardMaterial3D = StandardMaterial3D.new()
    material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    material.albedo_color = SOLID
    # Both sides and no depth test: the point is to see a box that is inside something, or behind
    # it. A shell you can only see from outside hides exactly the case this exists for.
    material.cull_mode = BaseMaterial3D.CULL_DISABLED
    # Seen through whatever is in front of it. In a session that is the point — a box inside a
    # building is the case worth finding — and on a review stage the object is alone, so there is
    # nothing it can hide behind to confuse the picture.
    material.no_depth_test = true
    return material
