class_name GroundModelSet
extends RefCounted
## The surfaces one terrain can be driven on: upstream's set, plus whatever the terrain adds.
##
## `GroundModels` is a fixed list because a surface map stores an index per cell and the index is
## part of that format. A terrain that ships its own ground models cannot be held in a fixed list:
## La Paz names `dirt` and `softsand`, neither of which exists upstream, and the next terrain will
## name something else again.
##
## So this is the same idea made per-terrain. Upstream's nine surfaces keep the indices they have,
## so a surface map written against `GroundModels` still means what it says, and anything a
## terrain adds is appended. A surface the terrain redefines keeps its index and takes the
## terrain's numbers, which is what upstream does with the same two files.

## Index -> name, upstream's order first.
var _order: PackedStringArray = PackedStringArray()
## name -> [adhesion, static, sliding, hydrodynamic, stribeck, alpha, strength].
var _values: Dictionary = {}


## The base set: upstream's own surfaces, as this project's checked copy of them.
static func upstream() -> GroundModelSet:
    var out: GroundModelSet = GroundModelSet.new()
    for name: String in GroundModels.ORDER:
        var values: Array = (GroundModels.SURFACES[name] as Array).duplicate()
        values.append(GroundModels.DEFAULT_ALPHA)
        values.append(GroundModels.DEFAULT_STRENGTH)
        out._order.append(name)
        out._values[name] = values
    return out


## Lays a terrain's own ground model config over the set. Returns how many surfaces it named.
##
## A surface the terrain also describes keeps its index and takes the values it states, one value
## at a time: a file that sets only a friction coefficient changes only that coefficient. A
## surface upstream has never heard of is appended, starting from upstream's own default surface
## so that anything it leaves out is still a number a wheel can be driven on.
func add_config(path: String) -> int:
    var parsed: Dictionary = GroundModelCfg.read(path)
    for name: String in parsed.keys():
        var row: Array = _values.get(name, []) as Array
        if row.is_empty():
            row = values_of(GroundModels.ORDER[0])
            _order.append(name)
        else:
            row = row.duplicate()
        var stated: Dictionary = parsed[name] as Dictionary
        for at: int in stated.keys():
            row[at] = float(stated[at])
        _values[name] = row
    return parsed.size()


## Which index a surface has, or -1 when the set does not hold it.
func index_of(name: String) -> int:
    return _order.find(name)


## Which surface an index is.
func name_of(index: int) -> String:
    return _order[index] if index >= 0 and index < _order.size() else ""


func size() -> int:
    return _order.size()


func names() -> PackedStringArray:
    return _order.duplicate()


## The seven numbers a surface is, as stored.
func values_of(name: String) -> Array:
    return (_values.get(name, []) as Array).duplicate()


## Registers every surface with a solver, at its own index.
func apply(solver: RefCounted) -> void:
    for index: int in _order.size():
        var values: Array = _values[_order[index]] as Array
        solver.set_ground_model(
            index,
            float(values[0]),
            float(values[1]),
            float(values[2]),
            float(values[3]),
            float(values[4]),
            float(values[5]),
            float(values[6])
        )
