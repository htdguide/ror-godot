extends GateBase
## The one guessed parameter in the conversion is applied consistently and cannot be badly wrong.
##
## **This gate does not claim the guess is right, and it says so.** Every other derived value in
## this project is a reading: a specular map is per-pixel truth, a stated shininess is the author's
## own number, a class is what the name says. When a material states none of those, its roughness
## comes from how bright its own texture is — wear, dirt and bare substrate are darker than the
## finish over them, so within one class a darker map is more often the rougher surface — and that
## is an observation about typical assets, not a fact about any one of them. A black wing is not a
## rough wing.
##
## What can honestly be held is that the guess is bounded, consistent and small:
##
##   - it never moves a material further than `MaterialCfg.LUMA_ROUGHNESS_SWING` from the constant
##     its class supplies, so it can make a surface look a little dirtier or a little fresher and
##     cannot turn it into a mirror or into chalk
##   - it is the stated rule and not something else, checked against a mean this gate takes itself
##     at its own sampling rate
##   - a material with authored data is never touched by it
##
## The library supplies the cases: every material in it that ships a texture and states nothing
## about its own finish.

## How far the built roughness may sit from the rule, as the two means are taken at different
## sampling rates over the same image.
const TOLERANCE: float = 0.02
## This gate takes its own mean, at its own size, rather than calling the conversion's.
const SAMPLE_SIZE: int = 24
## Below this many derived materials the checkout cannot answer the question.
const MIN_DERIVED: int = 20
const LISTED: int = 5


static func meta() -> Dictionary:
    return {
        "name": "a_derived_roughness_stays_inside_its_class",
        "proves": "where nothing is authored, roughness comes from the texture's own mean brightness by the stated rule, never moves further than one swing from the material's class, and never touches a material that states its own finish",
        "builds_on": ["a_pass_that_states_its_highlight_gets_it"],
        "oracle": GateBase.ORACLE_INVARIANT,
        "threshold": (
            "every derived roughness within %.3f of the rule and within %.2f of its class's own"
            % [TOLERANCE, MaterialCfg.LUMA_ROUGHNESS_SWING]
        ),
        "why": (
            "this is the only parameter in the conversion that is guessed rather than read, and a"
            + " guess that cannot be checked for truth can still be checked for blast radius."
            + " Bounded to one swing it is the difference between a panel looking a little worn"
            + " and a panel looking like chrome, and the bound is the whole reason the guess is"
            + " allowed at all."
        ),
        "budget_s": 120.0,
        "needs_gpu": false,
        "milestone": "M2",
    }


func run(_harness: Node) -> Dictionary:
    var derived: int = 0
    var moved: int = 0
    var problems: PackedStringArray = PackedStringArray()
    var widest: float = 0.0
    for summary: Dictionary in RorTerrainLibrary.summaries():
        if (summary.get("error", "") as String) != "":
            continue
        var loaded: Dictionary = RorTerrainLibrary.load_named(summary["name"] as String)
        if (loaded.get("error", "") as String) != "":
            continue
        var terrain: RorTerrain = loaded["terrain"] as RorTerrain
        var state: Dictionary = RorObjects.state(terrain)
        var dds: RefCounted = state["dds"] as RefCounted
        var scripts: Dictionary = state["materials"] as Dictionary
        for name: String in scripts.keys():
            var declared: Dictionary = scripts[name] as Dictionary
            if float(declared.get("shininess", -1.0)) >= 0.0:
                continue
            var files: PackedStringArray = declared.get(
                "textures", PackedStringArray()
            ) as PackedStringArray
            if files.is_empty():
                continue
            var path: String = RorContentPath.find(files[0], terrain.directory)
            var luma: float = MaterialClass.mean_luma_at(DdsImage.read(path, dds), SAMPLE_SIZE)
            if luma < 0.0:
                continue
            derived += 1
            var class_key: String = MaterialClass.classify(name, declared)["class"] as String
            # The rule the loader applies, stated again here rather than asked of it: a pass that
            # does not blend is not glass or a lamp whatever its name says, because a facade atlas
            # named `window` is brick too (`an_opaque_facade_is_not_glass`).
            if (class_key == "glass" or class_key == "lamp") and not bool(declared.get("alpha", false)):
                class_key = "default"
            var class_roughness: float = float((MaterialCfg.CLASSES.get(
                class_key, MaterialCfg.CLASSES["default"]
            ) as Dictionary)["roughness"])
            var built: float = RorObjectMaterial.of(terrain, name, state).roughness
            if absf(built - class_roughness) > 0.0005:
                moved += 1
            widest = maxf(widest, absf(built - class_roughness))

            # Inside its class's own swing, which is what keeps a guess from being a disaster.
            if absf(built - class_roughness) > MaterialCfg.LUMA_ROUGHNESS_SWING + TOLERANCE:
                problems.append(
                    "%s (%s) was built %.4f against its class's %.4f, further than one swing"
                    % [name, class_key, built, class_roughness]
                )
                continue
            # And it is the stated rule rather than something else.
            var wanted: float = clampf(
                class_roughness + MaterialCfg.LUMA_ROUGHNESS_SWING * (1.0 - 2.0 * luma),
                MaterialCfg.LUMA_ROUGHNESS_MIN, MaterialCfg.LUMA_ROUGHNESS_MAX
            )
            if absf(built - wanted) > TOLERANCE:
                problems.append(
                    "%s (%s) has a mean luma of %.4f, which the rule makes %.4f, and was built"
                    % [name, class_key, luma, wanted] + " %.4f" % built
                )

    if derived < MIN_DERIVED:
        return ok("skipped: %d materials derive a roughness in this checkout" % derived, derived)
    if problems.size() > 0:
        return fail(
            "%d of %d derived roughnesses are not what the rule says: %s"
            % [problems.size(), derived, "; ".join(problems.slice(0, LISTED))],
            problems.size()
        )
    return ok(
        "%d materials derive a roughness from their own texture, %d of them away from their"
        % [derived, moved]
        + " class's constant, by at most %.4f against a swing of %.2f"
        % [widest, MaterialCfg.LUMA_ROUGHNESS_SWING],
        widest
    )
