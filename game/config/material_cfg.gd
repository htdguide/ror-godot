class_name MaterialCfg
extends RefCounted
## Material classes and the PBR parameters each one supplies. Data only.
##
## The legacy format stores a texture and a Blinn-Phong pass; it has no metallic, no
## roughness and no notion of what a surface is made of. A class supplies exactly that,
## while the mod's own diffuse texture stays as albedo. See
## docs/decisions/0001-legacy-material-classification.md.
##
## Keys per class:
##   metallic     float
##   roughness    float, used when the mod supplies no specular map
##   clearcoat    float, the second specular lobe automotive paint needs
##   sheen        float, for cloth and leather
##   transmission bool, glass rather than alpha blending
##   emission     float, for lamps and gauges

const CLASSES: Dictionary = {
    # **A painted panel is fully coated, and the coat is 1.0 because that is what a coat is.**
    # This sat at 0.25 for as long as the coat was Godot's own, which does not layer: it trades
    # the paint away for the highlight, so turning the coat up darkened the panels until they read
    # as half transparent and the roll bar showed through the bed side. Tempering the number hid
    # the artefact. `VehiclePaint` fixes the layering instead — measured, a full coat now keeps
    # 0.965 of the paint head-on against the 0.96 a film at IOR 1.5 should — so the coverage can
    # say what it means. The paint under it stays at 0.45: a twenty-year-old truck is not a show
    # car, and that roughness is the paint, not the lacquer over it.
    "car_paint": {
        "metallic": 0.0, "roughness": 0.45, "clearcoat": 1.0, "sheen": 0.0,
        "transmission": false, "emission": 0.0,
    },
    "chrome": {
        "metallic": 1.0, "roughness": 0.08, "clearcoat": 0.0, "sheen": 0.0,
        "transmission": false, "emission": 0.0,
    },
    "bare_metal": {
        "metallic": 1.0, "roughness": 0.35, "clearcoat": 0.0, "sheen": 0.0,
        "transmission": false, "emission": 0.0,
    },
    "glass": {
        "metallic": 0.0, "roughness": 0.05, "clearcoat": 0.0, "sheen": 0.0,
        "transmission": true, "emission": 0.0,
    },
    "rubber": {
        "metallic": 0.0, "roughness": 0.9, "clearcoat": 0.0, "sheen": 0.05,
        "transmission": false, "emission": 0.0,
    },
    "leather_cloth": {
        "metallic": 0.0, "roughness": 0.75, "clearcoat": 0.0, "sheen": 0.3,
        "transmission": false, "emission": 0.0,
    },
    "plastic": {
        "metallic": 0.0, "roughness": 0.5, "clearcoat": 0.0, "sheen": 0.0,
        "transmission": false, "emission": 0.0,
    },
    "rust": {
        "metallic": 0.0, "roughness": 0.85, "clearcoat": 0.0, "sheen": 0.0,
        "transmission": false, "emission": 0.0,
    },
    "lamp": {
        "metallic": 0.0, "roughness": 0.1, "clearcoat": 0.0, "sheen": 0.0,
        "transmission": true, "emission": 0.6,
    },
    "carbon": {
        "metallic": 0.0, "roughness": 0.3, "clearcoat": 1.0, "sheen": 0.0,
        "transmission": false, "emission": 0.0,
    },
    # What an unrecognised material gets. Deliberately dull: a wrong guess that looks
    # expensive is harder to notice than one that looks plain.
    "default": {
        "metallic": 0.0, "roughness": 0.6, "clearcoat": 0.0, "sheen": 0.0,
        "transmission": false, "emission": 0.0,
    },
}

