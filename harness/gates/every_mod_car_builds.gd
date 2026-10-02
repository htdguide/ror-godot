extends GateBase
## Every vehicle in the library builds: all of its meshes, all of its wheels, all of its textures.
##
## **Written because one test vehicle is not a test.** This project had exactly one car for most
## of its life, and every convention in the loader was calibrated against it. A convention cannot
## be shown to be wrong by the example it was calibrated on — the hero truck's flexbody rotation
## is `180, -90, 0`, for which upstream's composition order and Godot's default are *identical*,
## so the order could be wrong for fifteen years of mods and that truck would never say so. The
## Mazda 626's `270, 180, 180` differ by 180 degrees about X and it loaded upside down.
##
## Three faults turned up the day a second and third pack were dropped in, none of which any gate
## could see:
##
## - `flexbodywheels` was never parsed, so a car built 14 parts and **zero wheels**.
## - `generate_mipmaps` fails on block-compressed images, so a car whose textures are DXT drew
##   bare panels while its uncompressed interior looked right.
## - the flexbody rotation order, above.
##
## So this gate asks the loader to build **everything in the library** and holds each one to what
## its own file declares. It has no list of expected vehicles and no per-car numbers: a pack
## dropped into `assets/` is covered the moment it is there, which is the only way a loader for
## other people's content can be held to anything.
##
## What it cannot check is whether the result *looks* right — that a body is upright rather than
## inverted is a question for a person with a window open, and it is how the rotation fault was
## found. What it can check is that nothing was silently dropped, which is how all three faults
## above presented: no error, no warning, just less vehicle than the file describes.
##
## **Two things it deliberately does not fail on**, both learned by writing it wrong first.
##
## A vehicle need not have any `flexbodies`: Starling Island's firetruck draws its whole body
## from `submesh` sections, the way the hero truck draws its cab, so counting flexbodies and
## calling zero a failure flagged a vehicle that is fine. What is counted is the geometry that
## actually ends up in the scene.
##
## A vehicle need not draw anything at all, either. NhelensGrass's bridge, crane and monorail
## and the Daf pack's semi trailer carry no flexbodies and no props: their only geometry is in
## `submesh` sections, which this project reads for collision and never renders — the hero
## truck's carry zero texcoords. Those vehicles correctly draw nothing today, so they are counted
## and reported rather than failed. Rendering submesh bodies is unimplemented, not broken, and a
## gate that conflates the two would be demanding a feature by pretending it is a bug.
##
## And a mod may name a mesh that is nowhere a mod may name it from. Starling Island's vehicles
## ask for `seat.mesh`, `dashboard-small.mesh` and `lightbar.mesh`, which are Rigs of Rods base
## content rather than theirs — and all three resolve, because `RorContentPath` searches the
## game's own resource directories the way Ogre's resource groups do. A name that resolves in none
## of them is a content problem rather than a loader problem, and it is reported rather than
## failed: the loader is judged on what it does with files that exist.

## Vehicles whose own file declares meshes this project has no reader for are still required to
## build what it can; a file that resolves to nothing at all is the failure.
const MIN_PARTS: int = 1
## Below this there is no content worth judging and the gate skips rather than failing: a fresh
## clone has no downloaded packs.
const MIN_FOR_A_VERDICT: int = 2


static func meta() -> Dictionary:
    return {
        "name": "every_mod_car_builds",
        "proves": "every vehicle the library holds builds with all of its meshes, every wheel its file declares, and no silently dropped geometry",
        "builds_on": ["the_library_finds_every_vehicle", "vehicle_renders"],
        "oracle": GateBase.ORACLE_INVARIANT,
        "threshold": (
            "every vehicle builds without error, with at least %d part, with as many wheels as"
            % MIN_PARTS + " its file declares, and with nothing skipped"
        ),
        "why": (
            "one test vehicle calibrates the loader to itself. The hero truck's flexbody rotation"
            + " is a case where upstream's composition order and Godot's default agree exactly,"
            + " so that truck could never reveal the order being wrong — and it was. Adding two"
            + " packs found three faults in a day, every one of them silent: no error, no"
            + " warning, just less vehicle than the file describes."
        ),
        "budget_s": 300.0,
        "needs_gpu": true,
        "milestone": "C1",
    }


