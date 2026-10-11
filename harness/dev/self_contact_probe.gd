extends SceneTree
## Where a rig's self-collision acts: contacts per phase of `a_recovered_rig_is_whole`'s script,
## and which beam breaks, with whether its nodes are contacters or collision-triangle corners.
##
##   godot --path . --headless --script res://harness/dev/self_contact_probe.gd [-- off]

func _initialize() -> void:
    var mod_dir: String = SourceScan.repo_root().path_join("assets/mods/ChevyS1023")
    var rig: Dictionary = RigBuilder.from_file(mod_dir, "S10offroad.truck", 0.0)
    var truck: TruckParser = rig["truck"] as TruckParser
    var solver: RefCounted = rig["solver"] as RefCounted
    if OS.get_cmdline_user_args().has("off"):
        solver.set_self_collision(false)
    solver.set_ground(0.0, true)
    RigBuilder.place(solver, truck, Vector3.ZERO, 0.0, DriveCfg.SPAWN_HEIGHT_M)
    var on_triangle: Dictionary = {}
    for node: int in truck.submeshes.cab_triangles:
        on_triangle[node] = true
    var phases: Array = [["settle", 2.0, 0.0], ["drive", 6.0, 0.8]]
    for phase: Array in phases:
        var before: int = solver.self_contact_count()
        if (phase[2] as float) > 0.0:
            solver.start_engine()
            solver.set_gear_selector(1)
        solver.set_throttle(phase[2] as float)
        for _f: int in int((phase[1] as float) * 60.0):
            solver.step(0.0005, 33)
        print("%s: %d self-contacts, %d broken" % [phase[0], solver.self_contact_count() - before, solver.broken_beam_count()])
    var positions: PackedVector3Array = solver.get_positions()
    var clearance: float = DriveCfg.RECOVER_CLEARANCE_M
    for arg: String in OS.get_cmdline_user_args():
        if arg.is_valid_float():
            clearance = arg.to_float()
    RigBuilder.place(solver, truck, ActorFrame.of(positions, truck.camera_nodes).origin,
        RigBuilder.heading_of(positions, truck.camera_nodes), clearance)
    solver.set_throttle(0.0)
    var before: int = solver.self_contact_count()
    for f: int in 240:
        solver.step(0.0005, 33)
        if f < 6 or f % 30 == 0:
            print("  recover frame %d: self-contacts so far %d, broken %d" % [f, solver.self_contact_count() - before, solver.broken_beam_count()])
    # Which contacter-triangle pairs are within range at the rest shape: a node already inside
    # one of its own triangles' padded prisms is pushed from the first substep.
    var rest: Dictionary = RigBuilder.build(truck, 0.0)
    var fresh: RefCounted = rest["solver"] as RefCounted
    var p: PackedVector3Array = fresh.get_positions()
    var tris: PackedInt32Array = truck.submeshes.cab_triangles
    var opts: PackedStringArray = truck.submeshes.cab_options
    var near_rest: int = 0
    for t: int in opts.size():
        if not opts[t].contains("c"):
            continue
        var o: Vector3 = p[tris[t * 3]]
        var a: Vector3 = p[tris[t * 3 + 1]]
        var b: Vector3 = p[tris[t * 3 + 2]]
        var u: Vector3 = a - o
        var v: Vector3 = b - o
        var n: Vector3 = u.cross(v).normalized()
        var m: Basis = Basis(u, v, n).inverse()
        for c: int in truck.contacters:
            if c == tris[t * 3] or c == tris[t * 3 + 1] or c == tris[t * 3 + 2]:
                continue
            var l: Vector3 = m * (p[c] - o)
            if l.x >= 0.0 and l.y >= 0.0 and 1.0 - l.x - l.y >= 0.0 and absf(l.z) <= 0.02:
                near_rest += 1
                if near_rest <= 6:
                    print("  at rest: contacter %d in triangle %d (%d %d %d) at %.4f m, bary %.3f %.3f" % [c, t, tris[t*3], tris[t*3+1], tris[t*3+2], l.z, l.x, l.y])
    print("at rest: %d contacter-in-own-triangle pairs" % near_rest)
    for beam: int in solver.beam_count():
        if solver.beam_broken(beam):
            var ends: Vector2i = solver.get_beam_nodes(beam)
            print("broken beam %d: nodes %d (%s%s) - %d (%s%s)" % [beam, ends.x,
                "contacter " if truck.contacters.has(ends.x) else "", "triangle" if on_triangle.has(ends.x) else "",
                ends.y, "contacter " if truck.contacters.has(ends.y) else "", "triangle" if on_triangle.has(ends.y) else ""])
    quit(0)
