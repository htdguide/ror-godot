extends GateBase
## A material that writes down how polished it is gets that, not its class's guess.
##
## **The legacy format says one thing about gloss and this is it.** An Ogre pass may write
##
##     specular <r> <g> <b> <shininess>
##
## and both halves are authored data: the exponent is the width of the Blinn-Phong highlight, and
## the colour is how strong it is. Everything else this project knows about a legacy surface's
## finish is a guess from its name. 31 lines in this checkout state one — a hall, a chapel, a tree
## set, Starling's structures — and until this gate existed every one of those materials was drawn
## with the roughness its *class* supplies instead of the number its author wrote.
##
## **Two oracles, and neither is this project's.** The expectation comes from the mod's own file,
## read here with four lines of string handling rather than through the parser under test, because
## a gate that asks the reader what the file says can only ever agree with it. And the conversion
## from an exponent to a roughness is Walter et al. (2007)'s equivalence between a Phong lobe and a
## microfacet one,
##
##     alpha = sqrt(2 / (n + 2))
##
## written out here independently of the implementation, with `alpha = roughness^2` as glTF and
## Godot both store it. So an exponent of 10 is a roughness of 0.639 and one of 33 is 0.489, and
## neither number was chosen by anybody.

## How close the built roughness has to be to the conversion. Floating point, not judgement.
const TOLERANCE: float = 0.001
## Below this many stated highlights the checkout cannot answer the question.
const MIN_STATED: int = 8
const LISTED: int = 5


static func meta() -> Dictionary:
    return {
        "name": "a_pass_that_states_its_highlight_gets_it",
        "proves": "every material whose .material script states a specular exponent is built with the roughness that exponent converts to, and with the highlight strength its specular colour states",
        "builds_on": ["a_materials_own_words_reach_the_surface"],
        "oracle": GateBase.ORACLE_EXTERNAL,
        "threshold": (
            "every stated exponent within %.4f of sqrt(2/(n+2)) squared back into a roughness,"
            % TOLERANCE + " over at least %d of them" % MIN_STATED
        ),
        "why": (
            "a class is what a material is guessed to be from its name; a specular line is what"
            + " its author wrote down. Reading one and ignoring the other is the whole difference"
            + " between a converter and a renderer that happens to draw something."
        ),
        "budget_s": 60.0,
        "needs_gpu": false,
        "milestone": "M2",
    }


func run(_harness: Node) -> Dictionary:
    var stated: int = 0
    var carried: int = 0
    var problems: PackedStringArray = PackedStringArray()
    var exponents: Dictionary = {}
    for summary: Dictionary in RorTerrainLibrary.summaries():
        if (summary.get("error", "") as String) != "":
            continue
        var loaded: Dictionary = RorTerrainLibrary.load_named(summary["name"] as String)
        if (loaded.get("error", "") as String) != "":
            continue
        var terrain: RorTerrain = loaded["terrain"] as RorTerrain
        var state: Dictionary = RorObjects.state(terrain)
        for row: Dictionary in _rows_of(terrain.directory):
            var name: String = row["material"] as String
            if not (state["materials"] as Dictionary).has(name):
                continue
            stated += 1
            exponents[row["shininess"]] = true
            var material: StandardMaterial3D = RorObjectMaterial.of(terrain, name, state)
            var wanted: float = _roughness_of(row["shininess"] as float)
            var wanted_specular: float = (row["colour"] as Color).get_luminance()
            if absf(material.roughness - wanted) > TOLERANCE:
                problems.append(
                    "%s states shininess %.1f, which is roughness %.4f, and was built %.4f"
                    % [name, row["shininess"], wanted, material.roughness]
                )
                continue
            if absf(material.metallic_specular - clampf(wanted_specular, 0.0, 1.0)) > TOLERANCE:
                problems.append(
                    "%s states a specular colour of %.3f luminance and was built %.3f"
                    % [name, wanted_specular, material.metallic_specular]
                )
                continue
            carried += 1

    if stated < MIN_STATED:
        return ok("skipped: %d materials state a specular exponent in this checkout" % stated, stated)
    if problems.size() > 0:
        return fail(
            "%d of %d stated highlights do not reach the surface: %s"
            % [problems.size(), stated, "; ".join(problems.slice(0, LISTED))],
            problems.size()
        )
    var said: PackedStringArray = PackedStringArray()
    for exponent: float in exponents.keys():
        said.append("%.1f is %.3f" % [exponent, _roughness_of(exponent)])
    said.sort()
    return ok(
        "%d materials state a specular exponent and all %d are built from it (%s)"
        % [stated, carried, ", ".join(said)],
        carried
    )


## The roughness a Blinn-Phong exponent converts to, written here from the published relation
## rather than called out of the code under test.
##
##   Walter, Marschner, Li & Torrance, *Microfacet Models for Refraction through Rough Surfaces*
##   (EGSR 2007), §5.2: a Phong lobe of exponent `n` matches a microfacet distribution of width
##   `alpha = sqrt(2 / (n + 2))`. glTF and Godot both store `alpha = roughness^2`.
func _roughness_of(shininess: float) -> float:
    var alpha: float = sqrt(2.0 / (maxf(shininess, 0.0) + 2.0))
    return clampf(
        sqrt(alpha), MaterialCfg.SHININESS_ROUGHNESS_MIN, MaterialCfg.SHININESS_ROUGHNESS_MAX
    )


## Every `specular` line in a directory's `.material` scripts, with the material it belongs to.
##
## Read with four lines of its own rather than through `OgreMaterial`, because the question is
## whether that reader puts the number where the renderer will find it.
func _rows_of(directory: String) -> Array[Dictionary]:
    var out: Array[Dictionary] = []
    var folder: DirAccess = DirAccess.open(directory)
    if folder == null:
        return out
    for file: String in folder.get_files():
        if file.get_extension().to_lower() != "material":
            continue
        var text: FileAccess = FileAccess.open(directory.path_join(file), FileAccess.READ)
        if text == null:
            continue
        var material: String = ""
        while not text.eof_reached():
            var line: String = text.get_line().strip_edges()
            if line.begins_with("//"):
                continue
            if line.to_lower().begins_with("material "):
                material = line.substr(9).get_slice(":", 0).strip_edges()
            elif line.to_lower().begins_with("specular ") and material != "":
                var words: PackedStringArray = line.split(" ", false)
                if words.size() > 4 and words[1].is_valid_float():
                    out.append({
                        "material": material,
                        "colour": Color(
                            words[1].to_float(), words[2].to_float(), words[3].to_float()
                        ),
                        "shininess": words[words.size() - 1].to_float(),
                    })
    return out
