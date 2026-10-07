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
## What a beam yields at and what it breaks at, also from SimConstants. A beam that reaches its
## deform stress bends permanently; one that reaches its strength snaps.
const DEFAULT_DEFORM: float = 400000.0
const DEFAULT_BREAK: float = 1000000.0
## How much of the elastic travel a yielding beam keeps. Upstream's default is none.
const DEFAULT_PLASTIC_COEF: float = 0.0

var _spring: float = DEFAULT_SPRING
var _damp: float = DEFAULT_DAMP
var _deform: float = DEFAULT_DEFORM
var _break: float = DEFAULT_BREAK
var _plastic_coef: float = DEFAULT_PLASTIC_COEF
var _spring_scale: float = 1.0
var _damp_scale: float = 1.0
var _deform_scale: float = 1.0
var _break_scale: float = 1.0


## "set_beam_defaults spring, damp, deform, break, diameter, material, plastic_coef".
## A negative value means "keep upstream's default".
func read_defaults(fields: PackedStringArray) -> void:
    if fields.size() >= 1:
        _spring = fields[0].to_float() if fields[0].to_float() >= 0.0 else DEFAULT_SPRING
    if fields.size() >= 2:
        _damp = fields[1].to_float() if fields[1].to_float() >= 0.0 else DEFAULT_DAMP
    if fields.size() >= 3:
        _deform = fields[2].to_float() if fields[2].to_float() >= 0.0 else DEFAULT_DEFORM
    if fields.size() >= 4:
        _break = fields[3].to_float() if fields[3].to_float() >= 0.0 else DEFAULT_BREAK
    # Fields 5 and 6 are the beam's diameter and material, which are for the renderer upstream
    # does not have here. Field 7 is the plastic coefficient.
    if fields.size() >= 7:
        var stated: float = fields[6].to_float()
        _plastic_coef = stated if stated >= 0.0 else DEFAULT_PLASTIC_COEF


## "set_beam_defaults_scale spring, damp, deform, break".
func read_scale(fields: PackedStringArray) -> void:
    if fields.size() >= 1:
        _spring_scale = fields[0].to_float()
    if fields.size() >= 2:
        _damp_scale = fields[1].to_float()
    if fields.size() >= 3:
        _deform_scale = fields[2].to_float()
    if fields.size() >= 4:
        _break_scale = fields[3].to_float()


## The spring a beam takes when it states none of its own.
func spring() -> float:
    return _spring * _spring_scale


func damp() -> float:
    return _damp * _damp_scale


## The stress a beam yields at, and the stress it breaks at, both scaled the way the springs are.
## The hero truck's own scale is `0.85, 0.25, 0.75, 0.80`, so its structure bends at three
## quarters of the stated figure and breaks at four fifths of it.
func deform() -> float:
    return _deform * _deform_scale


func breaking_strength() -> float:
    return _break * _break_scale


func plastic_coef() -> float:
    return _plastic_coef


## The stated rates, without the scale.
##
## These are what a shock ramps towards once it is past its travel. Upstream records a
## shock's handover rates from the unscaled `springiness` and `damping_constant` while giving
## ordinary beams the scaled ones, so on the hero truck a shock hands over to 1.9 MN/m while
## the structure around it is built at 0.85 of its stated rate. That asymmetry is upstream's
## and it is load-bearing: scaling the handover too would make every bump stop 15% softer.
func spring_unscaled() -> float:
    return _spring


func damp_unscaled() -> float:
    return _damp


## A snapshot of these defaults.
##
## `TruckDocument` hands every row the defaults in force where it was written, and spawning
## happens later and in another order, so a directive must not reach back and change what the
## rows above it were built with. Replacing the object rather than mutating it is what keeps
## that true, and this is the copy it replaces it with.
func copy() -> BeamDefaults:
    var out: BeamDefaults = BeamDefaults.new()
    out._spring = _spring
    out._damp = _damp
    out._deform = _deform
    out._break = _break
    out._plastic_coef = _plastic_coef
    out._spring_scale = _spring_scale
    out._damp_scale = _damp_scale
    out._deform_scale = _deform_scale
    out._break_scale = _break_scale
    return out
