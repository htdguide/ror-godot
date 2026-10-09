extends GateBase
## What an object draws is its header mesh. The hulls in its `beginmesh` blocks are collision.
##
## **The oracle is upstream's parser**, which puts them in different places —
## `source/main/resources/odef_fileformat/ODefFileFormat.cpp`:
##
##     else if (line_str == "endmesh")
##     {
##         m_def->collision_meshes.emplace_back(
##             m_ctx.cbox_mesh_name, m_ctx.header_scale, m_ctx.cbox_groundmodel_name);
##     }
##
## `m_def->header.mesh_name` is set once, from the positional header, and is the only thing the
## scene graph ever sees.
##
## **What reading them as geometry looked like.** 522 of Port Starling's 1189 object instances were
## hulls — `firehousebox.mesh`, `store02box.mesh`, `townhouse01box.mesh`, `haus5Kol.mesh`,
## `haus6Kol.mesh` — standing over the buildings they belong to as untextured shells: a house with
## no texture, or half of one where the hull covered part of it, and 44% of the map's object
## instances spent on geometry nobody should see. La Paz drew 99 of them, one per pole.
##
## Their materials are `Material.001`, `Material.004` and `default`, declared in no script, because
## nobody was ever meant to look at them. That is the trap this gate exists for: the symptom is an
## untextured surface, so the search goes looking for a missing texture, and the texture is missing
## because the surface should not be drawn at all.
##
## **A definition may collide with the mesh it draws**, and 133 in this checkout do:
## `40mrunway.odef` names `40mrunway.mesh` and then says `beginmesh / mesh 40mrunway.mesh`. One
## mesh in both roles is not a hull being drawn, and a first draft of this gate failed on all 133
## of them. What is checked is the hull that is nothing but a hull.
##
## This gate reads the files with its own small scan rather than through `Odef`, because `Odef` is
## the thing under test and a gate that asks the reader what the file says can only agree with it.

## Below this there is nothing to judge: a checkout with no object definitions.
const MIN_DEFINITIONS: int = 20


## **It builds on nothing.** `builds_on` means "running this exercises that, at least as
## hard", and the graph stops running what it implies — so an edge that only records which
## gate came first is an edge that silently retires a gate. This one sorts a definition's mesh lists and never asks whether the files exist.


static func meta() -> Dictionary:
    return {
        "name": "a_collision_hull_is_not_drawn",
        "proves": "an object's drawn geometry is its header mesh alone, and every mesh named inside a beginmesh block is collision instead",
        "oracle": GateBase.ORACLE_EXTERNAL,
        "threshold": "no mesh named inside a `beginmesh` block appears in the drawn set, and the drawn set is the header mesh",
        "why": (
            "522 of Port Starling's 1189 object instances were collision hulls drawn as scenery,"
            + " untextured shells over the buildings they belong to. Their materials are declared"
            + " in no script because nobody was meant to see them, so the symptom is a missing"
            + " texture and the cause is a surface that should not be drawn."
        ),
        "budget_s": 60.0,
        "needs_gpu": false,
        "milestone": "C2",
    }


func run(_harness: Node) -> Dictionary:
    var definitions: int = 0
    var hulls: int = 0
    var drawn: int = 0
    var problems: PackedStringArray = PackedStringArray()
    for directory: String in _definition_directories():
        for file: String in DirAccess.get_files_at(directory):
            if file.get_extension().to_lower() != "odef":
                continue
            var stated: Dictionary = _stated_in(directory.path_join(file))
            var read: Dictionary = Odef.read(directory.path_join(file))
            if (read["error"] as String) != "":
                continue
            definitions += 1
            var reads_drawn: PackedStringArray = read["meshes"] as PackedStringArray
            var reads_hulls: PackedStringArray = read["collision_meshes"] as PackedStringArray
            drawn += reads_drawn.size()
            hulls += reads_hulls.size()
            for hull: String in stated["hulls"] as PackedStringArray:
                if not reads_hulls.has(hull):
                    problems.append("%s names the hull %s and it is not collision" % [file, hull])
                    continue
                # A definition may collide with the very mesh it draws, and 133 here do:
                # `40mrunway.odef` is `40mrunway.mesh` with `beginmesh / mesh 40mrunway.mesh`
                # inside it. That is one mesh in both roles, not a hull being drawn. Only a hull
                # that is nothing but a hull is the fault.
                if hull != (stated["header"] as String) and reads_drawn.has(hull):
                    problems.append("%s draws %s, which is only a beginmesh hull" % [file, hull])
            var header: String = stated["header"] as String
            if header != "" and not reads_drawn.has(header):
                problems.append("%s draws %s rather than its header mesh %s"
                    % [file, ", ".join(reads_drawn), header])

    if definitions < MIN_DEFINITIONS:
        return ok("skipped: %d object definitions in this checkout" % definitions, definitions)
    if problems.size() > 0:
        return fail(
            "%d of %d object definitions mix collision with geometry: %s"
            % [problems.size(), definitions, "; ".join(problems)],
            problems.size()
        )
    return ok(
        "%d object definitions: %d drawn meshes and %d collision hulls, kept apart"
        % [definitions, drawn, hulls],
        hulls
    )


## Every directory an `.odef` may live in: the base resources and every pack on the disk.
func _definition_directories() -> PackedStringArray:
    var out: PackedStringArray = PackedStringArray()
    var base: String = SourceScan.repo_root().path_join(RorContentPath.BASE_ROOT)
    for directory: String in RorContentPath.BASE_DIRECTORIES:
        out.append(base.path_join(directory))
    for root: String in BuildProfile.mod_roots():
        var path: String = SourceScan.repo_root().path_join(root)
        for pack: String in DirAccess.get_directories_at(path):
            out.append(path.path_join(pack))
    return out


## The header mesh and the `beginmesh` hulls one file states, read here rather than through `Odef`.
##
## The header is positional: an obsolete bare `LOD` line may come first, then the mesh, then the
## scale. Everything after a `beginmesh` is that block's.
func _stated_in(path: String) -> Dictionary:
    var header: String = ""
    var hulls: PackedStringArray = PackedStringArray()
    var in_block: bool = false
    var header_done: bool = false
    for raw_line: String in RorText.read(path).split("\n"):
        var line: String = RorText.strip_comment(raw_line).strip_edges()
        if line.is_empty():
            continue
        if line == "beginmesh" or line == "beginbox":
            in_block = true
            header_done = true
            continue
        if line == "endmesh" or line == "endbox":
            in_block = false
            continue
        if in_block:
            if line.begins_with("mesh ") or line.begins_with("mesh\t"):
                var named: String = line.substr(line.find(" ") + 1).strip_edges()
                if named.to_lower() != "null.mesh" and not hulls.has(named):
                    hulls.append(named)
            continue
        if header_done or line == "LOD":
            continue
        if header.is_empty():
            if line.to_lower() != "null.mesh":
                header = line
            header_done = line.to_lower() == "null.mesh"
            continue
    return {"header": header, "hulls": hulls}
