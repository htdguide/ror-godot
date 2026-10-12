extends GateBase
## The wheel step, traction control, the anti-lock brake, foot, hand and skid braking, the drive
## force on every tread node, the measured speed and the reaction on the suspension arm, is
## upstream's `Actor::CalcWheels`: compared rig by rig against the function compiled from the pinned
## submodule (`tools/build_parity.sh`).
##
## Traction control and ABS were not implemented at all, the skid brakes were not either, and the
## `braked` field was numbered wrongly (foot-only at 2, the skid brakes at 3 and 4, where upstream
## has the skid brakes at 2 and 3 and foot-only at 4), so a passenger car's foot-only front wheels
## took the handbrake. The arithmetic now follows upstream's order and Ogre 1.11's vector operations.
##
## Each rig: a chassis node whose velocity is the vehicle's, and two to four wheels of 4 to 8 rays
## placed and moving at random, with every braking kind and propulsion, torques, speeds, coefficients
## and both aids' pulses in random states, some wheels detached. The direction is handed to both;
## that it comes from the camera nodes is `DriveAidSetup`'s, and upstream's `getDirection`.

const ORACLE: String = "build/parity/upstream_oracle"
## The cases' inputs pass through decimal text, which alone leaves about 5e-9; one rounding done in
## another order (a float literal for upstream's double, a product grouped differently) is about
## 1e-7. The threshold sits between, so it sees the second.
const TOLERANCE_RELATIVE: float = 2e-8
const RIGS: int = 200
const NODE_MASS: float = 5.0
const DT: float = 0.0005


static func meta() -> Dictionary:
    return {
        "name": "the_wheel_pass_is_upstreams",
        "proves": "the wheel step gives upstream's CalcWheels forces, wheel speeds, braking, traction control and anti-lock states on the same rigs",
        "builds_on": [],
        "oracle": GateBase.ORACLE_EXTERNAL,
        "threshold": "%d rigs: every node force, wheel torque, speed, average, retorque, coefficient and rotation within %s, every aid's activity the same" % [RIGS, String.num_scientific(TOLERANCE_RELATIVE)],
        "why": "traction control, ABS and skid brakes were missing, a passenger car's front wheels took the handbrake, and the wheel step had never been run against upstream's.",
        "budget_s": 30.0,
        "needs_gpu": false,
        "milestone": "M1",
    }


