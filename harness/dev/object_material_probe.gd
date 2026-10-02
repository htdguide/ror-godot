extends SceneTree
## Which of a terrain's object surfaces draw untextured, and what each of them asked for.
##
##   godot --headless --script res://harness/dev/object_material_probe.gd -- <terrain> [<terrain>...]
##
## `ror_terrain_objects_are_placed` counts textured objects and says nothing about the rest, so
## every investigation into a bare wall started by writing this script again. The answer wanted is
## never the count: it is the material name, and whether that name is undeclared, declared with no
## texture, or declared with a texture file nothing can find — three different faults that look
## identical on screen.
##
## Headless is fine: reading a mesh and resolving a material renders nothing.

## How many of the worst offenders to name before the list stops being readable.
const WORST: int = 12


func _initialize() -> void:
    for wanted: String in OS.get_cmdline_user_args():
        var loaded: Dictionary = RorTerrainLibrary.load_named(wanted)
        if (loaded.get("error", "") as String) != "":
            print("%s: ERROR %s" % [wanted, loaded["error"]])
            continue
        _report(wanted, loaded["terrain"] as RorTerrain)
    quit(0)


func _report(wanted: String, terrain: RorTerrain) -> void:
    var caches: Dictionary = RorObjects.state(terrain)
    var declared: Dictionary = caches["materials"] as Dictionary
    var reader: RefCounted = caches["reader"] as RefCounted
    var textured: int = 0
    # material name -> how many surfaces of it came out bare.
    var bare: Dictionary = {}
    var seen_meshes: Dictionary = {}
    # mesh file -> the material names of its own bare surfaces, so a half-textured building can
    # be named rather than counted.
    var by_mesh: Dictionary = {}
    # mesh file -> how many surfaces it has, textured or not.
    var surfaces: Dictionary = {}
    for placement: Dictionary in RorObjects.placements(terrain):
        var odef: Dictionary = RorObjects.definition(
            terrain, placement["name"] as String, caches
        )
        if (odef.get("error", "") as String) != "":
            continue
        # Drawn geometry only: a `beginmesh` hull is collision and is never rendered.
        for mesh_file: String in odef["meshes"] as PackedStringArray:
            if seen_meshes.has(mesh_file):
                continue
            seen_meshes[mesh_file] = true
            # The mesh is read here rather than taken from `RorObjects.mesh_of`, because a built
            # `StandardMaterial3D` does not remember the name it was asked to be and a submesh
            # with no geometry adds no surface — so surface index and submesh index diverge and
            # the bare surface cannot be traced back to what it asked for.
            var read: Dictionary = reader.read_file(
                RorContentPath.find(mesh_file, terrain.directory)
            )
            if (read.get("error", "") as String) != "":
                print("    unreadable: %s (%s)" % [mesh_file, read["error"]])
                continue
            for submesh: Dictionary in read["submeshes"] as Array:
                if (submesh["positions"] as PackedVector3Array).is_empty():
                    continue
                surfaces[mesh_file] = (surfaces.get(mesh_file, 0) as int) + 1
                var name: String = submesh["material"] as String
                # The loader's own material, so this reports what the game draws rather than
                # what this script thinks the game ought to draw.
                var material: StandardMaterial3D = RorObjects._material(terrain, name, caches)
                if material != null and material.albedo_texture != null:
                    textured += 1
                    continue
                bare[name] = (bare.get(name, 0) as int) + 1
                if not by_mesh.has(mesh_file):
                    by_mesh[mesh_file] = PackedStringArray()
                var listed: PackedStringArray = by_mesh[mesh_file] as PackedStringArray
                if not listed.has(name):
                    listed.append(name)
                    by_mesh[mesh_file] = listed

    var bare_total: int = 0
    for count: int in bare.values():
        bare_total += count
    print(
        "%s: %d distinct meshes, %d surfaces textured, %d bare across %d material names"
        % [wanted, seen_meshes.size(), textured, bare_total, bare.size()]
    )
    var names: Array = bare.keys()
    names.sort_custom(func(a: String, b: String) -> bool:
        return (bare[a] as int) > (bare[b] as int)
    )
    for index: int in mini(names.size(), WORST):
        var name: String = names[index] as String
        print("    %4d x  %-40s %s" % [bare[name], name, _why(name, terrain, declared)])
    if names.size() > WORST:
        print("    ... and %d more material names" % (names.size() - WORST))
    for mesh_file: String in by_mesh.keys():
        var listed: PackedStringArray = by_mesh[mesh_file] as PackedStringArray
        print(
            "    %-34s %d of %d surfaces bare: %s"
            % [mesh_file, listed.size(), surfaces.get(mesh_file, 0), ", ".join(listed)]
        )


## Why one material name came out with no texture, in the terms the loader itself works in.
func _why(name: String, terrain: RorTerrain, declared: Dictionary) -> String:
    var entry: Dictionary = declared.get(name, {}) as Dictionary
    if entry.is_empty():
        # The loader's last resort: Blender's Ogre exporter writes the texture into the material
        # name, so `Material.005/TEXFACE/asphaltshingles.dds` is its own declaration.
        entry = RorObjects._texface(name)
        if entry.is_empty():
            return "declared in no .material script this checkout can see"
    var textures: PackedStringArray = entry["textures"] as PackedStringArray
    if textures.is_empty():
        if entry["has_diffuse"] as bool:
            var colour: Color = entry["diffuse"] as Color
            return (
                "no texture by design, painted its own diffuse %.2f %.2f %.2f alpha %.2f"
                % [colour.r, colour.g, colour.b, colour.a]
            )
        return "declared, names neither a texture nor a colour"
    var missing: PackedStringArray = PackedStringArray()
    for file: String in textures:
        if not RorContentPath.has(file, terrain.directory):
            missing.append(file)
    if missing.is_empty():
        return "declared, texture %s found and still did not load" % textures[0]
    return "declared, texture file not installed: %s" % ", ".join(missing)
