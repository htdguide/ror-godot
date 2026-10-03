extends GateBase
## No stretch of a terrain's procedural road is buried in the ground it runs over.
##
## **The deck's height and the ground's height come from different files and neither was written
## against the other.** A `.tobj` gives a road as a spline of points the author laid down; the
## heightmap is the terrain's own. Where the two disagree the road wins or the hill does, and
## where the hill wins there is no road to see. Port Starling had 16 deck corners under its own
## terrain, the worst 0.58 m down.
##
## **Bridges and monorails are exempt and have to be.** Being above the ground is what they are
## for, and a rule that pushed every road up to the heightmap would drop a bridge onto the valley
## it spans.
##
## **Shoulders are exempt too, and that is not a loophole.** A road cut into a slope has its
## uphill shoulder in the hill — that is what a cutting is, and `RoadSection.foot` already meets
## the ground deliberately. Only the deck, the part a vehicle drives on and an eye sees, is held
## above the terrain. Measuring every vertex instead reports 789 below ground on a correct road
## and says nothing at all.
##
## **And a deck buried deeper than the builder will lift is counted, not failed.** The builder
## corrects up to `RoadSection.MAX_LIFT_M`, which covers a spline laid close to the ground and
## missing it. North St Helens has 87 road points wanting more than 5 m and one wanting 148.9 m;
## that is not a road that sank into a hillside, it is a road and a heightmap that disagree about
## where the world is, and hoisting it onto the mountain would hide the question rather than
## answer it. So the gate holds the builder to what it claims to do and reports the rest as a
## number somebody has to explain.

## How far under the ground a deck corner may sit before it counts as buried. Well under the
## clearance the builder lifts to, so this measures the rule rather than restating it.
const TOLERANCE_M: float = 0.02
## Below this a terrain has no procedural road to judge.
const MIN_CORNERS: int = 20
const LISTED: int = 6


static func meta() -> Dictionary:
    return {
        "name": "a_road_rests_on_the_ground_it_crosses",
        "proves": (
            "every deck corner of every flat, left, right or both road on every terrain in the"
            + " library is at or above the terrain under it"
        ),
        "oracle": GateBase.ORACLE_COMPUTED,
        "threshold": (
            "no deck corner between 2 cm and RoadSection.MAX_LIFT_M below the heightmap"
            + " beneath it; deeper than that is counted and reported"
        ),
        "why": (
            "a road's height is the author's spline and the ground's is a heightmap, and neither"
            + " was written against the other. Where the hill wins there is no road to see, and"
            + " a buried road looks exactly like a road nobody placed."
        ),
        "budget_s": 120.0,
        "needs_gpu": false,
        "milestone": "C2",
    }


func run(_harness: Node) -> Dictionary:
    var corners: int = 0
    var terrains: int = 0
    var worst: float = 0.0
    var unexplained: int = 0
    var deepest: float = 0.0
    var problems: PackedStringArray = PackedStringArray()
    for summary: Dictionary in RorTerrainLibrary.summaries():
        if (summary["error"] as String) != "":
            continue
        var loaded: Dictionary = RorTerrainLibrary.load_named(summary["name"] as String)
        if (loaded.get("error", "") as String) != "":
            continue
        var terrain: RorTerrain = loaded["terrain"] as RorTerrain
        var here: int = 0
        for group: Array in RorProceduralRoad.groups(terrain):
            for raw: Dictionary in group:
                var point: Dictionary = RoadSection.resolved(terrain, raw)
                if RoadSection.RAISED.has(point["kind"]):
                    continue
                # A section the builder refuses to touch is a mismatch, not a near miss, and
                # the question for it is not whether its corners clear the ground.
                if RoadSection.lift_wanted(terrain, point) > RoadSection.MAX_LIFT_M:
                    unexplained += 1
                    deepest = maxf(deepest, RoadSection.lift_wanted(terrain, point))
                    here += 2
                    continue
                var section: PackedVector3Array = RoadSection.points(terrain, point)
                # 3 and 4 are the deck's own edges: between them is what a vehicle drives on.
                for index: int in [3, 4]:
                    here += 1
                    var corner: Vector3 = section[index]
                    var under: float = terrain.height_at_world(corner.x, corner.z) - corner.y
                    if under <= TOLERANCE_M:
                        continue
                    worst = maxf(worst, under)
                    problems.append("%s: a %s deck corner is %.2f m under the ground at %s"
                        % [summary["name"], point["kind"], under, corner])
        corners += here
        if here > 0:
            terrains += 1

    if corners < MIN_CORNERS:
        return ok("skipped: %d road deck corners in this checkout" % corners, corners)
    if problems.size() > 0:
        return fail(
            "%d of %d deck corners are buried, the worst %.2f m: %s"
            % [problems.size(), corners, worst, "; ".join(problems.slice(0, LISTED))],
            problems.size()
        )
    return ok(
        "%d deck corners across %d terrains, none more than %d cm under their own ground%s"
        % [corners, terrains, int(TOLERANCE_M * 100.0),
           "" if unexplained == 0 else
           "; %d sections want more than the %.1f m the builder will lift, the worst %.1f m,"
           % [unexplained, RoadSection.MAX_LIFT_M, deepest]
           + " and are left where their files put them"],
        corners
    )
