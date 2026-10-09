extends GateBase
## The grass refills around a moving vehicle a little per frame, never a hitch, and does fill.
##
## The worst frames of every drive were the grass: a 16 m move invalidated a row of tiles and the
## old rule built six of them in one call — six times 2.4 ms of GDScript, a 14 ms hitch on an
## 18 ms frame, measured by `the_frame_costs_what_each_feature_costs`. A call has a time budget
## now and builds nearest-first. This drives a focus across La Paz at 120 km/h in 60 Hz steps
## and holds two things: no call runs past the budget by more than one tile, and the ring is
## whole again within the frames a row of tiles takes at one a frame — a refill that never
## finishes is a different fault from a hitch, and quieter.

const MAP: String = "lapaz"
const SPEED_MPS: float = 33.0
const FRAME_S: float = 1.0 / 60.0
const FRAMES: int = 240
## One tile over the budget is the most a call may run on: the budget is checked after each.
const TILE_MS_ALLOWANCE: float = 4.0
## After the focus stops, this many frames at one tile each must whole the ring.
const SETTLE_FRAMES: int = 90


static func meta() -> Dictionary:
    return {
        "name": "grass_refills_within_its_frame_budget",
        "proves": "a vegetation focus moved at %.0f m/s builds grass tiles within the per-call budget plus one tile on every frame, and the ring is whole within %d frames of stopping" % [SPEED_MPS, SETTLE_FRAMES],
        "builds_on": ["the_frame_costs_what_each_feature_costs"],
        "oracle": GateBase.ORACLE_INVARIANT,
        "threshold": "every focus_on under %.1f + %.1f ms over %d frames; 0 tiles pending %d frames after stopping" % [RorVegetation.BUILD_BUDGET_MS, TILE_MS_ALLOWANCE, FRAMES, SETTLE_FRAMES],
        "why": (
            "a frame that builds six grass tiles is a 14 ms hitch on an 18 ms frame, and a drive"
            + " is judged by its worst frames; a refill that never completes is the other way"
            + " to be wrong."
        ),
        "budget_s": 120.0,
        "needs_gpu": false,
        "measured_is_wall_clock": true,
        "milestone": "M2",
    }


func run(_harness: Node) -> Dictionary:
    var loaded: Dictionary = RorTerrainLibrary.load_named(MAP)
    if (loaded.get("error", "") as String) != "":
        return ok("skipped: %s is not in this checkout" % MAP, 0)
    var terrain: RorTerrain = loaded["terrain"] as RorTerrain
    var vegetation: RorVegetation = RorVegetation.new()
    if vegetation.setup(terrain) != "":
        vegetation.free()
        return ok("skipped: %s grows nothing" % MAP, 0)
    var at: Vector3 = terrain.start_position()
    vegetation.focus_on(at)
    vegetation.fill()
    var worst: float = 0.0
    var over: int = 0
    var heading: Vector3 = Vector3(1.0, 0.0, 0.0)
    for _frame: int in FRAMES:
        at += heading * SPEED_MPS * FRAME_S
        var began: int = Time.get_ticks_usec()
        vegetation.focus_on(at)
        var ms: float = float(Time.get_ticks_usec() - began) / 1000.0
        worst = maxf(worst, ms)
        if ms > RorVegetation.BUILD_BUDGET_MS + TILE_MS_ALLOWANCE:
            over += 1
    var settled: int = -1
    for frame: int in SETTLE_FRAMES:
        vegetation.focus_on(at)
        if vegetation.pending() == 0:
            settled = frame
            break
    var pending: int = vegetation.pending()
    var planted: int = vegetation.planted()
    vegetation.free()
    if over > 0:
        return fail("%d of %d focus calls ran past the budget: worst %.1f ms against %.1f + %.1f" % [over, FRAMES, worst, RorVegetation.BUILD_BUDGET_MS, TILE_MS_ALLOWANCE], worst)
    if pending > 0:
        return fail("%d tiles still pending %d frames after the focus stopped" % [pending, SETTLE_FRAMES], pending)
    return ok("%d frames at %.0f m/s: worst focus_on %.1f ms against a %.1f ms budget; ring whole %d frames after stopping, %d plants" % [FRAMES, SPEED_MPS, worst, RorVegetation.BUILD_BUDGET_MS, settled, planted], worst)
