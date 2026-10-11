class_name InertiaModels
extends RefCounted
## The named curves a command key's inertia follows, copied from Rigs of Rods' own
## `resources/skeleton/config/inertia_models.cfg`.
##
## A `commands` row, or a `set_inertia_defaults` directive, names a start and a stop curve; each is
## (time, rate) points that upstream threads an `Ogre::SimpleSpline` through, and a key's output
## climbs by the spline's value times 0.001 every substep. A name that is not here gives no
## inertia, as upstream gives none. Data, quoted rather than fitted, and held to upstream's file by
## `a_command_key_ramps_by_its_inertia_curve` whenever the submodule is present.

## Name -> flat [x0, y0, x1, y1, ...], in the file's order.
const MODELS: Dictionary = {
    "constant": [0, 1, 1, 1],
    "linear": [0, 0.0, 1.0, 1.0],
    "degressiv": [0, 0.0, 0.25, 0.5, 0.5, 0.701, 0.75, 0.866, 1.0, 1.0],
    "progressiv": [0, 0.0, 0.25, 0.063, 0.5, 0.25, 0.75, 0.564, 1.0, 1.0],
    "smooth": [0, 0.0, 0.2, 0.032, 0.4, 0.256, 0.6, 0.743, 0.8, 0.968, 1.0, 1.0],
    "revprogressiv": [0, 1.0, 0.25, 0.564, 0.5, 0.25, 0.75, 0.163, 1.0, 0.1],
    "smoothcrane": [0, 0.9, 0.05, 0.9, 0.1, 0.9, 0.15, 0.1, 0.2, 0.332, 0.4, 0.556, 0.6, 0.743, 0.8, 0.968, 1.0, 1.0],
    "slow01": [0, 0.01, 1, 0.01],
    "slow02": [0, 0.02, 1, 0.02],
    "slow04": [0, 0.04, 1, 0.04],
    "slow08": [0, 0.08, 1, 0.08],
    "slow10": [0, 0.1, 1, 0.1],
    "slow15": [0, 0.15, 1, 0.15],
    "slow20": [0, 0.20, 1, 0.20],
    "slow25": [0, 0.25, 1, 0.25],
    "slow30": [0, 0.30, 1, 0.30],
    "slow35": [0, 0.35, 1, 0.35],
    "slow40": [0, 0.40, 1, 0.40],
    "slow45": [0, 0.45, 1, 0.45],
    "slow50": [0, 0.50, 1, 0.50],
    "slow60": [0, 0.60, 1, 0.60],
    "slow70": [0, 0.70, 1, 0.70],
    "slow80": [0, 0.80, 1, 0.80],
    "slow90": [0, 0.90, 1, 0.90],
}


## Every model into `solver`, so a key can name one.
static func hand_to(solver: RefCounted) -> void:
    for name: String in MODELS:
        var points: Array = MODELS[name] as Array
        var xs: PackedFloat32Array = PackedFloat32Array()
        var ys: PackedFloat32Array = PackedFloat32Array()
        for i: int in range(0, points.size(), 2):
            xs.append(float(points[i]))
            ys.append(float(points[i + 1]))
        solver.add_inertia_model(name, xs, ys)


## Upstream's file read the way `CmdKeyInertiaConfig::LoadDefaultInertiaModels` reads it, for
## comparing against `MODELS`; empty when the file cannot be read.
static func parse(text: String) -> Dictionary:
    var out: Dictionary = {}
    var current: String = ""
    for raw: String in text.split("\n"):
        var line: String = raw.strip_edges()
        if line.is_empty() or line.begins_with(";"):
            continue
        var args: PackedStringArray = line.split(",")
        if args.size() == 1:
            current = line
        elif args.size() == 2 and current != "":
            if not out.has(current):
                out[current] = []
            (out[current] as Array).append(args[0].strip_edges().to_float())
            (out[current] as Array).append(args[1].strip_edges().to_float())
    return out
