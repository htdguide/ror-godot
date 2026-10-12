extends GateBase
## Each lamp lights by upstream's rules (`Actor::updateFlareStates` and the switches in
## `GameContext`), blinks on its own clock, fades if it is a `flares3` lamp, and shows its sprite
## as `GfxActor::UpdateFlares` does.
##
## What was ours before: brake lights lit with the headlights; every indicator on one shared 0.8 s
## clock where upstream gives each lamp its own (half a second each way by default); no hazards,
## fog lights, sidelights or user lights; `flares3` not read; a blink delay of -1 read as -1 ms
## and a negative size as the default; and a sprite the same size from every side.
##
## The oracle is upstream's code read rule by rule, on rows of every type:
## - parse: blink -2 is 0.5 s for an indicator and none otherwise, -1 is 0.5 s, n is n ms; size
##   -2 is 1 for a headlight and 0.5 otherwise, -1 is 0.5, other negatives stay; an unknown type
##   is `f`; user light 12 is the parking brake lamp; a material follows its first binding only;
## - switches: low beams bring the sidelights; brake lights only with the pedal past 0.01 and the
##   parking brake off; the same indicator again cancels; hazards light both;
## - clock: a 0.5 s lamp is lit from the first frame and flips on the frame its timer runs out,
##   which at 0.017 s a frame is every 30 frames;
## - fade: a `flares3` lamp on the `linear` curve with a 2 s start is at half after 1 s;
## - sprite: as big as the cosine between its facing and the camera, 0 from behind and past 500 m,
##   and 1 from anywhere for a lamp of negative size;
## - dashboard: ignition and battery lamps with the key on and the engine off, the warning lamp a
##   frame behind both indicators, the rpm lamp by its float's lowest byte.

const FLARE_ROWS: String = """lights
globals
1000, 0, tracks/semi
nodes
0, 0.0, 0.0, 0.0
1, 1.0, 0.0, 0.0
2, 0.0, 1.0, 0.0
set_inertia_defaults 2.0, 2.0, linear, linear
flares2
0, 1, 2, 0.5, 0.5, 0.0, f
0, 1, 2, 0.5, 0.5, 0.0, b
0, 1, 2, 0.5, 0.5, 0.0, l
0, 1, 2, 0.5, 0.5, 0.0, r
0, 1, 2, 0.5, 0.5, 0.0, s
0, 1, 2, 0.5, 0.5, 0.0, u, 3, 0, -0.7
0, 1, 2, 0.5, 0.5, 0.0, u, 12
0, 1, 2, 0.5, 0.5, 0.0, x, -1, -1
0, 1, 2, 0.5, 0.5, 0.0, b, -1, 250, -2
0, 1, 2, 0.5, 0.5, 0.0, d, engine_battery
0, 1, 2, 0.5, 0.5, 0.0, d, signal_warning
0, 1, 2, 0.5, 0.5, 0.0, d, rpm
flares3
0, 1, 2, 0.5, 0.5, 0.0, f, -1, 0
materialflarebindings
1, glass
6, glass
end"""
## A frame that does not divide half a second, so a toggle falls clearly on one frame: the timer
## resets to 0.5 s when it flips, so a 0.5 s lamp flips every 30 frames of 0.017 s.
const DT: float = 0.017


static func meta() -> Dictionary:
    return {
        "name": "a_lamp_lights_by_upstreams_switches_and_clock",
        "proves": "flare rows parse, switch, blink, fade and show their sprite by upstream's updateFlareStates, switches and UpdateFlares",
        "builds_on": [],
        "oracle": GateBase.ORACLE_COMPUTED,
        "threshold": "every rule in the header exact: parse values, switch states, blink on 0-0.5 s / off 0.5-1 s, linear fade 0.5 at 1 s of 2, sprite cosine",
        "why": "brake lights lit with the headlights, indicators shared one clock, hazards, fog, side and user lights and flares3 did not exist, and sprites were the same size from behind.",
        "budget_s": 10.0,
        "needs_gpu": false,
        "milestone": "M1",
    }


