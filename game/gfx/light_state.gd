class_name LightState
extends RefCounted
## A vehicle's light switches and what each of its lamps shows, upstream's `m_lightmask` and
## `Actor::updateFlareStates` run per frame.
##
## Each lamp is lit by its type's switch (`f` and `t` the headlights, `h` the main beam, `g` the fog
## lights, `s` the sidelights, `b` the pedal, `R` reverse, `l`/`r` the indicator or the hazards, `u`
## its user light), then by its own blink timer: a lamp with a blink delay flips on and off every
## that many seconds, from the moment the clock starts, on its own and not in step with any other.
## A `flares3` lamp then fades in and out by its inertia curve, the way a filament warms. The
## switches themselves are upstream's: low beams bring the sidelights with them, the light cycle
## steps through side, low and main, the indicators cancel each other and the hazards both.

enum Blink { NONE, LEFT, RIGHT, WARN }

var headlights: bool = false
var sidelights: bool = false
var high_beams: bool = false
var fog_lights: bool = false
var brakes: bool = false
var reverse: bool = false
var blink: Blink = Blink.NONE
## Upstream's custom lights 1 to 10, as 0 to 9.
var custom: Array[bool] = [false, false, false, false, false, false, false, false, false, false]
var parking_brake: bool = false

var _flares: Array[Dictionary] = []
var _blink_left: PackedFloat32Array = PackedFloat32Array()
var _blink_on: Array[bool] = []
var _fade_time: PackedFloat32Array = PackedFloat32Array()
var _fades: Array[Dictionary] = []


## The state for `truck`'s lamps, everything off.
static func of(truck: TruckParser) -> LightState:
    var state: LightState = LightState.new()
    state._flares = truck.flares
    for flare: Dictionary in truck.flares:
        state._blink_left.append(0.0)
        state._blink_on.append(false)
        state._fade_time.append(0.0)
        state._fades.append(_fade_of(flare))
    return state


## Upstream's low-beam key: the headlights, and the sidelights follow them.
func toggle_low_beams() -> void:
    headlights = not headlights
    sidelights = headlights


## Upstream's light cycle: off, sidelights (only if the vehicle has any), low beams, main beams
## (only if it has any), off.
func cycle(truck: TruckParser) -> void:
    if _count(truck, FlareRows.SIDELIGHT) > 0 and not sidelights:
        sidelights = true
    elif not headlights:
        sidelights = true
        headlights = true
    elif _count(truck, FlareRows.HIGH_BEAM) > 0 and not high_beams:
        sidelights = true
        headlights = true
        high_beams = true
    else:
        sidelights = false
        headlights = false
        high_beams = false


## Upstream's `toggleBlinkType`: the same stalk again cancels it, another replaces it.
func toggle_blink(kind: Blink) -> void:
    blink = Blink.NONE if blink == kind else kind


func toggle_custom(number: int) -> void:
    if number >= 0 and number < custom.size():
        custom[number] = not custom[number]


## The pedal and the gear, upstream's `ActorManager` rule: brake lights while the brake is pressed
## past 0.01 and the parking brake is off; reversing lights in a reverse gear.
func follow_controls(brake: float, parking: bool, gear: int) -> void:
    parking_brake = parking
    brakes = brake > 0.01 and not parking
    reverse = gear < 0


## Every lamp's intensity after `dt` seconds, 0 to 1.
func update(dt: float) -> PackedFloat32Array:
    var out: PackedFloat32Array = PackedFloat32Array()
    for i: int in _flares.size():
        var flare: Dictionary = _flares[i]
        var delay: float = float(flare.get("blink_s", 0.0))
        if delay != 0.0:
            _blink_left[i] -= dt
            if _blink_left[i] <= 0.0:
                _blink_left[i] = delay
                _blink_on[i] = not _blink_on[i]
        else:
            _blink_on[i] = true
        var visible: bool = _switch_of(flare) and _blink_on[i]
        out.append(_fade(i, visible, dt))
    return out


func _switch_of(flare: Dictionary) -> bool:
    match flare["type"] as String:
        FlareRows.HEADLIGHT, FlareRows.TAIL_LIGHT:
            return headlights
        FlareRows.HIGH_BEAM:
            return high_beams
        FlareRows.FOG_LIGHT:
            return fog_lights
        FlareRows.SIDELIGHT:
            return sidelights
        FlareRows.BRAKE_LIGHT:
            return brakes
        FlareRows.REVERSE_LIGHT:
            return reverse
        FlareRows.BLINKER_LEFT:
            return blink == Blink.LEFT or blink == Blink.WARN
        FlareRows.BLINKER_RIGHT:
            return blink == Blink.RIGHT or blink == Blink.WARN
        FlareRows.USER:
            var number: int = int(flare.get("control", -1))
            return number >= 0 and number < custom.size() and custom[number]
        FlareRows.DASHBOARD:
            # The only dashboard input modelled is the parking brake.
            return flare.get("dashboard", "") == "parkingbrake" and parking_brake
    return false


## Upstream's `SimpleInertia::CalcSimpleDelay` for a `flares3` lamp, or the switch itself.
func _fade(i: int, visible: bool, dt: float) -> float:
    var fade: Dictionary = _fades[i]
    if fade.is_empty():
        return 1.0 if visible else 0.0
    if visible:
        if _fade_time[i] < 1.0:
            _fade_time[i] = minf(_fade_time[i] + dt / float(fade["start_delay"]), 1.0)
        var start: SimpleSpline = fade["start"]
        return start.interpolate_y(_fade_time[i]) if start != null else 1.0
    if _fade_time[i] > 0.0:
        _fade_time[i] = maxf(_fade_time[i] - dt / float(fade["stop_delay"]), 0.0)
    var stop: SimpleSpline = fade["stop"]
    return stop.interpolate_y(_fade_time[i]) if stop != null else 0.0


## A `flares3` lamp's fade, upstream's `_ProcessSimpleInertia`: its delays (a delay that is not
## positive is 0, which upstream leaves as a division by zero; here it is instant) and its curves by
## name, "/" and "-" meaning none. {} for a lamp that does not fade.
static func _fade_of(flare: Dictionary) -> Dictionary:
    if not flare.has("inertia"):
        return {}
    var inertia: Dictionary = flare["inertia"]
    var out: Dictionary = {}
    for key: String in ["start", "stop"]:
        var delay: float = float(inertia.get(key + "_delay", 0.0))
        out[key + "_delay"] = delay if delay > 0.0 else 1e-6
        var name: String = str(inertia.get(key + "_function", ""))
        out[key] = SimpleSpline.of(InertiaModels.MODELS[name]) if InertiaModels.MODELS.has(name) else null
    return out


static func _count(truck: TruckParser, type: String) -> int:
    var count: int = 0
    for flare: Dictionary in truck.flares:
        count += 1 if flare["type"] == type else 0
    return count
