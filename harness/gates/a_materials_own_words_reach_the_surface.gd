extends GateBase
## Everything a `.material` script states about a surface reaches it: its texture, however the
## script names it, and its colour when it names no texture at all.
##
## **The oracle is upstream's own managed-material templates**, which are in this checkout:
## `resources/managed_materials/managed_mats.material` declares
##
##     abstract material RoR/Managed_Mats/Base
##     {
##         technique BaseTechnique: Shadows/managed/base_receiver
##         {
##             pass BaseRender
##             {
##                 texture_unit Diffuse_Map
##                 {
##                     texture_alias diffuse_tex
##                 }
##             }
##         }
##     }
##
## A leaf material inherits that and fills the hole: `material tracks/master:
## RoR/Managed_Mats/Base { set_texture_alias diffuse_tex master.dds }`. There is no `texture` line
## anywhere in it, and a reader that only knows `texture` sees a material with no texture. The
## alias name is not this project's convention — it is written in the template, in upstream's own
## files, and this gate reads it from there rather than asserting it.
##
## **Why both halves are one gate.** They are the same mistake: the loader had one way of learning
## what a surface draws and painted everything else a placeholder grey. 23 materials in this
## checkout are textured only through the alias, `tracks/master` among them. Another 18 carry no
## texture by design and state a colour instead — Starling Island's `rey_si_dark` is 0.13 grey and
## drew at 0.72, five and a half times too bright, which is a large part of what "the map is all
## white" looked like from the driver's seat. A flat colour is not a missing texture, and a
## material a script fully describes must not come out as a guess.
##
## What this gate does not do is look at pixels. That a textured object is textured on screen is
## `ror_terrain_objects_are_placed`; this one holds the step before it, where a script's own words
## are turned into a material, and it is the step where both faults lived.

## Where upstream's templates are, relative to the base resources.
const TEMPLATE_DIRECTORY: String = "managed_materials"
## The alias this gate expects the templates to bind the diffuse texture unit to. Checked against
## the templates rather than trusted: if upstream renames it, this gate says so instead of
## quietly passing.
const DIFFUSE_ALIAS: String = "diffuse_tex"
## Below this there is nothing to judge and the gate skips: a fresh clone has no downloaded packs,
## though the pinned submodule alone carries well over this.
const MIN_ALIASED: int = 5


## **It builds on nothing.** `builds_on` means "running this exercises that, at least as
## hard", and the graph stops running what it implies — so an edge that only records which
## gate came first is an edge that silently retires a gate. This one reads material scripts and builds no terrain objects.


static func meta() -> Dictionary:
    return {
        "name": "a_materials_own_words_reach_the_surface",
        "proves": "a material textured only through a managed-material alias gets its texture, and one that states a colour instead of a texture is painted that colour",
        "oracle": GateBase.ORACLE_EXTERNAL,
        "threshold": (
            "every leaf material that sets the `%s` alias resolves that file as its first"
            % DIFFUSE_ALIAS
            + " texture, and every textureless material declaring a diffuse colour is painted it"
        ),
        "why": (
            "the loader knew one way to learn what a surface draws, `texture`, and painted"
            + " everything else a placeholder grey. 23 materials here are textured only through"
            + " the alias and 18 more state a colour and no texture: Starling Island's"
            + " rey_si_dark is 0.13 grey and drew at 0.72, five and a half times too bright."
        ),
        "budget_s": 60.0,
        "needs_gpu": false,
        "milestone": "C2",
    }


func run(_harness: Node) -> Dictionary:
    var base: String = SourceScan.repo_root().path_join(RorContentPath.BASE_ROOT)
    var aliases: PackedStringArray = _template_aliases(base.path_join(TEMPLATE_DIRECTORY))
    if aliases.is_empty():
        return fail("upstream's managed-material templates declare no texture_alias at all")
    if not aliases.has(DIFFUSE_ALIAS):
        return fail(
            "upstream's templates bind %s, not `%s`: the alias this loader reads is no longer"
            % [", ".join(aliases), DIFFUSE_ALIAS] + " the one the content sets"
        )

    var problems: PackedStringArray = PackedStringArray()
    var aliased: int = 0
    var coloured: int = 0
    var other_aliases: Dictionary = {}
    for directory: String in _material_directories(base):
        var declared: Dictionary = OgreMaterial.read_directory(directory)
        for file: String in DirAccess.get_files_at(directory):
            if file.get_extension().to_lower() != "material":
                continue
            for stated: Dictionary in _stated_in(directory.path_join(file)):
                var name: String = stated["material"] as String
                var entry: Dictionary = declared.get(name, {}) as Dictionary
                if entry.is_empty():
                    problems.append("%s: %s parsed to nothing" % [file, name])
                    continue
                if (stated["alias"] as String) != "":
                    if (stated["alias"] as String) != DIFFUSE_ALIAS:
                        other_aliases[stated["alias"]] = true
                        continue
                    aliased += 1
                    var textures: PackedStringArray = entry["textures"] as PackedStringArray
                    if textures.is_empty() or textures[0] != (stated["file"] as String):
                        problems.append(
                            "%s: %s sets %s %s and the loader reads %s"
                            % [file, name, DIFFUSE_ALIAS, stated["file"],
                               "no texture" if textures.is_empty() else textures[0]]
                        )
                    continue
                coloured += 1
                if not (entry["has_diffuse"] as bool):
                    problems.append(
                        "%s: %s states a diffuse colour and the loader did not read one"
                        % [file, name]
                    )
                elif not (entry["diffuse"] as Color).is_equal_approx(stated["colour"] as Color):
                    problems.append(
                        "%s: %s states %v and the loader read %v"
                        % [file, name, stated["colour"], entry["diffuse"]]
                    )

    if aliased < MIN_ALIASED:
        return ok("skipped: %d aliased materials in this checkout" % aliased, aliased)
    if problems.size() > 0:
        return fail(
            "%d materials do not reach the surface as their script states: %s"
            % [problems.size(), "; ".join(problems)],
            problems.size()
        )
    return ok(
        "%d materials textured only through the `%s` alias resolve it, %d textureless materials"
        % [aliased, DIFFUSE_ALIAS, coloured]
        + " are painted their own diffuse colour%s"
        % ("" if other_aliases.is_empty() else
           "; %d other alias names in this content are not read: %s"
           % [other_aliases.size(), ", ".join(PackedStringArray(other_aliases.keys()))]),
        aliased + coloured
    )


