class_name WheelRows
extends RefCounted
## The five wheel sections, each with its own field order, read into one row.
##
## **They are not variants of one layout.** `wheels` states a radius and a width where every other
## section states two radii; `wheels2` puts the rim radius first and the tyre second, which is the
## other way round from `meshwheels2` and `flexbodywheels`; and the rates come in a different order
## again — a mesh wheel states one spring and one damper, `wheels2` states rim then tyre, and a
## flexbody wheel states tyre then rim. Read with one layout, a `wheels` row's ray count is its
## width and its axle nodes are a ray count and a node. The layouts are upstream's
## `RigDef_Parser.cpp`: `ParseWheel`, `ParseWheel2`, `_ParseBaseMeshWheel`, `ParseFlexBodyWheel`.
##
## **How many nodes each generates is part of the section, not of the row.** From upstream's own
## spawn budget: `wheels`, `meshwheels` and `meshwheels2` append 2·rays, `wheels2` and
## `flexbodywheels` append 4·rays — a rim ring and a tyre ring. That count decides every node
## number after it, so it belongs beside the layout rather than in the generator.
##
## Split from `WheelRig` because that file generates geometry and this one only reads a line, and
## because the generator was at the source cap with two of the five sections unread: the Starling
## pack's buses, the Daf trailers, NhelensGrass's crane and both agoras state plain `wheels`, so
## they had no tread at all and stood on their own axles.

## Which sections this reads, and how many nodes each appends per ray.
const RINGS_PER_RAY: Dictionary = {
    "wheels": 2,
    "wheels2": 4,
    "meshwheels": 2,
    "meshwheels2": 2,
    "flexbodywheels": 4,
}
## **How far a tyre may stretch off its own hub before the structure takes over.** Upstream bounds
## every axle-to-tread beam as a SHOCK1 with a contraction limit of 0.66 and this as its extension
## limit — `AddWheelBeam(..., 0.66f, max_extension)` — and only `meshwheels2` passes a non-zero
## one. Unbounded, as these were, a spinning tyre is held on by its stated rate alone: the Burnside
## Drag's spokes stretched 28.7% under wheelspin, the tread left the hub by 100 mm and the axle
## laid over 88 degrees. 19 of 66 driveable vehicles did this.
const TYRE_MAX_EXTENSION: Dictionary = {
    "wheels": 0.0,
    "wheels2": 0.0,
    "meshwheels": 0.0,
    "meshwheels2": 0.15,
    "flexbodywheels": 0.0,
}
## Upstream's contraction limit on the same beams.
const TYRE_MAX_CONTRACTION: float = 0.66

## The least fields a row of each section carries, from upstream's own `CheckNumArguments`.
const LEAST_FIELDS: Dictionary = {
    "wheels": 14,
    "wheels2": 17,
    "meshwheels": 16,
    "meshwheels2": 16,
    "flexbodywheels": 16,
}


static func handles(section: String) -> bool:
    return RINGS_PER_RAY.has(section)


## How many nodes a row of `section` appends. Zero when the row is not one.
static func nodes_for(section: String, rays: int) -> int:
    return int(RINGS_PER_RAY.get(section, 0)) * rays


## One row of any wheel section, in the shape `WheelRig.generate` builds from.
##
## `rim_spring` and `rim_damp` are left out where the section does not state them: the caller fills
## them from the beam defaults in force, which is where upstream takes a mesh wheel's rim rate.
static func row(section: String, fields: PackedStringArray, id_to_index: Dictionary) -> Dictionary:
    var least: int = int(LEAST_FIELDS.get(section, 0))
    if least == 0:
        return {"error": "'%s' is not a wheel section" % section}
    if fields.size() < least:
        return {"error": "row has %d fields, expected at least %d" % [fields.size(), least]}
    var out: Dictionary = _plain(fields) if section == "wheels" else _two_radii(section, fields)
    var node1: int = int(id_to_index.get(out["node1"] as String, -1))
    var node2: int = int(id_to_index.get(out["node2"] as String, -1))
    if node1 < 0 or node2 < 0:
        return {"error": "row references an unknown node"}
    out["error"] = ""
    out["node1"] = node1
    out["node2"] = node2
    out["arm_node"] = int(id_to_index.get(out["arm_node"] as String, -1))
    # Two rings per ray is a mesh wheel's layout and four is a flexbody wheel's, whatever the
    # section is called: `wheels2` is built the way a flexbody wheel is and drawn the way a plain
    # one is.
    out["flexbody"] = int(RINGS_PER_RAY[section]) == 4
    out["max_extension"] = float(TYRE_MAX_EXTENSION.get(section, 0.0))
    out["first_tread"] = -1
    out["tread_count"] = 0
    return out


