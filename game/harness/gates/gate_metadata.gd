extends GateBase
## Every gate must declare what it proves, against which oracle, at what threshold and
## why, inside what runtime budget. A gate without that metadata does not run.
##
## This gate also reports the suite's own debt: how many gates lean on a golden image
## rather than an outside oracle or a computed invariant. A growing golden count is the
## suite slowly becoming a record of its own past output instead of a test of the
## product, so it is measured continuously rather than noticed late.

const GATE_DIR: String = "res://harness/gates"
const MAX_GOLDEN_SHARE: float = 0.5


static func meta() -> Dictionary:
    return {
        "name": "gate_metadata",
        "proves": "every gate declares complete, valid metadata and the golden share stays bounded",
        "oracle": GateBase.ORACLE_INVARIANT,
        "threshold": "0 invalid gates; golden-oracle share <= %d%%" % int(MAX_GOLDEN_SHARE * 100.0),
        "why": (
            "a gate with no declared oracle or threshold cannot produce an actionable"
            + " failure, and an unbounded golden count turns the suite into a record of"
            + " its own past output rather than a test of the product."
        ),
        "budget_s": 10.0,
        "needs_gpu": false,
        "milestone": "M0",
    }


func run(_harness: Node) -> Dictionary:
    var dir: DirAccess = DirAccess.open(GATE_DIR)
    if dir == null:
        return fail("cannot open %s" % GATE_DIR)
    var offenders: PackedStringArray = PackedStringArray()
    var total: int = 0
    var golden: int = 0
    for file: String in dir.get_files():
        if not file.ends_with(".gd"):
            continue
        total += 1
        var gate_name: String = file.get_basename()
        var script: GDScript = load(GATE_DIR.path_join(file)) as GDScript
        var meta_dict: Dictionary = script.meta()
        var error: String = GateBase.validate_meta(meta_dict)
        if error != "":
            offenders.append("%s: %s" % [gate_name, error])
            continue
        if (meta_dict["name"] as String) != gate_name:
            offenders.append("%s: metadata name is '%s'" % [gate_name, meta_dict["name"]])
        if (meta_dict["oracle"] as String) == GateBase.ORACLE_GOLDEN:
            golden += 1
    if offenders.size() > 0:
        return fail("invalid gate metadata: " + ", ".join(offenders), offenders.size())
    if total == 0:
        return fail("no gates found in %s" % GATE_DIR)
    var share: float = float(golden) / float(total)
    if share > MAX_GOLDEN_SHARE:
        return fail(
            "%d of %d gates use a golden image (%.0f%%), over the %.0f%% cap"
            % [golden, total, share * 100.0, MAX_GOLDEN_SHARE * 100.0],
            share
        )
    return ok(
        "%d gates valid; %d use goldens (%.0f%%)" % [total, golden, share * 100.0], share
    )
