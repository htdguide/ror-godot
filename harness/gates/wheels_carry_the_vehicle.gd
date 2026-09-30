extends GateBase
## Checks that the lowest thing on the vehicle is the part that touches the ground.
##
## Ground contact acts on nodes; a person looks at the tyres. A `meshwheels2` row names
## two axle nodes and a tyre radius, and the nodes the tyre stands on are generated from
## that rather than written in the file. Generate none and the lowest node of the whole
## vehicle is an axle, so contact happens at the axle and the tyres are drawn buried: on
## the hero truck, 0.34 m of tyre below the ground it was resting on.
##
## The oracle is the vehicle's own geometry, not a reference image. Whatever rests on the
## ground has to be the lowest thing the vehicle draws, because that is what "resting on
## the ground" means.

const MOD_DIR: String = "assets/mods/ChevyS1023"
const TRUCK: String = "S10offroad.truck"
## Both rings are sampled at discrete angles and the two do not share a phase, so the
## lowest node and the lowest drawn point never coincide exactly. The hero truck measures
## 0.043 m. The bound is set to catch a missing tread ring, which is an error of a whole
## tyre radius, and not to police the sampling residue.
const MAX_GAP_M: float = 0.10
const MIN_WHEELS: int = 2


static func meta() -> Dictionary:
    return {
        "name": "wheels_carry_the_vehicle",
        "proves": "the nodes that take ground contact are at the tyres, not at the axles",
        "oracle": GateBase.ORACLE_COMPUTED,
        "threshold": "lowest node within %.2f m of the lowest drawn point" % MAX_GAP_M,
        "why": (
            "the thing resting on the ground must be the lowest thing drawn, which is a"
            + " property of the vehicle rather than of this renderer. Without the"
            + " generated tread the gap is a whole tyre radius and the vehicle is drawn"
            + " sunk into the ground, which no existing gate noticed: every one of them"
            + " measures nodes, and the nodes were resting correctly."
        ),
        "budget_s": 30.0,
        "needs_gpu": false,
        "milestone": "M1",
    }


func run(_harness: Node) -> Dictionary:
    var mod_dir: String = SourceScan.repo_root().path_join(MOD_DIR)
    if not DirAccess.dir_exists_absolute(mod_dir):
        return ok("skipped: hero asset not present at %s" % MOD_DIR, 0)
    var built: Dictionary = VehicleBuilder.build(mod_dir, TRUCK)
    if (built.get("error", "") as String) != "":
        return fail(built["error"] as String)
    var root: Node3D = built["root"] as Node3D
    var truck: TruckParser = built["truck"] as TruckParser
    if truck.wheels.size() < MIN_WHEELS:
        return fail("%d wheels, expected at least %d" % [truck.wheels.size(), MIN_WHEELS])

    var lowest_node: float = truck.nodes[0].y
    for node: Vector3 in truck.nodes:
        lowest_node = minf(lowest_node, node.y)
    var lowest_drawn: float = VehicleBuilder.world_bounds(root).position.y
    root.queue_free()

    var gap: float = lowest_node - lowest_drawn
    if not is_finite(gap):
        return fail("the vehicle's bounds are not finite", gap)
    if absf(gap) > MAX_GAP_M:
        var where: String = "above" if gap > 0.0 else "below"
        return fail(
            "the lowest node sits %.3f m %s the lowest drawn point, over the %.2f m"
            % [absf(gap), where, MAX_GAP_M]
            + " bound. Contact acts on nodes, so the vehicle will rest %.3f m out of"
            % absf(gap)
            + " position: %s" % (
                "tyres buried in the ground" if gap > 0.0 else "tyres hovering over it"
            ),
            gap
        )
    return ok(
        "%d wheels: lowest node %.3f m, lowest drawn point %.3f m, apart by %.3f m"
        % [truck.wheels.size(), lowest_node, lowest_drawn, absf(gap)],
        gap
    )