## Name fragments that identify a class, checked in this order so the more specific win.
## Lower-cased substring match against the material name and its texture names.
const NAME_HINTS: Array = [
    ["glass", "glass"], ["window", "glass"], ["windshield", "glass"], ["windscreen", "glass"],
    ["chrome", "chrome"], ["mirror", "chrome"],
    ["tyre", "rubber"], ["tire", "rubber"], ["rubber", "rubber"], ["wheelband", "rubber"],
    ["seat", "leather_cloth"], ["leather", "leather_cloth"], ["cloth", "leather_cloth"],
    ["interior", "leather_cloth"], ["carpet", "leather_cloth"],
    ["carbon", "carbon"],
    ["rust", "rust"],
    ["lamp", "lamp"], ["light", "lamp"], ["flare", "lamp"], ["gauge", "lamp"],
    ["tacho", "lamp"], ["speedo", "lamp"],
    ["alu", "bare_metal"], ["metal", "bare_metal"], ["steel", "bare_metal"],
    ["frame", "bare_metal"], ["axle", "bare_metal"], ["bumper", "bare_metal"],
    ["plastic", "plastic"], ["dash", "plastic"], ["grill", "plastic"],
    ["steer", "plastic"],
    # After "wheelband", so a tyre is rubber and the rim it wraps is metal.
    ["wheel", "bare_metal"], ["rim", "bare_metal"],
]

## The band a roughness derived from a stated Blinn-Phong exponent is held inside.
##
## **The conversion is exact and the inputs are not.** An exponent of 10 converts to 0.639 and one
## of 33 to 0.489, which are reasonable; what the band is for is the ends. A legacy author writing
## a very large exponent meant "shiny", not "a mirror of the sky", and one writing zero meant
## "matte", not "a surface with no highlight anywhere". The 31 specular lines in this checkout
## state 10, 12.5 and 33, so nothing here is currently clamped — the band is what keeps the next
## mod's 2000 from turning a plastic bumper into chrome.
const SHININESS_ROUGHNESS_MIN: float = 0.15
const SHININESS_ROUGHNESS_MAX: float = 0.95

## How polished a clear coat is. Automotive lacquer is near-specular — what it reflects is a
## recognisable image of the sky and not a bloom — and the number is the coat's own, nothing to do
## with the paint under it.
const CLEARCOAT_ROUGHNESS: float = 0.06

## How wide the cloth lobe is. The Charlie distribution's roughness, which is not a
## metallic-roughness roughness: it sets how far around the silhouette the sheen reaches.
const SHEEN_ROUGHNESS: float = 0.3

## How far a texture's own brightness may move a surface's roughness away from its class's
## constant, and the band the result is held inside.
##
## **This is the one derived parameter in the project that is a guess rather than a reading**, and
## it is deliberately a small one. The reasoning is the thin end of a real observation — wear,
## dirt and bare substrate are darker than the finish they sit on, so within one material class a
## darker texture is more often the rougher surface — and it is wrong whenever a surface is simply
## painted a dark colour, which a black car wing is. A swing of 0.12 either way can make a panel
## look a little dirtier or a little fresher than its class says; it cannot turn a panel into a
## mirror or into chalk, and that is the whole of what the bound is for.
##
## **Per material, from the mean, and never per pixel.** A roughness map made from the diffuse's
## own luma paints every logo, decal and letter into the gloss, which is the same failure this
## project refuses derived normal maps for — see PLAN §4.2. One number per material cannot emboss
## anything.
##
## Authored data beats it in both directions: a specular map is per-pixel truth and a stated
## shininess is the author's own number, and either one means this is never consulted.
const LUMA_ROUGHNESS_SWING: float = 0.12
const LUMA_ROUGHNESS_MIN: float = 0.1
const LUMA_ROUGHNESS_MAX: float = 0.98
## What a texture is resized to before its mean is taken.
##
## **A downsample rather than a stride.** Reading every eighth pixel of a level crossing's stripes
## samples the stripes, not the surface: two such means of the same image taken at different steps
## came out 0.11 apart, which is most of the swing this derivation is allowed. A resize averages
## every pixel into the result, costs less than walking the image in GDScript, and gives the same
## answer whatever grid it is asked for.
const LUMA_SAMPLE_SIZE: int = 16

## Roughness is derived from a specular map as 1 - specular, then pulled toward the middle
## of this range: a legacy specular map is an artist's intensity mask rather than a
## measured reflectance, so taking it literally produces mirrors and chalk.
## The floor matters more than the ceiling: a legacy specular map is an artist's mask,
## and a bright one taken literally drives roughness to zero and turns a panel into a
## mirror of the sky.
const SPEC_ROUGHNESS_MIN: float = 0.35
const SPEC_ROUGHNESS_MAX: float = 0.95
