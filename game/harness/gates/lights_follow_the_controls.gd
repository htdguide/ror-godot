extends GateBase
## Each lamp lights for its own reason: headlights with the switch, brake lights with the pedal,
## reversing lights with the gear, indicators with the stalk and the clock.
##
## Before this, every lamp on the vehicle came on together with the light switch — which looks
## right in a still photograph and is wrong in every other way. A brake light that is on whenever
## the headlights are is not a brake light, and an indicator that does not blink is a sidelight.
##
## The vehicle's own flare types are upstream's letters, read from its file; what is on when is
## this project's rule, and this gate is where that rule is written down as something checkable.
## So it drives the state rather than the lamps: press the pedal, select reverse, flick the stalk,
## and ask which lamps are emitting.

const MOD_DIR: String = "assets/mods/ChevyS1023"
const TRUCK: String = "S10offroad.truck"
## Half a blink period apart: an indicator has to be on at one of these and off at the other, or
## it is not blinking.
const BLINK_ON_S: float = 0.0
const BLINK_OFF_S: float = FlareBuilder.BLINK_PERIOD_S * 0.75


static func meta() -> Dictionary:
    return {
        "name": "lights_follow_the_controls",
        "proves": "headlights follow the switch, brake lights the pedal, reversing lights the gear, and indicators blink on the side that was asked for",
        # the lamps have to exist and face outward before what lights them can be checked.
        "builds_on": ["flares_face_outward"],
        "oracle": GateBase.ORACLE_INVARIANT,
        "threshold": "every lamp lit in the states its type is for, and dark in the others",
        "why": (
            "every lamp used to come on with the light switch, which photographs perfectly and"
            + " is wrong in every other way: a brake light that is on with the headlights is not"
            + " a brake light, and an indicator that does not blink is a sidelight."
        ),
        "budget_s": 60.0,
        "needs_gpu": true,
        "milestone": "M1",
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
    var truck: TruckParser = built["truck"] as TruckParser
    harness.world.add_child(built["root"] as Node3D)
    var lamps: Array[Node3D] = built["lamps"] as Array[Node3D]
    if lamps.is_empty():
        return fail("%s built no lamps: there is nothing to light" % TRUCK)

    var reported: PackedStringArray = PackedStringArray()
    # Each case is a state and what it should light, by upstream's own type letters.
    for case: Dictionary in [
        {
            "name": "everything off",
            "state": {},
            "lit": [],
        },
        {
            "name": "headlights",
            "state": {"headlights": true},
            "lit": [
                FlareRows.HEADLIGHT, FlareRows.HIGH_BEAM, FlareRows.FOG_LIGHT,
                FlareRows.TAIL_LIGHT, FlareRows.SIDELIGHT, FlareRows.DASHBOARD,
                FlareRows.BRAKE_LIGHT,
            ],
        },
        {
            "name": "on the brakes",
            "state": {"brake": 0.6},
            "lit": [FlareRows.BRAKE_LIGHT],
        },
        {
            "name": "in reverse",
            "state": {"reverse": true},
            "lit": [FlareRows.REVERSE_LIGHT],
        },
        {
            "name": "indicating left",
            "state": {"left": true, "seconds": BLINK_ON_S},
            "lit": [FlareRows.BLINKER_LEFT],
        },
        {
            "name": "indicating left, between blinks",
            "state": {"left": true, "seconds": BLINK_OFF_S},
            "lit": [],
        },
        {
            "name": "indicating right",
            "state": {"right": true, "seconds": BLINK_ON_S},
            "lit": [FlareRows.BLINKER_RIGHT],
        },
    ]:
        FlareBuilder.apply_state(lamps, truck, case["state"] as Dictionary)
        var wanted: Array = case["lit"] as Array
        var counted: int = 0
        for index: int in mini(lamps.size(), truck.flares.size()):
            var type: String = truck.flares[index]["type"] as String
            var should: bool = wanted.has(type)
            var is_lit: bool = _lit(lamps[index])
            if should != is_lit:
                return fail(
                    "with %s, lamp %d (type '%s') is %s and should be %s"
                    % [case["name"], index, type, "lit" if is_lit else "dark",
                       "lit" if should else "dark"],
                    index
                )
            if is_lit:
                counted += 1
        reported.append("%s: %d lit" % [case["name"], counted])
    return ok("; ".join(reported), lamps.size())


## Halfway between a dark lens and a lit one.
func _half_lit() -> float:
    return (FlareBuilder.LENS_EMISSION_OFF + FlareBuilder.LENS_EMISSION_ON) * 0.5


## Whether a lamp is emitting: its lens is bright, or its beam is on.
func _lit(lamp: Node3D) -> bool:
    for child: Node in lamp.get_children():
        var light: Light3D = child as Light3D
        if light != null and light.visible:
            return true
        var lens: MeshInstance3D = child as MeshInstance3D
        if lens == null:
            continue
        var material: StandardMaterial3D = lens.material_override as StandardMaterial3D
        # Closer to the on level than the off one, rather than "above off": a material stores
        # its energy as a 32-bit float, so reading back the off level and comparing it with the
        # constant it was set from says the lens is lit.
        if material != null and material.emission_energy_multiplier > _half_lit():
            return true
    return false
