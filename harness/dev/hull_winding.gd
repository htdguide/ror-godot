extends SceneTree
## Whether a terrain's collision hulls are wound so their faces look outwards.
##
## A triangle is solid on the side its normal points to: a node behind the face by less than the
## slab is pushed back along that normal. Wound the other way, the solid side is the outside and a
## vehicle passes through the object until a face happens to catch it from within.


func _initialize() -> void:
    var loaded: Dictionary = RorTerrainLibrary.load_named(OS.get_cmdline_user_args()[0])
    var terrain: RorTerrain = loaded["terrain"] as RorTerrain
    var per_name: Dictionary = {}
    for tri: Dictionary in RorObjectCollision.triangles(terrain):
        var key: String = tri["name"] as String
        var seen: Dictionary = per_name.get(key, {"out": 0, "in": 0, "mid": Vector3.ZERO,
            "tris": [] as Array}) as Dictionary
        (seen["tris"] as Array).append(tri)
        seen["mid"] = (seen["mid"] as Vector3) + (tri["a"] as Vector3)
        per_name[key] = seen
    for key: String in per_name.keys():
        var seen: Dictionary = per_name[key] as Dictionary
        var tris: Array = seen["tris"] as Array
        var middle: Vector3 = (seen["mid"] as Vector3) / maxf(float(tris.size()), 1.0)
        # **Signed volume, not a centroid test.** A closed mesh's triangles sum to a positive
        # volume when they are wound outwards and a negative one when they are wound inwards,
        # whatever shape it is. Comparing each face against the centroid instead reads 50% on
        # every building in the library, which is noise: a concave hull has faces pointing every
        # way regardless of its winding.
        var volume: float = 0.0
        for tri: Dictionary in tris:
            volume += (tri["a"] as Vector3).dot(
                (tri["b"] as Vector3).cross(tri["c"] as Vector3)
            ) / 6.0
        print("%-30s %5d triangles, signed volume %+.1f m3 -> wound %s" % [
            key, tris.size(), volume, "outwards" if volume > 0.0 else "INWARDS"])
    quit(0)