## The alias names upstream's abstract templates bind a texture unit to.
func _template_aliases(directory: String) -> PackedStringArray:
    var out: PackedStringArray = PackedStringArray()
    for file: String in DirAccess.get_files_at(directory):
        if file.get_extension().to_lower() != "material":
            continue
        var in_unit: bool = false
        for raw_line: String in RorText.read(directory.path_join(file)).split("\n"):
            var line: String = RorText.strip_comment(raw_line).strip_edges()
            if line.begins_with("texture_unit"):
                in_unit = true
                continue
            if line.begins_with("}"):
                in_unit = false
                continue
            if in_unit and line.begins_with("texture_alias"):
                var words: PackedStringArray = line.split(" ", false)
                if words.size() > 1 and not out.has(words[1]):
                    out.append(words[1])
    return out


## Every directory holding `.material` scripts: the base resources and every pack on the disk.
func _material_directories(base: String) -> PackedStringArray:
    var out: PackedStringArray = PackedStringArray()
    for directory: String in RorContentPath.BASE_DIRECTORIES:
        out.append(base.path_join(directory))
    for root: String in RorVehicleLibrary.CONTENT_ROOTS:
        var path: String = SourceScan.repo_root().path_join(root)
        for pack: String in DirAccess.get_directories_at(path):
            out.append(path.path_join(pack))
    return out


## What a script states about each of its materials, read independently of the loader: either the
## file it sets the diffuse alias to, or the colour it is painted when it names no texture.
##
## Read here with its own small parser rather than through `OgreMaterial`, because the thing under
## test is `OgreMaterial`, and a gate that asks the reader what the file says can only ever agree
## with it.
func _stated_in(path: String) -> Array[Dictionary]:
    var out: Array[Dictionary] = []
    var name: String = ""
    var alias: String = ""
    var aliased_file: String = ""
    var colour: Color = Color.WHITE
    var has_colour: bool = false
    var has_texture: bool = false
    for raw_line: String in RorText.read(path).split("\n"):
        var line: String = RorText.strip_comment(raw_line).strip_edges()
        var words: PackedStringArray = line.split(" ", false)
        if words.is_empty():
            continue
        if words[0].to_lower() == "material" and words.size() > 1:
            _close(out, name, alias, aliased_file, colour, has_colour, has_texture)
            name = line.substr(9).get_slice(":", 0).strip_edges()
            alias = ""
            aliased_file = ""
            colour = Color.WHITE
            has_colour = false
            has_texture = false
            continue
        if words[0].to_lower() == "abstract":
            # A template states nothing about a surface; a leaf fills it in.
            _close(out, name, alias, aliased_file, colour, has_colour, has_texture)
            name = ""
            continue
        match words[0].to_lower():
            "texture", "anim_texture":
                has_texture = true
            "set_texture_alias":
                if words.size() > 2:
                    alias = words[1]
                    aliased_file = words[2]
            "diffuse":
                if words.size() > 3 and words[1].is_valid_float():
                    colour = Color(
                        words[1].to_float(), words[2].to_float(), words[3].to_float(),
                        words[4].to_float() if words.size() > 4 else 1.0
                    )
                    has_colour = true
    _close(out, name, alias, aliased_file, colour, has_colour, has_texture)
    return out


## Records the material just finished, when it states something this gate can check.
func _close(
    out: Array[Dictionary], name: String, alias: String, aliased_file: String,
    colour: Color, has_colour: bool, has_texture: bool
) -> void:
    if name.is_empty():
        return
    if alias != "":
        out.append({"material": name, "alias": alias, "file": aliased_file, "colour": colour})
        return
    if has_colour and not has_texture:
        out.append({"material": name, "alias": "", "file": "", "colour": colour})
