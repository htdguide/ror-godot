class_name DaylightLocus
extends RefCounted
## Where a daylight illuminant sits on the chromaticity diagram, and the published values that
## say so.
##
## **A blackbody and daylight are not the same white.** Godot's `Light3D.light_temperature`
## converts along the Planckian locus — the colour a black body glows at that temperature — and
## sRGB's white point is D65, which is on the **daylight** locus, a different curve fitted to
## measured skylight. 6500 K on one is not 6500 K on the other, which is why a light this project
## sets to 6500 K photographs as (1.0, 0.9419, 0.9919) rather than neutral: a 6% green deficit
## carried by every light in the scene.
##
## **The locus is a published formula**, CIE 15 — see `THIRD_PARTY.md`. For 4000 K to 7000 K
##
##     x = -4.6070e9/T^3 + 2.9678e6/T^2 + 0.09911e3/T + 0.244063
##
## and above 7000 K
##
##     x = -2.0064e9/T^3 + 1.9018e6/T^2 + 0.24748e3/T + 0.237040
##
## with `y = -3.000 x^2 + 2.870 x - 0.275` over the whole range.
##
## **The named illuminants are not at round temperatures.** The series was defined when the
## second radiation constant was 1.4380e-2 m K and it is 1.4388e-2 now, so the nominal
## temperature is multiplied by 1.4388/1.4380: D65 is 6503.6 K and D50 is 5002.8 K. Measured
## against the published chromaticities, the correction **halves the residual** — 0.000095 to
## 0.000126 with it, 0.000164 to 0.000196 without — so it is worth making and it is a good deal
## smaller than the 0.0008 this was first written down as. Both are inside any tolerance this
## project would set, which is why the gate reports the difference instead of turning on it.

## The correction from the nominal name to the temperature the formula wants.
const PLANCK_CORRECTION: float = 1.4388 / 1.4380
## Where the two branches of the formula meet.
const BRANCH_K: float = 7000.0
## The range the formula is defined over.
const MIN_K: float = 4000.0
const MAX_K: float = 25000.0

## The published chromaticities of the named illuminants, for the 2 degree observer. These are
## what the formula is checked against; they are not computed from it.
const PUBLISHED: Dictionary = {
    "D50": Vector2(0.34567, 0.35850),
    "D55": Vector2(0.33242, 0.34743),
    "D65": Vector2(0.31272, 0.32903),
    "D75": Vector2(0.29902, 0.31485),
}
## The nominal temperature each of those is named for.
const NOMINAL_K: Dictionary = {
    "D50": 5000.0,
    "D55": 5500.0,
    "D65": 6500.0,
    "D75": 7500.0,
}


## The chromaticity of the daylight illuminant of correlated colour temperature `kelvin`.
##
## `kelvin` is the real temperature, not the name: pass 6503.6 for D65, or `of_name("D65")`.
static func chromaticity(kelvin: float) -> Vector2:
    var t: float = clampf(kelvin, MIN_K, MAX_K)
    var x: float = 0.0
    if t <= BRANCH_K:
        x = (
            -4.6070e9 / (t * t * t) + 2.9678e6 / (t * t) + 0.09911e3 / t + 0.244063
        )
    else:
        x = (
            -2.0064e9 / (t * t * t) + 1.9018e6 / (t * t) + 0.24748e3 / t + 0.237040
        )
    return Vector2(x, -3.000 * x * x + 2.870 * x - 0.275)


## The chromaticity of a named illuminant, computed from its nominal temperature through the
## correction the series carries. `D65` is 6500 x 1.4388/1.4380.
static func of_name(name: String) -> Vector2:
    if not NOMINAL_K.has(name):
        return Vector2.ZERO
    return chromaticity((NOMINAL_K[name] as float) * PLANCK_CORRECTION)


## The linear sRGB a daylight illuminant of this temperature shines, normalised so its brightest
## channel is 1. A light's colour, in other words, with its brightness left to its own field.
static func linear_srgb(kelvin: float) -> Color:
    var xy: Vector2 = chromaticity(kelvin)
    var xyz: Vector3 = Colorimetry.xyy_to_xyz(xy.x, xy.y, 1.0)
    var to_rgb: Array[Vector3] = Colorimetry.inverse(Colorimetry.rgb_to_xyz(
        Colorimetry.SRGB_RED, Colorimetry.SRGB_GREEN, Colorimetry.SRGB_BLUE,
        Colorimetry.xyy_to_xyz(
            Colorimetry.SRGB_WHITE.x, Colorimetry.SRGB_WHITE.y, 1.0
        )
    ))
    var rgb: Vector3 = Colorimetry.apply(to_rgb, xyz)
    var brightest: float = maxf(rgb.x, maxf(rgb.y, rgb.z))
    if brightest <= 0.0:
        return Color.WHITE
    return Color(
        maxf(rgb.x, 0.0) / brightest,
        maxf(rgb.y, 0.0) / brightest,
        maxf(rgb.z, 0.0) / brightest
    )
