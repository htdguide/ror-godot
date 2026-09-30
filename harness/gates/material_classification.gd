extends GateBase
## Checks that the hero vehicle's legacy materials are classified into the right surfaces.
##
## The expectations come from the mod itself — its declared transparency effects and its
## own material names — not from anything recorded by this project. A classifier that
## calls glass "glass" and tyres "rubber" is the whole difference between a renderer that
## can show metal and one that makes everything look like painted plastic.

const MOD_DIR: String = "assets/mods/ChevyS1023"
const TRUCK: String = "S10offroad.truck"
## Material name to the class it must be given. Chosen because each is unambiguous from
## the file: the two window materials are declared transparent, the wheel band is a tyre,
## the body carries the specular map.
const EXPECTED: Dictionary = {
    "S10windows": "glass",
    "S10windowsint": "glass",
    "S10wheelband": "rubber",
    "S1024": "car_paint",
}
## How many of the vehicle's materials must land on something other than the fallback.
## Below this the classifier is not earning its place.
const MIN_RECOGNISED: float = 0.75


static func meta() -> Dictionary:
    return {
        "name": "material_classification",
        "proves": "legacy materials are classified into surfaces using the mod's own declarations and names",
        "oracle": GateBase.ORACLE_EXTERNAL,
        "threshold": (
            "%d named materials classified exactly; at least %.0f%% of all materials recognised"
            % [EXPECTED.size(), MIN_RECOGNISED * 100.0]
        ),
        "why": (
            "the expectations are read out of the mod — what it declares transparent and"
            + " what it names its own surfaces — so this checks the classifier against"
            + " third-party data rather than against its own past output."
        ),
        "budget_s": 30.0,
        "needs_gpu": false,
        "milestone": "M2",
    }


func run(_harness: Node) -> Dictionary:
    var mod_dir: String = SourceScan.repo_root().path_join(MOD_DIR)
    if not DirAccess.dir_exists_absolute(mod_dir):
        return ok("skipped: hero asset not present at %s" % MOD_DIR, 0)

    var truck: TruckParser = TruckParser.new()
    var parse_error: String = truck.parse_file(mod_dir.path_join(TRUCK))
    if parse_error != "":
        return fail(parse_error)
    if truck.managed_materials.is_empty():
        return fail("%s declares no managedmaterials" % TRUCK)

    var classified: Dictionary = MeshAssembler.classify_materials(truck)
    var wrong: PackedStringArray = PackedStringArray()
    for material_name: String in EXPECTED.keys():
        if not classified.has(material_name):
            wrong.append("%s is not declared by the mod" % material_name)
            continue
        var got: String = (classified[material_name] as Dictionary)["class"] as String
        if got != EXPECTED[material_name]:
            wrong.append(
                "%s classified as %s, expected %s (%s)"
                % [
                    material_name, got, EXPECTED[material_name],
                    (classified[material_name] as Dictionary)["reason"]
                ]
            )
    if wrong.size() > 0:
        return fail("; ".join(wrong), wrong.size())

    var recognised: int = 0
    var report: PackedStringArray = PackedStringArray()
    for material_name: String in classified.keys():
        var entry: Dictionary = classified[material_name] as Dictionary
        if (entry["class"] as String) != "default":
            recognised += 1
        report.append("%s=%s" % [material_name, entry["class"]])
    var share: float = float(recognised) / float(classified.size())
    if share < MIN_RECOGNISED:
        return fail(
            "only %d of %d materials recognised (%.0f%%): %s"
            % [recognised, classified.size(), share * 100.0, ", ".join(report)],
            share
        )
    return ok(
        "%d of %d materials recognised: %s"
        % [recognised, classified.size(), ", ".join(report)],
        share
    )
