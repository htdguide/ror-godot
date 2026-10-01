class_name ColorChecker
extends RefCounted
## The 24 patches of a ColorChecker, as published. Nothing here was measured by this project and
## nothing here was recited from memory.
##
## **Source.** CIE xyY for the CIE 1931 2 degree standard observer under **Illuminant C**, from
## Field, *Color Scanning and Imaging Systems* (1990), with the CIE data for Illuminant C from
## Poynton (2008), as tabulated in Wikipedia's `ColorChecker` article. The patch colours
## themselves were described by McCamy et al. (1976). See `THIRD_PARTY.md` for the citation and
## the retrieval.
##
## **Why these numbers and not a nicer set.** A gate may not write its own expectation, and a
## colour chart is the easiest place in a renderer to break that rule: the published values are
## widely quoted, so quoting 24 patches from memory would feel like sourcing them and would in
## fact be a self-written expectation with a citation stapled to it. These were retrieved,
## verbatim, from one stated table, and the uncertainty in them is that table's.
##
## **The adopted white is the chart's own.** Patches 19 through 24 are neutral and every one of
## them is published at x 0.310, y 0.316 — which is Illuminant C, stated by the same table that
## states the colours. So the white point this data is relative to comes out of the data, and no
## illuminant constant has to be recited alongside it. That also means no chromatic adaptation is
## needed anywhere downstream: the measurement can be done under C throughout.
##
## **The X-Rite sRGB column is carried but deliberately unused.** The same table gives the
## manufacturer's own sRGB values, from X-Rite's `ColorData-1p_EN.pdf`. It is a genuinely
## independent publication of the same physical chart and so a tempting second oracle, but it is
## specified under D65 while the xyY column is under C, and bridging them needs a chromatic
## adaptation matrix that would itself have to be sourced and whose choice (Bradford, CAT02, XYZ
## scaling) would change the answer. Until that is sourced, comparing the two would report their
## illuminant difference as if it were renderer error. It is here so the next person does not
## have to fetch it again.
##
## One discrepancy in the source is preserved rather than smoothed: patch 19's cell is shaded
## `#f3f3f2` while the value written in it reads `#f3f3f3`. The written value is carried, since
## that is the figure the table states, and the shading is presumably a typo in one or the other.