## `wheels`: "radius, width, rays, n1, n2, rigidity, braked, propulsed, arm, mass, spring, damp,
## face material, band material". The only section with one radius, and the only one that states
## no mesh: upstream sweeps a wheel of its own and paints the two materials onto it.
static func _plain(fields: PackedStringArray) -> Dictionary:
    return {
        "tire_radius": fields[0].to_float(),
        # No rim radius is stated. Nothing in a two-ring wheel needs one — the ring stands at the
        # tyre radius — and the generated wheel upstream draws is not built here yet.
        "rim_radius": 0.0,
        "width": fields[1].to_float(),
        "rays": fields[2].to_int(),
        "node1": fields[3],
        "node2": fields[4],
        "braked": fields[6].to_int(),
        "propulsed": fields[7].to_int(),
        "arm_node": fields[8],
        "mass": fields[9].to_float(),
        "spring": fields[10].to_float(),
        "damping": fields[11].to_float(),
        "side": "l",
        "mesh": "",
        "material": fields[13],
        "tyre_mesh": "",
        # **Both rings take the row's own rates.** `ProcessWheel` passes `wheel_def.springiness`
        # and `wheel_def.damping` for the tyre *and* for the rim; only `meshwheels2` reaches for
        # the beam defaults. Given the defaults instead, a rig that states none got the 9 MN/m
        # fallback on its rim ring: the Starling pack's buses and the Daf semis broke between 200
        # and 460 beams each, standing still.
        "rim_spring": fields[10].to_float(),
        "rim_damp": fields[11].to_float(),
    }


## The four sections that state two radii. They agree up to field 10 and then differ in which
## rates come first and what the tail holds.
static func _two_radii(section: String, fields: PackedStringArray) -> Dictionary:
    # `wheels2` states the rim radius first; the other three state the tyre first.
    var rim_first: bool = section == "wheels2"
    var out: Dictionary = {
        "tire_radius": fields[1].to_float() if rim_first else fields[0].to_float(),
        "rim_radius": fields[0].to_float() if rim_first else fields[1].to_float(),
        "width": fields[2].to_float(),
        "rays": fields[3].to_int(),
        "node1": fields[4],
        "node2": fields[5],
        "braked": fields[7].to_int(),
        "propulsed": fields[8].to_int(),
        "arm_node": fields[9],
        "mass": fields[10].to_float(),
        "side": "l",
        "mesh": "",
        "material": "",
        "tyre_mesh": "",
    }
    if section == "wheels2":
        # Rim rates first, then the tyre's, then two material names and no mesh.
        out["rim_spring"] = fields[11].to_float()
        out["rim_damp"] = fields[12].to_float()
        out["spring"] = fields[13].to_float()
        out["damping"] = fields[14].to_float()
        out["material"] = fields[16]
        return out
    out["spring"] = fields[11].to_float()
    out["damping"] = fields[12].to_float()
    if section == "meshwheels":
        # `ProcessMeshWheel` gives both rings the row's rates, the same as `wheels`. Its numbered
        # successor is the one that takes its rim from the beam defaults, and the two are a
        # different section for exactly this kind of reason.
        out["rim_spring"] = out["spring"]
        out["rim_damp"] = out["damping"]
    if section == "flexbodywheels":
        # Tyre rates, then the rim's, then a side and two **meshes**: a flexbody wheel draws its
        # tyre as geometry where a mesh wheel sweeps one and paints it.
        out["rim_spring"] = fields[13].to_float()
        out["rim_damp"] = fields[14].to_float()
        out["side"] = fields[15].to_lower()
        out["mesh"] = fields[16] if fields.size() > 16 else ""
        out["tyre_mesh"] = fields[17] if fields.size() > 17 else ""
        return out
    out["side"] = fields[13].to_lower()
    out["mesh"] = fields[14]
    out["material"] = fields[15]
    return out