func run(_harness: Node) -> Dictionary:
    var root: String = SourceScan.repo_root()
    if not FileAccess.file_exists(root.path_join(ORACLE)):
        return ok("skipped: the upstream oracle is not built. Run tools/build_parity.sh", 0)
    var rigs: Array[Dictionary] = _rigs()
    var lines: PackedStringArray = PackedStringArray()
    for rig: Dictionary in rigs:
        var nodes: Array = rig["nodes"]
        var wheels: Array = rig["wheels"]
        var g: Dictionary = rig["globals"]
        var d: Vector3 = g["direction"]
        lines.append("wheels %d %d" % [nodes.size(), wheels.size()])
        lines.append("globals %s %s %s %s %s %d %s %s %d" % [_n(d.x), _n(d.y), _n(d.z), _n(g["brake_force"]), _n(g["brake"]),
                1 if g["parking"] else 0, _n(g["handbrake"]), _n(g["steer"]), g["proped"]])
        var a: Array = rig["aids"]
        lines.append("aids %d %s %s %s %d %d %s %s %s %s %d" % [a[0], _n(a[1]), _n(a[2]), _n(a[4]), a[5], a[6], _n(a[7]),
                _n(a[8]), _n(a[9]), _n(a[10]), a[11]])
        for node: Dictionary in nodes:
            var p: Vector3 = node["position"]
            var v: Vector3 = node["velocity"]
            lines.append("node %s %s %s %s %s %s" % [_n(p.x), _n(p.y), _n(p.z), _n(v.x), _n(v.y), _n(v.z)])
        for w: Dictionary in wheels:
            lines.append("wheel %d %d %d %d %d %d %s %s %d %d %s %s %s %s %s %s %s %d" % [w["a"], w["b"], w["first"],
                    w["count"], w["arm"], w["near"], _n(w["radius"]), _n(NODE_MASS * float(w["count"])), w["brake"],
                    w["drive"], _n(w["torque"]), _n(w["speed"]), _n(w["avg"]), _n(w["last_torque"]),
                    _n(w["retorque"]), _n(w["tc_coef"]), _n(w["alb_coef"]), 1 if w["detached"] else 0])
    var path: String = root.path_join("build/parity/wheel_cases.txt")
    var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
    file.store_string("\n".join(lines) + "\n")
    file.close()
    var output: Array = []
    var status: int = OS.execute("/bin/sh", ["-c", "'%s' < '%s'" % [root.path_join(ORACLE), path]], output, true)
    if status != 0:
        return fail("the upstream oracle exited %d: %s" % [status, "\n".join(output)])
    var results: PackedStringArray = ("\n".join(output)).strip_edges().split("\n")

    var at: int = 0
    var worst: float = 0.0
    var counts: Dictionary = {"tc": 0, "abs": 0, "braked": 0}
    for r: int in RIGS:
        var rig: Dictionary = rigs[r]
        var ours: Dictionary = _ours(rig)
        var forces: PackedVector3Array = ours["forces"]
        for i: int in (rig["nodes"] as Array).size():
            var theirs: PackedStringArray = results[at].split(" ", false)
            at += 1
            for axis: int in 3:
                var difference: float = _difference(theirs[axis].to_float(), forces[i][axis])
                if difference > TOLERANCE_RELATIVE:
                    return fail("rig %d node %d force axis %d: upstream %s, ours %s" % [r, i, axis, theirs[axis], _n(forces[i][axis])], difference)
                worst = maxf(worst, difference)
        var wheel_values: PackedFloat32Array = ours["wheels"]
        for w: int in (rig["wheels"] as Array).size():
            var theirs: PackedStringArray = results[at].split(" ", false)
            at += 1
            for j: int in 7:
                var difference: float = _difference(theirs[j].to_float(), wheel_values[w * 7 + j])
                if difference > TOLERANCE_RELATIVE:
                    return fail("rig %d wheel %d (%s), %s: upstream %s, ours %s" % [r, w, rig["wheels"][w],
                            ["torque", "speed", "average speed", "retorque", "tc coef", "alb coef", "rotation"][j],
                            theirs[j], _n(wheel_values[w * 7 + j])], difference)
                worst = maxf(worst, difference)
        var totals: PackedStringArray = results[at].split(" ", false)
        at += 1
        for pair: Array in [[0, "spin"], [1, "speed"]]:
            var difference: float = _difference(totals[pair[0]].to_float(), float(ours[pair[1]]))
            if difference > TOLERANCE_RELATIVE:
                return fail("rig %d driven %s: upstream %s, ours %s" % [r, pair[1], totals[pair[0]], ours[pair[1]]], difference)
        if (totals[2] == "1") != bool(ours["tc_active"]) or (totals[3] == "1") != bool(ours["abs_active"]):
            return fail("rig %d: upstream tc %s abs %s, ours tc %s abs %s (%s)" % [r, totals[2], totals[3], ours["tc_active"], ours["abs_active"], rig])
        counts["tc"] += 1 if totals[2] == "1" else 0
        counts["abs"] += 1 if totals[3] == "1" else 0
    if counts["tc"] == 0 or counts["abs"] == 0:
        return fail("traction control acted on %d rigs and ABS on %d: the cases did not reach them" % [counts["tc"], counts["abs"]])
    return ok("%d rigs against upstream's CalcWheels, traction control acting on %d and ABS on %d; worst %s" % [
            RIGS, counts["tc"], counts["abs"], String.num_scientific(worst)], worst)


## The same rig in the solver, through its wheel step alone.
func _ours(rig: Dictionary) -> Dictionary:
    var solver: RefCounted = ClassDB.instantiate("RorSolver") as RefCounted
    for node: Dictionary in rig["nodes"] as Array:
        var index: int = solver.add_node(node["position"], NODE_MASS)
        solver.set_node_velocity(index, node["velocity"])
    var states: PackedFloat32Array = PackedFloat32Array()
    for w: Dictionary in rig["wheels"] as Array:
        solver.add_wheel(w["a"], w["b"], w["first"], w["count"], w["arm"], w["radius"], w["drive"], w["brake"])
        for value: float in [w["torque"], w["speed"], w["avg"], w["last_torque"], w["retorque"], w["tc_coef"], w["alb_coef"], 1.0 if w["detached"] else 0.0]:
            states.append(value)
    var g: Dictionary = rig["globals"]
    solver.set_brake_forces(g["brake_force"], g["handbrake"])
    solver.set_brake(g["brake"])
    solver.set_parking_brake(g["parking"])
    var a: Array = rig["aids"]
    var aids: PackedFloat32Array = PackedFloat32Array([a[0], a[1], a[2], a[3], a[4], a[5], a[6], a[7], a[8], a[9], a[10], a[11]])
    return solver.wheel_pass_probe(states, aids, g["direction"], g["steer"], DT)


