class_name GroundModelCfg
extends RefCounted
## Reads a Rigs of Rods ground model config: the friction numbers a terrain ships for its own
## surfaces.
##
## Upstream's `ground_models.cfg` is the base set, and `GroundModels` is this project's checked
## copy of it. A terrain may also ship its own file and name it from its traction map config, and
## that file both overrides surfaces it shares with the base set and adds surfaces the base set
## has never heard of: La Paz paints `dirt` and defaults to `softsand`, and upstream's file
## describes neither.
##
## What is returned is only what each section actually states. Filling the gaps is `GroundModelSet`
## work, because what a missing value falls back to is the surface the base set already holds —
## a terrain that states one coefficient means to change one coefficient.
##
## Sections that state none of the friction keys are dropped. Upstream's own files carry variants
## kept for reference, and a surface registered with zeroes is a surface a vehicle falls through
## the moment a traction map points at it.

## The friction keys, in the order `GroundModels.SURFACES` stores its values, then the two
## upstream leaves commented out in every surface of its own file.
const KEYS: Array[String] = [
    "adhesion velocity",
    "static friction coefficient",
    "sliding friction coefficient",
    "hydrodynamic friction",
    "stribeck velocity",
    "alpha",
    "strength",
    # The soft half: how deep the surface is before anything solid, and what the layer above
    # that is made of. Every hard surface states none of these and takes zeroes; La Paz's sand
    # states a 0.1 m layer of a power-law fluid, and it is the whole of why sand is not asphalt.
    "solid ground level",
    "fluid density",
    "flow consistency index",
    "flow behavior index",
    "drag anisotropy",
]
## How many of the leading keys are the friction ones, which is what decides whether a section
## is describing a surface at all.
const FRICTION_KEYS: int = 5
## How many of the first five a section has to state to count as a surface description.
const MIN_STATED: int = 1


## Reads a ground model config as name -> {index into KEYS: value}, stating only what it states.
## Returns an empty dictionary when the file cannot be read.
static func read(path: String) -> Dictionary:
    var text: String = RorText.read(path)
    if text.is_empty():
        return {}
    var out: Dictionary = {}
    var section: String = ""
    var stated: Dictionary = {}
    for raw_line: String in text.split("\n"):
        var line: String = RorText.strip_comment(raw_line)
        if line.is_empty():
            continue
        if line.begins_with("[") and line.ends_with("]"):
            _keep(out, section, stated)
            section = line.substr(1, line.length() - 2).strip_edges().to_lower()
            stated = {}
            continue
        if not line.contains("="):
            continue
        var at: int = KEYS.find(line.get_slice("=", 0).strip_edges().to_lower())
        if at >= 0:
            stated[at] = line.substr(line.find("=") + 1).strip_edges().to_float()
    _keep(out, section, stated)
    return out


## Keeps a section if it describes friction at all.
static func _keep(out: Dictionary, section: String, stated: Dictionary) -> void:
    if section.is_empty() or section == "general":
        return
    var friction: int = 0
    for at: int in stated.keys():
        if at < FRICTION_KEYS:
            friction += 1
    if friction < MIN_STATED:
        return
    out[section] = stated
