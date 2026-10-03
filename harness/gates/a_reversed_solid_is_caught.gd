extends GateBase
## The test that decides which of a terrain object's triangles are drawn back to front is pointed
## at solids the engine makes itself, both the right way round and deliberately reversed.
##
## **A one-sided control passes a broken instrument.** The first version of this ray test left
## Godot's own `BoxMesh` alone, which looked like the correct answer and was: it also left a
## `BoxMesh` with every triangle reversed alone, and reported nothing wrong with it. One ray from
## the middle of a face crosses the far face exactly on the diagonal its two triangles share, is
## counted twice, and an inside-out solid reads as even. Pointed at content it turned
## `haus4.mesh`'s roof inside out while fixing its gable ends, and the sheets showed it.
##
## So the control runs both ways. A primitive the engine draws correctly must have **nothing**
## turned — a false positive is the dangerous direction, because it breaks content that was right
## — and the same primitive reversed must be caught almost entirely.
##
## **Why almost.** The bound is 85% rather than everything because the test has been two
## different things and may be again: when it decided surface by surface with a ray, a reversed
## sphere came back 256 of 288, the 32 misses being the fan of slivers at its poles where a ray
## grazes its neighbours instead of crossing them. Deciding by signed volume, as it does now, all
## three solids come back whole. A bound that only the current implementation can meet is a bound
## that has to be edited every time the implementation changes, and then it is not a control.

## How much of a reversed solid has to be caught.
const MIN_CAUGHT: float = 0.85


static func meta() -> Dictionary:
    return {
        "name": "a_reversed_solid_is_caught",
        "proves": (
            "the winding test turns nothing on a solid the engine draws correctly, and turns"
            + " almost all of the same solid reversed"
        ),
        "oracle": GateBase.ORACLE_EXTERNAL,
        "threshold": "0 triangles turned on a correct primitive, over 85% turned on a reversed one",
        "why": (
            "a control that only checks the correct case passes an instrument that can detect"
            + " nothing at all, and this one did: one ray from a face centre crosses the opposite"
            + " face on the diagonal its triangles share and is counted twice, so a reversed solid"
            + " reads as even. It turned a roof inside out before a two-way control caught it."
        ),
        "budget_s": 120.0,
        "needs_gpu": false,
        "milestone": "C2",
    }


func run(_harness: Node) -> Dictionary:
    var reported: PackedStringArray = PackedStringArray()
    var problems: PackedStringArray = PackedStringArray()
    for name: String in _controls().keys():
        var arrays: Array = (_controls()[name] as PrimitiveMesh).get_mesh_arrays()
        var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] as PackedInt32Array
        var triangles: int = indices.size() / 3
        var correct: int = _turned(_submesh(arrays, indices))
        var caught: int = _turned(_submesh(arrays, _reversed(indices)))
        reported.append("%s %d triangles, %d turned as built, %d of %d turned reversed"
            % [name, triangles, correct, caught, triangles])
        if correct > 0:
            problems.append(
                "%s is drawn correctly by the engine and %d of its %d triangles are turned"
                % [name, correct, triangles]
            )
        if triangles > 0 and float(caught) / float(triangles) < MIN_CAUGHT:
            problems.append(
                "%s reversed: only %d of %d triangles caught" % [name, caught, triangles]
            )
    if problems.size() > 0:
        return fail("; ".join(problems), problems.size())
    return ok("; ".join(reported), 0)


## Solids the engine builds and draws itself, small enough to stay under the ray test's own cost
## limit.
func _controls() -> Dictionary:
    var sphere: SphereMesh = SphereMesh.new()
    sphere.radial_segments = 16
    sphere.rings = 8
    var cylinder: CylinderMesh = CylinderMesh.new()
    cylinder.radial_segments = 16
    cylinder.rings = 1
    return {"BoxMesh": BoxMesh.new(), "SphereMesh": sphere, "CylinderMesh": cylinder}


## How many triangles the winding test would turn.
func _turned(submeshes: Array) -> int:
    var turned: int = 0
    for indices: PackedInt32Array in ObjectWinding.plan(submeshes):
        turned += indices.size()
    return turned


## The reader's shape of a submesh, from a primitive's arrays.
func _submesh(arrays: Array, indices: PackedInt32Array) -> Array:
    return [{
        "positions": arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array,
        "indices": indices,
        "normals": arrays[Mesh.ARRAY_NORMAL] as PackedVector3Array,
        "uvs": arrays[Mesh.ARRAY_TEX_UV] as PackedVector2Array,
    }]


## The same triangles wound the other way round.
func _reversed(indices: PackedInt32Array) -> PackedInt32Array:
    var out: PackedInt32Array = indices.duplicate()
    for at: int in range(0, out.size() - 2, 3):
        var swap: int = out[at + 1]
        out[at + 1] = out[at + 2]
        out[at + 2] = swap
    return out
