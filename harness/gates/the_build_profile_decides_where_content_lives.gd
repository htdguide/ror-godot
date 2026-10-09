extends GateBase
## Two builds of one code: dev with its fixtures and shipped map, prod bundling nothing. One file
## decides which, and every content root follows it.
##
## The production build exists so that no vehicle or map with a licence this project cannot
## vouch for is ever inside the build: `mods/` and `maps/` at its root are the user's, and the
## submodule's shipped content is not read at all. That is only true if every place the code
## looks for content asks `BuildProfile` rather than naming a folder. So this holds three things.
## The profile text parses the way the shell's `tools/profile.sh` parses it, prod and dev and
## nonsense. Under prod the roots are `mods` and `maps`, nothing shipped, no default map; under
## dev the fixtures. And no source file outside `BuildProfile` names a content root, found by
## reading the source rather than by asking the libraries, which would only agree with themselves.

const LITERALS: PackedStringArray = ["assets/mods", "assets/terrains", "rigs-of-rods/content"]
## Where a content root may be named: the profile itself, and the harness fixtures a scenario
## drives (the hero is a development fixture; the production build has none).
const ALLOWED: PackedStringArray = [
    "game/config/build_profile.gd", "harness/drive_scenario.gd",
]
const SCANNED: PackedStringArray = ["game", "harness"]
const NOT_SCANNED: PackedStringArray = ["harness/gates", "harness/dev"]


static func meta() -> Dictionary:
    return {
        "name": "the_build_profile_decides_where_content_lives",
        "proves": "the profile file parses to prod or dev, prod looks in mods/ and maps/ with nothing bundled and no default map, dev looks in the fixtures, and no source outside BuildProfile names a content root",
        "builds_on": ["static_state"],
        "oracle": GateBase.ORACLE_INVARIANT,
        "threshold": "prod: roots mods,maps, shipped \"\", default map \"\"; dev: assets/mods,assets/terrains, the submodule, simple2; 0 content-root literals outside the allowed files",
        "why": (
            "the production build is the one with no licence it cannot vouch for inside it, and"
            + " that holds only while every lookup asks the profile. A folder named in one"
            + " loader is a vehicle shipped by accident."
        ),
        "budget_s": 20.0,
        "needs_gpu": false,
        "milestone": "M2",
    }


func run(_harness: Node) -> Dictionary:
    var problems: PackedStringArray = PackedStringArray()
    for pair: Array in [
        ['[build]\nprofile="prod"\n', "prod"], ["[build]\nprofile=prod\n", "prod"],
        ["[build]\nprofile=PROD\n", "prod"], ['[build]\nprofile="dev"\n', "dev"],
        ["", "dev"], ["nonsense = = =\n", "dev"], ["[build]\nprofile=staging\n", "dev"],
    ]:
        var got: String = BuildProfile.parse(pair[0] as String)
        if got != (pair[1] as String):
            problems.append("profile text %s parsed as %s, not %s" % [JSON.stringify(pair[0]), got, pair[1]])
    if BuildProfile.mod_roots_of("prod") != PackedStringArray(["mods", "maps"]):
        problems.append("prod mod roots are %s" % ",".join(BuildProfile.mod_roots_of("prod")))
    if BuildProfile.terrain_root_of("prod") != "maps":
        problems.append("prod terrain root is %s" % BuildProfile.terrain_root_of("prod"))
    if BuildProfile.shipped_root_of("prod") != "":
        problems.append("prod reads shipped content from %s" % BuildProfile.shipped_root_of("prod"))
    if BuildProfile.default_map_of("prod") != "":
        problems.append("prod opens on a bundled map: %s" % BuildProfile.default_map_of("prod"))
    if BuildProfile.mod_roots_of("dev") != PackedStringArray(["assets/mods", "assets/terrains"]):
        problems.append("dev mod roots are %s" % ",".join(BuildProfile.mod_roots_of("dev")))
    if BuildProfile.shipped_root_of("dev") != "vendor/rigs-of-rods/content":
        problems.append("dev reads shipped content from %s" % BuildProfile.shipped_root_of("dev"))
    if BuildProfile.default_map_of("dev") != "simple2":
        problems.append("dev opens on %s" % BuildProfile.default_map_of("dev"))
    # The libraries follow the profile that is on, whichever it is.
    var expected_vehicle_roots: PackedStringArray = PackedStringArray()
    for relative: String in BuildProfile.mod_roots():
        expected_vehicle_roots.append(SourceScan.repo_root().path_join(relative))
    if BuildProfile.shipped_root() != "":
        expected_vehicle_roots.append(SourceScan.repo_root().path_join(BuildProfile.shipped_root()))
    if RorVehicleLibrary.roots() != expected_vehicle_roots:
        problems.append("the vehicle library looks in %s" % ",".join(RorVehicleLibrary.roots()))
    if RorTerrainLibrary.roots()[0] != SourceScan.repo_root().path_join(BuildProfile.terrain_root()):
        problems.append("the terrain library looks in %s first" % RorTerrainLibrary.roots()[0])

    var named: PackedStringArray = PackedStringArray()
    var scanned: int = 0
    for dir: String in SCANNED:
        for path: String in SourceScan.find_files(SourceScan.repo_root().path_join(dir), ["gd"]):
            var relative: String = path.trim_prefix(SourceScan.repo_root() + "/")
            var skip: bool = ALLOWED.has(relative)
            for excluded: String in NOT_SCANNED:
                if relative.begins_with(excluded + "/"):
                    skip = true
            if skip:
                continue
            scanned += 1
            var text: String = FileAccess.get_file_as_string(path)
            for literal: String in LITERALS:
                var at: int = text.find(literal)
                while at >= 0:
                    var line_start: int = text.rfind("\n", at) + 1
                    var line: String = text.substr(line_start, text.find("\n", at) - line_start)
                    if not line.strip_edges().begins_with("#"):
                        named.append("%s names %s" % [relative, literal])
                        break
                    at = text.find(literal, at + 1)
    if not named.is_empty():
        problems.append("%d source files name a content root outside BuildProfile: %s" % [named.size(), "; ".join(named)])
    if not problems.is_empty():
        return fail("; ".join(problems), problems.size())
    return ok(
        "profile parses prod/dev/nonsense as it should; prod: mods,maps, nothing shipped, no default map; dev: the fixtures and simple2; this checkout is %s; %d source files name no content root"
        % [BuildProfile.name(), scanned], scanned
    )
