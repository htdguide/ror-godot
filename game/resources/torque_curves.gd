class_name TorqueCurves
extends RefCounted
## The predefined engine torque models, copied from Rigs of Rods' own
## `resources/skeleton/config/torque_models.cfg`.
##
## A rig's `torquecurve` section may hold explicit (rpm, fraction) samples, or the name of
## one of these. The hero truck names `gas`, which is easy to miss: its section body is a
## single bare word, so a parser that treats any lone word as a section header reads the
## curve name as the start of a new section and silently gives the engine flat torque at
## every rpm instead of a real power band.
##
## These are data, not a model. Each pair is (rpm, fraction of the engine's peak torque),
## and they are quoted rather than fitted so a curve can be checked against upstream's
## file rather than against a number this project chose.

const MODELS: Dictionary = {
    "default": [[0.0, 1.0], [1000.0, 1.0], [10000.0, 1.0]],
    "diesel": [
        [0.0, 0.0], [1000.0, 0.79], [1500.0, 0.9], [2000.0, 0.97], [2500.0, 0.99],
        [3000.0, 0.9], [3500.0, 0.77],
    ],
    "turbodiesel": [
        [0.0, 0.0], [1000.0, 0.89], [1500.0, 1.0], [2000.0, 1.0], [2500.0, 1.0],
        [3000.0, 1.0], [3500.0, 1.0], [4000.0, 0.89], [4500.0, 0.81], [5000.0, 0.65],
    ],
    "gas": [
        [0.0, 0.0], [1000.0, 0.75], [1500.0, 0.8], [2000.0, 0.88], [2500.0, 0.93],
        [3000.0, 1.0], [3500.0, 0.98], [4000.0, 0.93], [4500.0, 0.9], [5000.0, 0.88],
        [5500.0, 0.83], [6000.0, 0.78],
    ],
    "turbogas": [
        [0.0, 0.0], [1000.0, 0.67], [1500.0, 1.0], [2000.0, 1.0], [2500.0, 1.0],
        [3000.0, 1.0], [3500.0, 1.0], [4000.0, 1.0], [4500.0, 1.0], [5000.0, 0.95],
        [5500.0, 0.88], [6000.0, 0.83],
    ],
    "wheelloader": [
        [0.0, 0.0], [800.0, 0.66], [900.0, 0.74], [1000.0, 0.81], [1100.0, 0.88],
        [1200.0, 0.96], [1300.0, 0.99], [1400.0, 1.0], [1500.0, 0.93], [1600.0, 0.88],
        [1700.0, 0.85], [1800.0, 0.77], [1900.0, 0.74], [2000.0, 0.7], [2100.0, 0.66],
        [2200.0, 0.63], [2300.0, 0.59],
    ],
    "compacttractor": [
        [1800.0, 0.87], [2000.0, 0.87], [2200.0, 0.84], [2400.0, 0.85], [2600.0, 0.88],
        [2800.0, 0.88], [3000.0, 0.89], [3200.0, 0.93], [3400.0, 0.96], [3600.0, 1.0],
    ],
    "tractor": [
        [1000.0, 0.9], [1100.0, 0.93], [1200.0, 0.98], [1300.0, 0.99], [1400.0, 1.0],
        [1500.0, 1.0], [1600.0, 0.97], [1700.0, 0.93], [1800.0, 0.87], [1900.0, 0.83],
        [2000.0, 0.77], [2100.0, 0.67], [2200.0, 0.5],
    ],
    "hydrostatic": [
        [400.0, 1.0], [600.0, 0.7], [800.0, 0.55], [1000.0, 0.4], [1200.0, 0.35],
        [1400.0, 0.3], [1600.0, 0.25],
    ],
}


static func has(model: String) -> bool:
    return MODELS.has(model.to_lower())


## Returns {"rpm": PackedFloat32Array, "ratio": PackedFloat32Array} for a named model, or
## empty arrays when the name is not one of upstream's.
static func samples(model: String) -> Dictionary:
    var rpm: PackedFloat32Array = PackedFloat32Array()
    var ratio: PackedFloat32Array = PackedFloat32Array()
    for pair: Array in MODELS.get(model.to_lower(), []) as Array:
        rpm.append(float(pair[0]))
        ratio.append(float(pair[1]))
    return {"rpm": rpm, "ratio": ratio}
