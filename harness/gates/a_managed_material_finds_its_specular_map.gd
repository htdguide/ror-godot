extends GateBase
## A managed material's specular map is read from the slot its own effect puts it in.
##
## **The oracle is upstream's parser.** `RigDef_Parser.cpp`, `ParseManagedMaterials`:
##
##     managed_mat.diffuse_map = this->GetArgStr(2);
##     if (managed_mat.type == MESH_STANDARD || managed_mat.type == MESH_TRANSPARENT)
##     {
##         if (m_num_args > 3) { managed_mat.specular_map = this->GetArgManagedTex(3); }
##     }
##     else if (... FLEXMESH_STANDARD || ... FLEXMESH_TRANSPARENT)
##     {
##         if (m_num_args > 3) { managed_mat.damaged_diffuse_map = this->GetArgManagedTex(3); }
##         if (m_num_args > 4) { managed_mat.specular_map        = this->GetArgManagedTex(4); }
##     }
##
## A flexmesh row carries a damaged diffuse between the diffuse and the specular; a mesh row does
## not. Counted from the first texture the specular map is at index 2 for one and **1** for the
## other, and this project read 2 for both.
##
## **What that looked like.** Every `mesh_standard` material in the library lost its specular map
## and drew with the class default instead: the hero truck's rims, steering wheel, tacho, speedo
## and flares came out as flat matte shapes. Reported as "the rims are just black plate caps" —
## and the rim texture really is near-black, 128 x 64 of dark steel with two bolt heads, so the
## colour was right and the thing missing was the highlight that makes it metal.
##
## The gate reads each vehicle file itself rather than asking the parser, because the parser is
## what is under test.

## Below this there is nothing to judge: a fresh clone has no downloaded packs.
const MIN_DECLARED: int = 3
const LISTED: int = 8


## **It builds on nothing.** `builds_on` means "running this exercises that, at least as
## hard", and the graph stops running what it implies — so an edge that only records which
## gate came first is an edge that silently retires a gate. This one holds one slot of one row and classifies nothing.


static func meta() -> Dictionary:
    return {
        "name": "a_managed_material_finds_its_specular_map",
        "proves": "a managedmaterial that declares a specular map builds a material carrying it, whichever slot its effect puts it in",
        "oracle": GateBase.ORACLE_EXTERNAL,
        "threshold": "every declared specular map reaches the built material; mesh_* reads slot 1, flexmesh_* slot 2",
        "why": (
            "this project read slot 2 for both, so every mesh_standard material in the library"
            + " lost its specular map and drew with the class default: rims, steering wheel,"
            + " gauges and flares as flat matte shapes. The colour was right and the highlight"
            + " that makes it metal was missing."
        ),
        "budget_s": 180.0,
        "needs_gpu": true,
        "milestone": "C1",
    }


func run(_harness: Node) -> Dictionary:
    var dds: RefCounted = ClassDB.instantiate("DdsReader") as RefCounted
    var declared: int = 0
    var carried: int = 0
    var absent: int = 0
    var problems: PackedStringArray = PackedStringArray()
    for entry: Dictionary in RorVehicleLibrary.entries():
        var directory: String = entry["directory"] as String
        var truck: TruckParser = TruckParser.new()
        if truck.parse_file(directory.path_join(entry["file"] as String)) != "":
            continue
        for row: Dictionary in _rows_of(directory.path_join(entry["file"] as String)):
            var wanted: String = row["specular"] as String
            if wanted == "":
                continue
            declared += 1
            if not RorContentPath.has(wanted, directory):
                # A map the mod names and does not ship is a content gap, not a loader one.
                absent += 1
                continue
            var material: Material = MeshAssembler.material_for(
                row["name"] as String, truck, directory, dds, {}, {}
            )
            # Through `VehiclePaint` rather than off the material, because a coated surface is a
            # `ShaderMaterial` and a plain one is not, and which it is says nothing about whether
            # the mod's specular map reached it.
            if material != null and VehiclePaint.roughness_map(material) != null:
                carried += 1
                continue
            problems.append(
                "%s: %s declares %s as its specular map and the material carries none"
                % [entry["name"], row["name"], wanted]
            )

    if declared < MIN_DECLARED:
        return ok("skipped: %d specular maps declared in this checkout" % declared, declared)
    if problems.size() > 0:
        return fail(
            "%d of %d declared specular maps never reach the material: %s"
            % [problems.size(), declared, "; ".join(problems.slice(0, LISTED))],
            problems.size()
        )
    return ok(
        "%d managedmaterials declare a specular map and %d carry one%s"
        % [declared, carried,
           "" if absent == 0 else "; %d name a file the pack does not ship" % absent],
        carried
    )


## Each `managedmaterials` row of a vehicle file, as its own effect lays it out.
##
## Read here with four lines of its own rather than through `TruckParser`, because the question is
## whether the loader puts the specular map in the right place and the loader cannot be the
## witness to that.
func _rows_of(path: String) -> Array[Dictionary]:
    var out: Array[Dictionary] = []
    var section: String = ""
    for raw_line: String in RorText.read(path).split("\n"):
        var line: String = raw_line.get_slice(";", 0).strip_edges()
        if line.is_empty():
            continue
        var fields: PackedStringArray = (
            line.replace(",", " ").replace("\t", " ").split(" ", false)
        )
        if fields.size() == 1:
            section = fields[0].to_lower()
            continue
        if section != "managedmaterials" or fields.size() < 3:
            continue
        var effect: String = fields[1].to_lower()
        var slot: int = -1
        if effect.begins_with("flexmesh_"):
            slot = 4
        elif effect.begins_with("mesh_"):
            slot = 3
        var specular: String = ""
        if slot > 0 and fields.size() > slot and fields[slot] != "-":
            specular = fields[slot]
        out.append({"name": fields[0], "effect": effect, "specular": specular})
    return out
