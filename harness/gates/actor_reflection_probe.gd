extends GateBase
## The vehicle carries a reflection probe that encloses it.
##
## What this proves is placement and sizing, not appearance: a probe that is missing, that is
## the wrong size, or that is left updating every frame is a fault this catches, and whether
## the resulting reflection looks right is a question for a human session.
##
## Sizing is the part worth checking mechanically, and **what this gate asked for used to be
## wrong.** It required a metre of clearance on every axis "so the probe captures the ground
## beneath it", which confuses two different things: a probe's box is the volume it *lights*,
## while what it *captures* is set by where it stands and `max_distance`. Godot applies a probe
## to every surface inside its box, so a metre of clearance handed it a ring of road and lit that
## road differently from the road beyond — a hard rectangle around the vehicle, reported twice
## from the window before any gate could see it. `the_actor_probe_does_not_tint_the_ground`
## measures the consequence; this one now asks for the opposite of what it used to.
##
## A small margin is still required, for a reason that is actually about the box: the vehicle is
## a soft body and it deforms, so a box fitted exactly to the rest shape would leave panels
## outside it the moment the rig bends. The ground reflection is guaranteed instead by checking
## the capture range, which is the thing that genuinely controls it.

const MOD_DIR: String = "assets/mods/ChevyS1023"
const TRUCK: String = "S10offroad.truck"
## Enough slack that a deforming rig stays inside its own box, and no more.
const MIN_MARGIN_M: float = 0.1
## And not so large that the box reaches past the vehicle into the road, which is the fault that
## produced a visible rectangle around it.
const MAX_MARGIN_M: float = 0.5
## How far the probe must be able to see, so the ground is in what it captures. This, and not the
## size of the box, is what puts the road into the vehicle's lower panels.
const MIN_CAPTURE_M: float = 10.0


static func meta() -> Dictionary:
    return {
        "name": "actor_reflection_probe",
        "proves": "the built vehicle carries one reflection probe that bounds its bodywork without reaching into the road, sees far enough to capture the ground, and updates once",
        "oracle": GateBase.ORACLE_INVARIANT,
        "threshold": (
            "exactly 1 probe; it encloses the body by %.1f to %.1f m on every axis; it captures"
            % [MIN_MARGIN_M, MAX_MARGIN_M]
            + " to at least %.0f m; update mode is ONCE" % MIN_CAPTURE_M
        ),
        "why": (
            "car paint and glass are defined by what they reflect, so a missing probe is a"
            + " material fault that looks like a shading fault. The size bound is the real"
            + " check, and it used to point the wrong way: a box bigger than the vehicle lights"
            + " the road inside it from a frozen capture, which is what put a rectangle around"
            + " the truck. The ground still reaches the lower panels, through the capture range."
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
    if probe.max_distance < MIN_CAPTURE_M:
        return fail(
            "the probe only sees %.1f m, so the ground is not in what it captures and the lower"
            % probe.max_distance + " panels have nothing to reflect",
            probe.max_distance
        )
    if smallest < MIN_MARGIN_M:
        return fail(
            "the probe clears the bodywork by only %.2f m at its tightest: a soft body deforms,"
            % smallest
            + " and panels that bend outside their own box lose their reflections mid-drive",
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