## One patch: its published chromaticity and luminance factor, and the manufacturer's sRGB hex.
##
## `luminance` is Y as the table gives it, in percent — a luminance *factor*, so the white patch's
## 90.0 means it reflects 90% of the light, and dividing by 100 is the only arithmetic applied to
## any of these numbers here.
const PATCHES: Array[Dictionary] = [
    {"index": 1, "name": "Dark skin", "x": 0.400, "y": 0.350, "luminance": 10.1, "srgb": "735244"},
    {"index": 2, "name": "Light skin", "x": 0.377, "y": 0.345, "luminance": 35.8, "srgb": "c29682"},
    {"index": 3, "name": "Blue sky", "x": 0.247, "y": 0.251, "luminance": 19.3, "srgb": "627a9d"},
    {"index": 4, "name": "Foliage", "x": 0.337, "y": 0.422, "luminance": 13.3, "srgb": "576c43"},
    {"index": 5, "name": "Blue flower", "x": 0.265, "y": 0.240, "luminance": 24.3, "srgb": "8580b1"},
    {"index": 6, "name": "Bluish green", "x": 0.261, "y": 0.343, "luminance": 43.1, "srgb": "67bdaa"},
    {"index": 7, "name": "Orange", "x": 0.506, "y": 0.407, "luminance": 30.1, "srgb": "d67e2c"},
    {"index": 8, "name": "Purplish blue", "x": 0.211, "y": 0.175, "luminance": 12.0, "srgb": "505ba6"},
    {"index": 9, "name": "Moderate red", "x": 0.453, "y": 0.306, "luminance": 19.8, "srgb": "c15a63"},
    {"index": 10, "name": "Purple", "x": 0.285, "y": 0.202, "luminance": 6.6, "srgb": "5e3c6c"},
    {"index": 11, "name": "Yellow green", "x": 0.380, "y": 0.489, "luminance": 44.3, "srgb": "9dbc40"},
    {"index": 12, "name": "Orange yellow", "x": 0.473, "y": 0.438, "luminance": 43.1, "srgb": "e0a32e"},
    {"index": 13, "name": "Blue", "x": 0.187, "y": 0.129, "luminance": 6.1, "srgb": "383d96"},
    {"index": 14, "name": "Green", "x": 0.305, "y": 0.478, "luminance": 23.4, "srgb": "469449"},
    {"index": 15, "name": "Red", "x": 0.539, "y": 0.313, "luminance": 12.0, "srgb": "af363c"},
    {"index": 16, "name": "Yellow", "x": 0.448, "y": 0.470, "luminance": 59.1, "srgb": "e7c71f"},
    {"index": 17, "name": "Magenta", "x": 0.364, "y": 0.233, "luminance": 19.8, "srgb": "bb5695"},
    {"index": 18, "name": "Cyan", "x": 0.196, "y": 0.252, "luminance": 19.8, "srgb": "0885a1"},
    {"index": 19, "name": "White", "x": 0.310, "y": 0.316, "luminance": 90.0, "srgb": "f3f3f3"},
    {"index": 20, "name": "Neutral 8", "x": 0.310, "y": 0.316, "luminance": 59.1, "srgb": "c8c8c8"},
    {"index": 21, "name": "Neutral 6.5", "x": 0.310, "y": 0.316, "luminance": 36.2, "srgb": "a0a0a0"},
    {"index": 22, "name": "Neutral 5", "x": 0.310, "y": 0.316, "luminance": 19.8, "srgb": "7a7a7a"},
    {"index": 23, "name": "Neutral 3.5", "x": 0.310, "y": 0.316, "luminance": 9.0, "srgb": "555555"},
    {"index": 24, "name": "Black", "x": 0.310, "y": 0.316, "luminance": 3.1, "srgb": "343434"},
]

## The chart is six patches across and four down, in the order the table lists them.
const COLUMNS: int = 6
const ROWS: int = 4
## The neutral row, whose patches state the white the whole table is relative to.
const FIRST_NEUTRAL: int = 18


## The chart's own adopted white as an XYZ with Y = 1, taken from its neutral patches rather than
## from a recited illuminant.
##
## Every neutral patch must agree, and this refuses rather than averaging if they do not: a chart
## whose greys disagree about the white point is a transcription error, and silently averaging it
## would turn that error into a small bias in every Lab value computed downstream.
static func adopted_white() -> Vector3:
    var first: Dictionary = PATCHES[FIRST_NEUTRAL]
    for index: int in range(FIRST_NEUTRAL, PATCHES.size()):
        var patch: Dictionary = PATCHES[index]
        if not is_equal_approx(patch["x"] as float, first["x"] as float) \
                or not is_equal_approx(patch["y"] as float, first["y"] as float):
            push_error(
                "the chart's neutral patches disagree about the white point: patch %d is at"
                % (patch["index"] as int) + " %.3f, %.3f and patch %d at %.3f, %.3f"
                % [patch["x"], patch["y"], first["index"], first["x"], first["y"]]
            )
            return Vector3.ZERO
    return Colorimetry.xyy_to_xyz(first["x"] as float, first["y"] as float, 1.0)


## A patch's published colour as an XYZ, with Y as a reflectance factor rather than a percentage.
static func xyz(patch: Dictionary) -> Vector3:
    return Colorimetry.xyy_to_xyz(
        patch["x"] as float, patch["y"] as float, (patch["luminance"] as float) / 100.0
    )


## Where a patch sits on the chart, in the table's own reading order: six across, four down.
static func grid_position(index: int, spacing: float) -> Vector2:
    var column: int = index % COLUMNS
    var row: int = index / COLUMNS
    return Vector2(
        (float(column) - float(COLUMNS - 1) * 0.5) * spacing,
        (float(ROWS - 1) * 0.5 - float(row)) * spacing
    )