func _rigs() -> Array[Dictionary]:
    var rng: RandomNumberGenerator = RandomNumberGenerator.new()
    rng.seed = 20261012
    var rigs: Array[Dictionary] = []
    for r: int in RIGS:
        var vehicle: Vector3 = Vector3(rng.randf_range(-20.0, 20.0), rng.randf_range(-1.0, 1.0), rng.randf_range(-20.0, 20.0))
        var nodes: Array[Dictionary] = [{"position": Vector3.ZERO, "velocity": vehicle}]
        var wheels: Array[Dictionary] = []
        var proped: int = 0
        for w: int in rng.randi_range(2, 4):
            var centre: Vector3 = Vector3(rng.randf_range(-2.0, 2.0), rng.randf_range(0.0, 1.0), rng.randf_range(-2.0, 2.0))
            var axis: Vector3 = Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(-0.3, 0.3), rng.randf_range(-1.0, 1.0)).normalized()
            var radius: float = rng.randf_range(0.25, 0.6)
            var spin: float = rng.randf_range(-40.0, 40.0)
            var a: int = nodes.size()
            nodes.append({"position": centre - axis * 0.12, "velocity": vehicle})
            nodes.append({"position": centre + axis * 0.12, "velocity": vehicle})
            var arm: int = nodes.size()
            nodes.append({"position": centre + Vector3(rng.randf_range(-0.6, 0.6), rng.randf_range(0.2, 0.5), rng.randf_range(-0.6, 0.6)), "velocity": vehicle})
            var rays: int = rng.randi_range(4, 8)
            var side: Vector3 = axis.cross(Vector3.UP).normalized()
            var first: int = nodes.size()
            for j: int in rays * 2:
                var angle: float = TAU * float(j) / float(rays * 2)
                var spoke: Vector3 = side.rotated(axis, angle) * radius * rng.randf_range(0.9, 1.05)
                var plane: Vector3 = centre + axis * (0.12 if j % 2 else -0.12)
                nodes.append({"position": plane + spoke, "velocity": vehicle + axis.cross(spoke) * spin + Vector3(rng.randf_range(-0.2, 0.2), 0.0, 0.0)})
            var drive: int = rng.randi_range(0, 2)
            proped += 1 if drive != 0 else 0
            var near: int = a if (nodes[a]["position"] as Vector3).distance_to(nodes[arm]["position"]) < (nodes[a + 1]["position"] as Vector3).distance_to(nodes[arm]["position"]) else a + 1
            wheels.append({
                "a": a, "b": a + 1, "first": first, "count": rays * 2, "arm": arm, "near": near, "radius": radius,
                "brake": rng.randi_range(0, 4), "drive": drive,
                "torque": rng.randf_range(-3000.0, 3000.0) if rng.randf() < 0.8 else 0.0,
                "speed": rng.randf_range(-30.0, 30.0), "avg": rng.randf_range(-30.0, 30.0),
                "last_torque": rng.randf_range(-3000.0, 3000.0), "retorque": rng.randf_range(-500.0, 500.0),
                "tc_coef": rng.randf_range(0.0, 1.0), "alb_coef": rng.randf_range(0.0, 1.0),
                "detached": rng.randf() < 0.1,
            })
        rigs.append({
            "nodes": nodes, "wheels": wheels,
            "globals": {
                "direction": Vector3(rng.randf_range(-1.0, 1.0), 0.0, rng.randf_range(-1.0, 1.0)).normalized(),
                "brake_force": rng.randf_range(1000.0, 6000.0), "brake": rng.randf_range(0.0, 1.0) if rng.randf() < 0.6 else 0.0,
                "parking": rng.randf() < 0.3, "handbrake": rng.randf_range(1000.0, 9000.0),
                "steer": rng.randf_range(-1.0, 1.0), "proped": proped,
            },
            # tc on, ratio, pulse_time, min_speed (unused), timer, state; then abs the same.
            "aids": [1 if rng.randf() < 0.7 else 0, rng.randf_range(1.0, 20.0), [0.0005, 0.002][rng.randi_range(0, 1)], 0.0,
                    rng.randf_range(0.0, 0.002), rng.randi_range(0, 1),
                    1 if rng.randf() < 0.7 else 0, rng.randf_range(1.0, 20.0), [0.0005, 0.002][rng.randi_range(0, 1)],
                    rng.randf_range(0.5, 5.0), rng.randf_range(0.0, 0.002), rng.randi_range(0, 1)],
        })
    return rigs


func _difference(theirs: float, ours: float) -> float:
    return absf(theirs - ours) / maxf(absf(theirs), 1.0)


func _n(value: float) -> String:
    return String.num_scientific(value)
