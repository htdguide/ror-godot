extends GateBase
## The vehicle carries a reflection probe that encloses it.
##
## What this proves is placement and sizing, not appearance: a probe that is missing, that is
## the wrong size, or that is left updating every frame is a fault this catches, and whether
## the resulting reflection looks right is a question for a human session.
##
## Sizing is the part worth checking mechanically. A probe exactly the size of the bodywork
## captures nothing of the ground beneath it, which is most of what a car's lower panels
## reflect; one sized in world space rather than the vehicle's own would be correct only while
## the vehicle is facing the way it was built.

const MOD_DIR: String = "assets/mods/ChevyS1023"
const TRUCK: String = "S10offroad.truck"
## The probe must contain the whole vehicle, with room beneath it for the ground.
const MIN_MARGIN_M: float = 1.0
## And not be so large that it is reflecting the horizon into the door mirrors.
const MAX_MARGIN_M: float = 6.0


static func meta() -> Dictionary:
    return {
        "name": "actor_reflection_probe",
        "proves": "the built vehicle carries one reflection probe, enclosing its bodywork with room for the ground, at a low update rate",
        "oracle": GateBase.ORACLE_INVARIANT,
        "threshold": (
            "exactly 1 probe; it encloses the body by %.1f to %.1f m on every axis; update"
            % [MIN_MARGIN_M, MAX_MARGIN_M]
            + " mode is ONCE"
        ),
        "why": (
            "car paint and glass are defined by what they reflect, so a missing probe is a"
            + " material fault that looks like a shading fault. The size bound is the real"
            + " check: a probe fitted tightly to the bodywork reflects none of the ground"
            + " under it, which is most of what the lower panels show."
        ),
        "budget_s": 60.0,
        "needs_gpu": true,
        "milestone": "M2",
    }


func run(harness: Node) -> Dictionary:
    var mod_dir: String = SourceScan.repo_root().path_join(MOD_DIR)
    if not DirAccess.dir_exists_absolute(mod_dir):
        return ok("skipped: hero asset not present at %s" % MOD_DIR, 0)
    var err: String = harness.setup_for("hero_3q")
    if err != "":
        return fail(err)

    var built: Dictionary = VehicleBuilder.build(mod_dir, TRUCK)
    if (built.get("error", "") as String) != "":
        return fail(built["error"] as String)
    var root: Node3D = built["root"] as Node3D
    harness.world.add_child(root)

    var probes: Array[Node] = []
    for child: Node in root.get_children():
        if child is ReflectionProbe:
            probes.append(child)
    if probes.size() != 1:
        return fail(
            "the vehicle carries %d reflection probes, expected exactly 1" % probes.size(),
            probes.size()
        )
    var probe: ReflectionProbe = probes[0] as ReflectionProbe
    if probe.update_mode != ReflectionProbe.UPDATE_ONCE:
        return fail(
            "the probe updates every frame: six faces of scene rendering for a reflection"
            + " nobody is inspecting while the vehicle moves"
        )

    # Both in the root's own space. Comparing a local box against world bounds would compare
    # a box with the axis-aligned box around a rotated box, which is a different shape.
    var body: AABB = ActorProbe.local_bounds(root)
    var box: AABB = AABB(probe.position - probe.size * 0.5, probe.size)
    if not box.encloses(body):
        return fail(
            "the probe's box %v..%v does not enclose the bodywork %v..%v"
            % [box.position, box.end, body.position, body.end]
        )
    var low: Vector3 = body.position - box.position
    var high: Vector3 = box.end - body.end
    var smallest: float = minf(low.x, minf(low.y, minf(low.z, minf(high.x, minf(high.y, high.z)))))
    var largest: float = maxf(low.x, maxf(low.y, maxf(low.z, maxf(high.x, maxf(high.y, high.z)))))
    if smallest < MIN_MARGIN_M:
        return fail(
            "the probe clears the bodywork by only %.2f m at its tightest: it will reflect"
            % smallest
            + " none of the ground under the vehicle",
            smallest
        )
    if largest > MAX_MARGIN_M:
        return fail(
            "the probe extends %.2f m past the bodywork at its loosest" % largest, largest
        )
    return ok(
        "1 probe, %.1f x %.1f x %.1f m around a %.1f x %.1f x %.1f m body, clearing it by"
        % [box.size.x, box.size.y, box.size.z, body.size.x, body.size.y, body.size.z]
        + " %.2f to %.2f m, updating once" % [smallest, largest],
        smallest
    )
