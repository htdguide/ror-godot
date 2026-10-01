class_name Colorimetry
extends RefCounted
## Colour arithmetic: chromaticities to matrices, XYZ to CIELAB, and the distance between two
## colours. Textbook formulae only — nothing here encodes a measurement.
##
## **Why the matrices are built and not written down.** The sRGB-to-XYZ matrix is quoted in a
## hundred places and is exactly the sort of nine-number constant that is easy to transcribe
## subtly wrong and impossible to notice: a channel error of a per cent survives every eyeball
## check and lands in the middle of a colour measurement as a bias. So this takes the eight
## chromaticity coordinates the sRGB standard actually defines and derives the matrix, which
## means the only recited numbers are ones that can be checked against the standard at a glance.
## `matrix_is_consistent` then asserts the derivation against its own inputs.
##
## **Matrices are three rows, explicitly.** Not `Basis`: whether `Basis.x` is a row or a column
## is the single most reliable source of silent transposition bugs in Godot code, and a
## transposed colour matrix is a channel swap that still produces plausible pictures.

## The chromaticities the sRGB standard defines (IEC 61966-2-1), with the D65 white point. Taken
## from the primaries table in Wikipedia's `SRGB` article; see `THIRD_PARTY.md`.
##
## The standard's own luminance weights for these primaries are 0.2126, 0.7152 and 0.0722, which
## is a useful cross-check on this derivation: the middle row of the resulting matrix must come
## out as those three numbers when the white point is D65.
const SRGB_RED: Vector2 = Vector2(0.6400, 0.3300)
const SRGB_GREEN: Vector2 = Vector2(0.3000, 0.6000)
const SRGB_BLUE: Vector2 = Vector2(0.1500, 0.0600)
const SRGB_WHITE: Vector2 = Vector2(0.3127, 0.3290)

## CIELAB's two constants, as the standard writes them rather than as decimals: the cube of 6/29
## is where the curve meets its linear toe.
const LAB_EPSILON: float = 216.0 / 24389.0
const LAB_KAPPA: float = 24389.0 / 27.0


## A chromaticity and a luminance as an XYZ.
static func xyy_to_xyz(x: float, y: float, luminance: float) -> Vector3:
    if absf(y) < 0.000001:
        return Vector3.ZERO
    return Vector3(luminance * x / y, luminance, luminance * (1.0 - x - y) / y)


## The matrix taking linear RGB in a space with these primaries to XYZ, scaled so that
## RGB (1, 1, 1) is exactly the given white.
##
## The construction is the standard one: put the primaries' XYZ in the columns, solve for the
## three scale factors that make the channels sum to the white, and fold those into the columns.
static func rgb_to_xyz(
    red: Vector2, green: Vector2, blue: Vector2, white: Vector3
) -> Array[Vector3]:
    var primaries: Array[Vector3] = [
        Vector3(red.x, green.x, blue.x),
        Vector3(red.y, green.y, blue.y),
        Vector3(1.0 - red.x - red.y, 1.0 - green.x - green.y, 1.0 - blue.x - blue.y),
    ]
    var scale: Vector3 = apply(inverse(primaries), white)
    var out: Array[Vector3] = []
    for row: Vector3 in primaries:
        out.append(Vector3(row.x * scale.x, row.y * scale.y, row.z * scale.z))
    return out


## How far a derived matrix is from reproducing its own inputs, as a share of them.
##
## Three things must hold for the construction to have worked: RGB (1,1,1) maps to the white, and
## each primary alone maps to a colour of that primary's chromaticity. If any of them does not,
## the matrix is wrong in a way that would otherwise show up only as a colour measurement that
## is slightly off and impossible to attribute.
static func matrix_is_consistent(
    matrix: Array[Vector3], red: Vector2, green: Vector2, blue: Vector2, white: Vector3
) -> float:
    var worst: float = 0.0
    var mapped_white: Vector3 = apply(matrix, Vector3.ONE)
    for axis: int in 3:
        worst = maxf(worst, absf(mapped_white[axis] - white[axis]) / maxf(absf(white[axis]), 0.000001))
    var wanted: Array[Vector2] = [red, green, blue]
    for channel: int in 3:
        var only: Vector3 = Vector3.ZERO
        only[channel] = 1.0
        var got: Vector3 = apply(matrix, only)
        var total: float = got.x + got.y + got.z
        if absf(total) < 0.000001:
            return INF
        worst = maxf(worst, absf(got.x / total - wanted[channel].x) / wanted[channel].x)
        worst = maxf(worst, absf(got.y / total - wanted[channel].y) / wanted[channel].y)
    return worst


## An XYZ as CIELAB, relative to a stated white.
static func xyz_to_lab(xyz: Vector3, white: Vector3) -> Vector3:
    var fx: float = _lab_f(xyz.x / maxf(white.x, 0.000001))
    var fy: float = _lab_f(xyz.y / maxf(white.y, 0.000001))
    var fz: float = _lab_f(xyz.z / maxf(white.z, 0.000001))
    return Vector3(116.0 * fy - 16.0, 500.0 * (fx - fy), 200.0 * (fy - fz))


static func _lab_f(ratio: float) -> float:
    if ratio > LAB_EPSILON:
        return pow(ratio, 1.0 / 3.0)
    return (LAB_KAPPA * ratio + 16.0) / 116.0


## CIE76: the plain Euclidean distance in Lab.
##
## Stated plainly because the choice matters and a later gate may want better: CIE76 over-weights
## saturated colours compared to CIEDE2000, so a figure quoted in it is not comparable with one
## quoted in the other. It is used here because it is unambiguous and short enough to read and
## check, and because the question this project is asking of its renderer — does colour survive
## the pipeline at all — is nowhere near the precision where the difference between the two
## formulae decides anything.
static func delta_e_76(first: Vector3, second: Vector3) -> float:
    return (first - second).length()


## --------------------------------------------------------------------------------
## Three-by-three arithmetic, rows explicit


static func apply(matrix: Array[Vector3], vector: Vector3) -> Vector3:
    return Vector3(
        matrix[0].dot(vector), matrix[1].dot(vector), matrix[2].dot(vector)
    )


static func inverse(matrix: Array[Vector3]) -> Array[Vector3]:
    var a: Vector3 = matrix[0]
    var b: Vector3 = matrix[1]
    var c: Vector3 = matrix[2]
    var cofactors: Array[Vector3] = [
        Vector3(b.y * c.z - b.z * c.y, b.z * c.x - b.x * c.z, b.x * c.y - b.y * c.x),
        Vector3(a.z * c.y - a.y * c.z, a.x * c.z - a.z * c.x, a.y * c.x - a.x * c.y),
        Vector3(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x),
    ]
    var determinant: float = a.x * cofactors[0].x + a.y * cofactors[0].y + a.z * cofactors[0].z
    if absf(determinant) < 0.0000000001:
        push_error("a colour matrix is singular; its primaries are collinear")
        return [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO] as Array[Vector3]
    var out: Array[Vector3] = []
    for column: int in 3:
        out.append(Vector3(
            cofactors[0][column] / determinant,
            cofactors[1][column] / determinant,
            cofactors[2][column] / determinant
        ))
    return out
