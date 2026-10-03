class_name Stamp
extends RefCounted
## Writes a word into a captured image, in pixels.
##
## **A photograph of a model needs to say which side it is of.** A sheet of six views is only
## readable if each tile names itself: a texture can look plausible and be on the wrong face, and
## without a label there is nothing to tell a wall seen from the front from the same wall seen
## from behind. Asked for from a window, in those words — "maybe we see them, but wrongly".
##
## **Drawn as pixels rather than as text.** Godot's `Label` in a `CanvasLayer` does not appear in
## a viewport capture, and ffmpeg's `drawtext` filter is missing from this build, so both of the
## obvious ways to put a word on an image fail silently. A five-by-seven bitmap cannot.
##
## The glyphs are only the letters the view names use. A letter that is wanted and absent draws as
## a blank, which is visible as a gap rather than as a wrong word.

## How many image pixels one glyph pixel covers, and how far from the corner the word sits.
const SCALE: int = 4
const MARGIN: int = 24
const SPACING: int = 1
const GLYPH_W: int = 5
const GLYPH_H: int = 7
## Drawn light on a dark plate so it reads over sky, ground or bodywork alike.
const INK: Color = Color(1.0, 1.0, 1.0)
const PLATE: Color = Color(0.0, 0.0, 0.0, 0.65)
const PLATE_PAD: int = 6

const FONT: Dictionary = {
    "A": ["01110", "10001", "10001", "11111", "10001", "10001", "10001"],
    "B": ["11110", "10001", "10001", "11110", "10001", "10001", "11110"],
    "C": ["01110", "10001", "10000", "10000", "10000", "10001", "01110"],
    "D": ["11110", "10001", "10001", "10001", "10001", "10001", "11110"],
    "E": ["11111", "10000", "10000", "11110", "10000", "10000", "11111"],
    "F": ["11111", "10000", "10000", "11110", "10000", "10000", "10000"],
    "G": ["01110", "10001", "10000", "10111", "10001", "10001", "01111"],
    "H": ["10001", "10001", "10001", "11111", "10001", "10001", "10001"],
    "I": ["11111", "00100", "00100", "00100", "00100", "00100", "11111"],
    "K": ["10001", "10010", "10100", "11000", "10100", "10010", "10001"],
    "L": ["10000", "10000", "10000", "10000", "10000", "10000", "11111"],
    "M": ["10001", "11011", "10101", "10101", "10001", "10001", "10001"],
    "N": ["10001", "11001", "10101", "10011", "10001", "10001", "10001"],
    "O": ["01110", "10001", "10001", "10001", "10001", "10001", "01110"],
    "P": ["11110", "10001", "10001", "11110", "10000", "10000", "10000"],
    "Q": ["01110", "10001", "10001", "10001", "10101", "10010", "01101"],
    "R": ["11110", "10001", "10001", "11110", "10100", "10010", "10001"],
    "S": ["01111", "10000", "10000", "01110", "00001", "00001", "11110"],
    "T": ["11111", "00100", "00100", "00100", "00100", "00100", "00100"],
    "U": ["10001", "10001", "10001", "10001", "10001", "10001", "01110"],
    "3": ["11110", "00001", "00001", "01110", "00001", "00001", "11110"],
    " ": ["00000", "00000", "00000", "00000", "00000", "00000", "00000"],
}


## Writes `text` into the top-left of the image at `path`, in place. Returns an error, or "".
static func write(path: String, text: String) -> String:
    var image: Image = Image.load_from_file(path)
    if image == null:
        return "cannot read %s" % path
    draw(image, text, Vector2i(MARGIN, MARGIN))
    return "" if image.save_png(path) == OK else "cannot write %s" % path


## Draws `text` into `image` with its top-left corner at `at`.
static func draw(image: Image, text: String, at: Vector2i) -> void:
    var word: String = text.to_upper()
    var width: int = word.length() * (GLYPH_W + SPACING) * SCALE
    var height: int = GLYPH_H * SCALE
    _plate(image, at, Vector2i(width, height))
    var pen: int = at.x
    for index: int in word.length():
        _glyph(image, word.substr(index, 1), Vector2i(pen, at.y))
        pen += (GLYPH_W + SPACING) * SCALE


## The dark backing, so a white word is readable over a white sky.
static func _plate(image: Image, at: Vector2i, size: Vector2i) -> void:
    for y: int in range(at.y - PLATE_PAD, at.y + size.y + PLATE_PAD):
        for x: int in range(at.x - PLATE_PAD, at.x + size.x + PLATE_PAD):
            if x < 0 or y < 0 or x >= image.get_width() or y >= image.get_height():
                continue
            image.set_pixel(x, y, image.get_pixel(x, y).lerp(PLATE, PLATE.a))


static func _glyph(image: Image, letter: String, at: Vector2i) -> void:
    if not FONT.has(letter):
        return
    var rows: Array = FONT[letter] as Array
    for row: int in rows.size():
        var bits: String = rows[row] as String
        for column: int in bits.length():
            if bits[column] != "1":
                continue
            for y: int in SCALE:
                for x: int in SCALE:
                    var px: int = at.x + column * SCALE + x
                    var py: int = at.y + row * SCALE + y
                    if px < 0 or py < 0 or px >= image.get_width() or py >= image.get_height():
                        continue
                    image.set_pixel(px, py, INK)
