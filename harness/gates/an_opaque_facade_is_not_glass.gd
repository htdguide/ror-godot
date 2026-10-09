extends GateBase
## A terrain surface that does not blend is not built as glass, whatever its texture is called.
##
## A modular building is one submesh painted with one atlas, and the atlas is named after what is
## in it: Starling's `modularbuildings/TEXFACE/window_chicago_lightgrey.dds` covers the brick and
## the mullions as well as the panes. The material classifier reads names — that is the second of
## its three sources, after authored data and before the default — and `window` put the whole
## facade in the glass class at roughness 0.05. A vertical wall at that roughness mirrors any low
## sun, and a session in `dawn_mist` photographed a blown white disc three storeys across on the
## office block, with the sun six degrees up behind the camera's shoulder. It showed only under the
## mist presets because those are the ones with a low sun.
##
## The oracle is the format's own: legacy glass is a pass that blends (`scene_blend`), which is
## authored, and a name is a hint. So every surface a shipped terrain draws is built the way the
## loader builds it, and any surface whose name alone says glass or lamp but whose pass is opaque
## has to come out at its default class's roughness. The count of such surfaces is reported, and
## the gate refuses to pass on a checkout that has none, because then it has checked nothing.

const MIN_FOUND: int = 1
const LISTED: int = 6


static func meta() -> Dictionary:
    return {
        "name": "an_opaque_facade_is_not_glass",
        "proves": "every terrain-object surface whose name alone would class it as glass or lamp, but whose pass does not blend, is built at its default class's roughness rather than as a mirror",
        "builds_on": ["a_pass_that_states_its_highlight_gets_it"],
        "oracle": GateBase.ORACLE_INVARIANT,
        "threshold": "0 opaque surfaces built with the glass or lamp class, over at least %d named as one" % MIN_FOUND,
        "why": (
            "a facade atlas named window is brick as much as glass, and glass by name made a"
            + " vertical wall a mirror of the dawn sun. Blending is what the format says about"
            + " glass; a name is what an exporter said about a texture."
        ),
        "budget_s": 120.0,
        "needs_gpu": false,
        "milestone": "M2",
    }


func run(_harness: Node) -> Dictionary:
    var found: int = 0
    var problems: PackedStringArray = PackedStringArray()
    var named: PackedStringArray = PackedStringArray()
    for summary: Dictionary in RorTerrainLibrary.summaries():
        if (summary.get("error", "") as String) != "":
            continue
        var loaded: Dictionary = RorTerrainLibrary.load_named(summary["name"] as String)
        if (loaded.get("error", "") as String) != "":
            continue
        var terrain: RorTerrain = loaded["terrain"] as RorTerrain
        var state: Dictionary = RorObjects.state(terrain)
        # Build every mesh the terrain places, so that every surface it draws has its material
        # in the state's cache under the name the mesh gave it.
        for placement: Dictionary in RorObjects.placements(terrain):
            var odef: Dictionary = RorObjects.definition(terrain, placement["name"] as String, state)
            if (odef.get("error", "") as String) != "":
                continue
            var files: PackedStringArray = odef.get("meshes", PackedStringArray()) as PackedStringArray
            for lod: Dictionary in odef.get("lods", [] as Array[Dictionary]) as Array:
                files.append(lod["mesh"] as String)
            for file: String in files:
                RorObjects.mesh_of(terrain, file, state)
        var built: Dictionary = state["textures"] as Dictionary
        for name: String in built.keys():
            var material: StandardMaterial3D = built[name] as StandardMaterial3D
            if material == null:
                continue
            var declared: Dictionary = (state["materials"] as Dictionary).get(name, {}) as Dictionary
            if declared.is_empty():
                declared = RorObjectMaterial._texface(name)
            if declared.is_empty():
                continue
            var by_name: String = MaterialClass.classify(name, declared)["class"] as String
            if not RorObjectMaterial.OPAQUE_IS_NOT.has(by_name):
                continue
            if declared["alpha"] as bool:
                continue
            found += 1
            if named.size() < LISTED:
                named.append("%s: %s" % [terrain.name, name])
            var wanted: float = float((MaterialCfg.CLASSES["default"] as Dictionary)["roughness"])
            var guessed: float = float((MaterialCfg.CLASSES[by_name] as Dictionary)["roughness"])
            if material.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED \
                    and absf(material.roughness - guessed) < absf(material.roughness - wanted):
                problems.append(
                    "%s: %s is opaque, named as %s, and built at roughness %.3f (the %s class) rather than %.3f"
                    % [terrain.name, name, by_name, material.roughness, by_name, wanted]
                )
    if found < MIN_FOUND:
        return fail("no opaque surface named as glass or a lamp on any shipped terrain: nothing to check", found)
    if not problems.is_empty():
        return fail(
            "%d of %d opaque surfaces named as glass or a lamp are built as one: %s"
            % [problems.size(), found, "; ".join(problems.slice(0, LISTED))], problems.size()
        )
    return ok(
        "%d opaque surfaces named as glass or a lamp, every one built at its default class; e.g. %s"
        % [found, "; ".join(named)], found
    )
