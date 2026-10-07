class_name ColourGrade
extends RefCounted
## The grade on the end of the frame: a lookup table, and the three knobs beside it.
##
## **A LUT is where a look lives, and it is the last thing that touches a picture.** Everything
## before it is a measurement — how much light arrived, what the surface did with it, what the film
## made of that — and a grade is a decision about how the result should feel. Keeping it in one
## place, applied last, is what stops a look being smuggled into the physics: when a scene is too
## blue, the fix is either a light that is wrong or a grade that says so, and those are different
## repairs.
##
## Godot applies `Environment.adjustment_color_correction` after tonemapping, in display space, so
## the table maps display values to display values.

## The side of the cube, in samples. 32 is the usual size for a grading LUT: it resolves a
## gradient without the file being a megabyte, and the hardware interpolates between the samples.
const CUBE: int = 32


## A lookup table that changes nothing, as a 3D texture.
##
## Every sample is its own coordinate, so the table is the identity function and a frame through it
## is the frame it went in as. Used as the neutral default, and as the thing
## `a_neutral_grade_changes_nothing` holds the pipeline to: a LUT path that is sampled wrongly, or
## decoded in the wrong colour space, shows up here as an identity that is not one.
static func identity_cube(side: int = CUBE) -> ImageTexture3D:
    var slices: Array[Image] = []
    # **A texel holds the value at its own centre, not at its index.** Godot samples the cube at the
    # colour itself, so texel `i` is read for values around `(i + 0.5) / side` — and a table written
    # as `i / (side - 1)` is therefore half a texel out everywhere. Measured, that is exactly what it
    # was: a 5% grey came back at 0.0353 instead of 0.0510, short by 0.0157, where half a texel of a
    # 32-sample cube is 0.0156.
    var centre: float = float(side)
    for blue: int in side:
        var slice: Image = Image.create(side, side, false, Image.FORMAT_RGBF)
        for green: int in side:
            for red: int in side:
                slice.set_pixel(red, green, Color(
                    (float(red) + 0.5) / centre,
                    (float(green) + 0.5) / centre,
                    (float(blue) + 0.5) / centre,
                    1.0
                ))
        slices.append(slice)
    var cube: ImageTexture3D = ImageTexture3D.new()
    cube.create(Image.FORMAT_RGBF, side, side, side, false, slices)
    return cube


## Puts an hour's grade on an environment.
##
## A weather preset may name its own table in `grade_lut`; anything that does not gets the identity,
## which is to say no grade at all. The three knobs beside it are there for the cases a table is
## overkill for and are left neutral by default, because a renderer that is right does not need
## them and a renderer that is wrong should not be hiding behind them.
static func apply(env: Environment, weather: Dictionary) -> void:
    var path: String = weather.get("grade_lut", "") as String
    var table: Texture = null
    if not path.is_empty() and ResourceLoader.exists(path):
        table = load(path) as Texture
    env.adjustment_enabled = bool(weather.get("grade", RenderCfg.GRADE_ENABLED))
    env.adjustment_brightness = float(weather.get("grade_brightness", RenderCfg.GRADE_BRIGHTNESS))
    env.adjustment_contrast = float(weather.get("grade_contrast", RenderCfg.GRADE_CONTRAST))
    env.adjustment_saturation = float(weather.get("grade_saturation", RenderCfg.GRADE_SATURATION))
    env.adjustment_color_correction = table