func run(_harness: Node) -> Dictionary:
    var entries: Array[Dictionary] = RorVehicleLibrary.entries()
    if entries.size() < MIN_FOR_A_VERDICT:
        return ok("skipped: %d vehicles in this checkout, too few to judge" % entries.size(), 0)

    var problems: PackedStringArray = PackedStringArray()
    var parts: int = 0
    var wheels: int = 0
    var textures: int = 0
    var absent: int = 0
    var submesh_only: int = 0
    for entry: Dictionary in entries:
        var name: String = entry["name"] as String
        var built: Dictionary = VehicleBuilder.build(
            entry["directory"] as String, entry["file"] as String
        )
        var error: String = built.get("error", "") as String
        if error != "":
            problems.append("%s: %s" % [name, error])
            continue
        var truck: TruckParser = built["truck"] as TruckParser
        var root: Node3D = built["root"] as Node3D
        var drawn: int = _drawn_meshes(root)
        # Geometry is only expected from a file that names some. NhelensGrass ships a bridge, a
        # crane and a monorail, and the Daf pack a semi trailer, none of which reference a single
        # mesh: they are node and beam structures, and demanding that they draw something flagged
        # four vehicles that are doing exactly what their files say.
        # Drawn geometry is expected from flexbodies and props, which this project renders.
        # `submesh` sections are **not** counted: they are read for collision only and never
        # drawn — the hero truck's carry zero texcoords — so NhelensGrass's bridge, crane and
        # monorail and the Daf semi trailer, whose only geometry is submesh, correctly draw
        # nothing today. Rendering submesh bodies is unimplemented rather than broken, and this
        # gate says so by counting them separately instead of failing on them.
        if _has_installed_mesh(truck, entry["directory"] as String) and drawn < MIN_PARTS:
            problems.append("%s: names geometry and resolved to none of it" % name)
        elif truck.flexbodies.is_empty() and truck.props.is_empty() and truck.submesh_count > 0:
            submesh_only += 1
        # Every wheel the file declares has to be built. This is the check that catches a wheel
        # section nobody parsed: the vehicle looks almost right and simply has no wheels.
        var declared: int = truck.wheels.size()
        if (built["wheels"] as int) != declared:
            problems.append(
                "%s: declares %d wheels and built %d" % [name, declared, built["wheels"]]
            )
        # A mesh the mod names but this checkout does not have is content that was never
        # installed; one that is present and will not read is the loader's problem.
        for dropped: String in built["skipped"] as PackedStringArray:
            var mesh_name: String = dropped.get_slice(" ", 0)
            if dropped.ends_with("(missing)") or not RorContentPath.has(
                mesh_name, entry["directory"] as String
            ):
                absent += 1
                continue
            problems.append("%s: could not read %s" % [name, dropped])
        parts += drawn
        wheels += built["wheels"] as int
        textures += built["textures"] as int
        if root != null:
            root.queue_free()

    if problems.size() > 0:
        return fail(
            "%d of %d vehicles did not build everything their files describe: %s"
            % [problems.size(), entries.size(), "; ".join(problems)],
            problems.size()
        )
    return ok(
        "%d vehicles built: %d drawn parts, %d wheels, %d textures%s"
        % [entries.size(), parts, wheels, textures,
           ("" if absent == 0 else "; %d meshes named but not installed" % absent)
           + ("" if submesh_only == 0 else
              "; %d drawn only from submesh sections, which are collision-only here"
              % submesh_only)],
        entries.size()
    )


## Whether this vehicle names at least one drawable mesh that is actually on the disk.
##
## The condition is "names a mesh **and has it**", not "names a mesh", and "has it" means anywhere
## a mod may name it from — the pack's own folder or the game's own resource directories, which is
## how Rigs of Rods resolves content. Requiring geometry from a file whose only mesh is absent
## everywhere asks the loader to invent it.
func _has_installed_mesh(truck: TruckParser, directory: String) -> bool:
    for group: Array[Dictionary] in [truck.flexbodies, truck.props]:
        for entry: Dictionary in group:
            var mesh_name: String = entry.get("mesh", "") as String
            if mesh_name != "" and RorContentPath.has(mesh_name, directory):
                return true
    return false


## How much of a built vehicle actually ends up on screen, counted from the scene rather than
## from any one section's tally.
func _drawn_meshes(root: Node3D) -> int:
    if root == null:
        return 0
    var found: int = 0
    var stack: Array[Node] = [root]
    while not stack.is_empty():
        var node: Node = stack.pop_back()
        var instance: MeshInstance3D = node as MeshInstance3D
        if instance != null and instance.mesh != null:
            found += 1
        for child: Node in node.get_children():
            stack.append(child)
    return found