func run(_harness: Node) -> Dictionary:
    var truck: TruckParser = TruckParser.new()
    var error: String = truck.parse_text(FLARE_ROWS)
    if error != "" or truck.flares.size() != 13:
        return fail("the flare rows did not parse to 13 lamps: %s (%d)" % [error, truck.flares.size()])
    var f: Array[Dictionary] = truck.flares
    var parsed: Array = [
        [f[2]["blink_s"], 0.5], [f[0]["blink_s"], 0.0], [f[7]["blink_s"], 0.5], [f[8]["blink_s"], 0.25],
        [f[0]["size"], 1.0], [f[2]["size"], 0.5], [f[7]["size"], 1.0], [f[5]["size"], -0.7], [f[8]["size"], 0.5],
        [f[7]["type"], "f"], [f[5]["control"], 2], [f[6]["type"], "d"], [f[6]["dashboard"], "parkingbrake"],
        [truck.material_flares.get("glass"), PackedInt32Array([1])],
    ]
    for i: int in parsed.size():
        if parsed[i][0] != parsed[i][1]:
            return fail("parse check %d: read %s, upstream's rule gives %s" % [i, parsed[i][0], parsed[i][1]])

    var light: LightState = LightState.of(truck)
    light.headlights = true
    light.follow_controls(0.0, false, 1)
    var lit: PackedFloat32Array = light.update(DT)
    if lit[1] != 0.0:
        return fail("the brake light is lit by the headlights alone (%.1f)" % lit[1])
    light = LightState.of(truck)
    light.toggle_low_beams()
    if not light.sidelights:
        return fail("low beams did not bring the sidelights")
    light.follow_controls(0.005, false, 1)
    if light.brakes:
        return fail("brake lights at 0.005 of the pedal; upstream's threshold is 0.01")
    light.follow_controls(1.0, true, 1)
    if light.brakes:
        return fail("brake lights with the parking brake on")
    light.toggle_blink(LightState.Blink.LEFT)
    light.toggle_blink(LightState.Blink.LEFT)
    if light.blink != LightState.Blink.NONE:
        return fail("the same indicator twice did not cancel it")
    light.toggle_blink(LightState.Blink.WARN)
    var both: PackedFloat32Array = light.update(DT)
    if both[2] != 1.0 or both[3] != 1.0:
        return fail("hazards lit left %.1f and right %.1f, not both" % [both[2], both[3]])

    # The clock: a 0.5 s indicator from its first frame.
    light = LightState.of(truck)
    light.blink = LightState.Blink.LEFT
    var pattern: PackedStringArray = PackedStringArray()
    var expected: PackedStringArray = PackedStringArray()
    for frame: int in 70:
        var on: bool = light.update(DT)[2] > 0.0
        pattern.append("1" if on else "0")
        expected.append("1" if (frame / 30) % 2 == 0 else "0")
    if pattern != expected:
        return fail("the indicator lit %s over 70 frames; upstream's clock gives %s" % ["".join(pattern), "".join(expected)])

    # The fade: the flares3 headlight on `linear`, 2 s to warm.
    light = LightState.of(truck)
    light.headlights = true
    var warm: float = light.update(1.0)[12]
    if absf(warm - 0.5) > 1e-4:
        return fail("the flares3 lamp is at %.4f after 1 s of a 2 s linear warm-up, not 0.5" % warm)

    # The dashboard: ignition and battery with the key on and the engine not running; the warning
    # lamp a frame behind the hazards, as upstream updates its dashboard before its flares; rpm
    # as a float read through a bool, lit by its lowest byte (800.0 has a zero one, 812.3 not).
    light = LightState.of(truck)
    light.follow_engine(true, false, 800.0)
    var dash: PackedFloat32Array = light.update(DT)
    if dash[9] != 1.0 or dash[11] != 0.0:
        return fail("key on, engine off at 800 rpm: battery lamp %.1f (should be lit), rpm lamp %.1f (should be dark)" % [dash[9], dash[11]])
    light.follow_engine(true, true, 812.3)
    dash = light.update(DT)
    if dash[9] != 0.0 or dash[11] != 1.0:
        return fail("engine running at 812.3 rpm: battery lamp %.1f (should be dark), rpm lamp %.1f (should be lit)" % [dash[9], dash[11]])
    light.blink = LightState.Blink.WARN
    var first: float = light.update(DT)[10]
    var second: float = light.update(DT)[10]
    if first != 0.0 or second != 1.0:
        return fail("the warning lamp read %.1f on the hazards' first frame and %.1f on the second; upstream's is a frame behind" % [first, second])

    # The sprite.
    var lamp: Transform3D = Transform3D(Basis.IDENTITY, Vector3.ZERO)
    var front: float = FlareBuilder.sprite_amplitude(lamp, Vector3(0.0, 0.0, -10.0), 1.0)
    var oblique: float = FlareBuilder.sprite_amplitude(lamp, Vector3(10.0, 0.0, -10.0), 1.0)
    var behind: float = FlareBuilder.sprite_amplitude(lamp, Vector3(0.0, 0.0, 10.0), 1.0)
    var far: float = FlareBuilder.sprite_amplitude(lamp, Vector3(0.0, 0.0, -600.0), 1.0)
    var fixed: float = FlareBuilder.sprite_amplitude(lamp, Vector3(0.0, 0.0, 10.0), -0.7)
    if absf(front - 1.0) > 1e-6 or absf(oblique - cos(PI / 4.0)) > 1e-6 or behind != 0.0 or far != 0.0 or fixed != 1.0:
        return fail("sprite sizes front %.3f, 45 deg %.3f, behind %.3f, at 600 m %.3f, fixed size from behind %.3f" % [front, oblique, behind, far, fixed])
    return ok("parse, switches, the 0.5 s clock over 70 frames, the flares3 fade (%.4f at 1 s) and the sprite all upstream's" % warm, 0)
