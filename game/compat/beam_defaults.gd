class_name BeamDefaults
extends RefCounted
## The beam spring and damping in force at a point in a vehicle file.
##
## Two directives set them and they do not work the same way. `set_beam_defaults` states the
## rates, and a later one replaces them outright. `set_beam_defaults_scale` states multipliers
## that survive every later `set_beam_defaults`, so a scale stated once at the top of a file
## applies to everything below it.
##
## The hero truck opens with `set_beam_defaults_scale 0.85, 0.25, 0.75, 0.80`. Every beam that
## takes its rate from the defaults is therefore 15% softer and four times less damped than
## the figure written beside it — and that 0.25 is most of why the rig is stable at upstream's
## 2 kHz rather than needing 3 kHz.
##
## A beam that states its own rates, such as a shock, uses them unscaled. That asymmetry is
## upstream's, not an oversight here.

## Upstream's SimConstants defaults, in force until a directive changes them.
const DEFAULT_SPRING: float = 9000000.0
const DEFAULT_DAMP: float = 12000.0

var _spring: float = DEFAULT_SPRING
var _damp: float = DEFAULT_DAMP
var _spring_scale: float = 1.0
var _damp_scale: float = 1.0


## "set_beam_defaults spring, damp, deform, break, diameter, material, plastic_coef".
## A negative value means "keep upstream's default".
func read_defaults(fields: PackedStringArray) -> void:
    if fields.size() >= 1:
        _spring = fields[0].to_float() if fields[0].to_float() >= 0.0 else DEFAULT_SPRING
    if fields.size() >= 2:
        _damp = fields[1].to_float() if fields[1].to_float() >= 0.0 else DEFAULT_DAMP


## "set_beam_defaults_scale spring, damp, deform, break".
func read_scale(fields: PackedStringArray) -> void:
    if fields.size() >= 1:
        _spring_scale = fields[0].to_float()
    if fields.size() >= 2:
        _damp_scale = fields[1].to_float()


## The spring a beam takes when it states none of its own.
func spring() -> float:
    return _spring * _spring_scale


func damp() -> float:
    return _damp * _damp_scale
