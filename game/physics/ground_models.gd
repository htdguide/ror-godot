class_name GroundModels
extends RefCounted
## The surfaces a vehicle can drive on, copied from Rigs of Rods'
## `resources/skeleton/config/ground_models.cfg`.
##
## These are the numbers that decide whether a truck slides or tips. Every surface in this
## project was upstream's `concrete` until now — 1.2 static friction everywhere — which grips
## right up to the point a vehicle rolls over instead of letting it slide first. A rollover
## threshold is a ratio of track width to centre-of-mass height, and the hero truck's is
## 1.18 g; on concrete the tyres can deliver more than that, and on sand at 0.7 they cannot.
##
## They are data, not choices, and `ground_models_match_upstream` checks every value against
## the file they came from rather than trusting this copy.
##
## `alpha` and `strength` are upstream's built-in defaults: its config leaves them commented
## out in every surface.

const DEFAULT_ALPHA: float = 2.0
const DEFAULT_STRENGTH: float = 1.0

## Index -> name. The index is what a surface map stores per cell, so the order is part of the
## format: appending is safe, reordering is not.
const ORDER: Array[String] = [
    "concrete", "asphalt", "gravel", "rock", "ice", "snow", "metal", "grass", "sand",
]

## name -> [adhesion velocity, static friction, sliding friction, hydrodynamic friction,
## stribeck velocity].
const SURFACES: Dictionary = {
    "concrete": [3.0, 1.2, 0.75, 0.01, 6.0],
    "asphalt": [3.0, 1.2, 0.75, 0.01, 6.0],
    "gravel": [3.0, 0.85, 0.6, 0.006, 3.0],
    "rock": [3.0, 0.95, 0.7, 0.007, 8.0],
    "ice": [1.0, 0.3, 0.2, 0.0001, 3.0],
    "snow": [2.0, 0.65, 0.4, 0.004, 6.0],
    "metal": [3.0, 0.7, 0.4, 0.001, 3.0],
    "grass": [3.0, 0.8, 0.55, 0.005, 7.0],
    "sand": [3.0, 0.7, 0.55, 0.0001, 9.0],
}


static func index_of(name: String) -> int:
    return ORDER.find(name)


static func name_of(index: int) -> String:
    return ORDER[index] if index >= 0 and index < ORDER.size() else ""


## Registers every surface with a solver, at the index its position in ORDER gives it.
static func apply(solver: RefCounted) -> void:
    for index: int in ORDER.size():
        var values: Array = SURFACES[ORDER[index]] as Array
        solver.set_ground_model(
            index,
            float(values[0]),
            float(values[1]),
            float(values[2]),
            float(values[3]),
            float(values[4]),
            DEFAULT_ALPHA,
            DEFAULT_STRENGTH
        )
