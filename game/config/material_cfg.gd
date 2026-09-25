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
    # Tempered from clearcoat 0.8 / roughness 0.25, which made body panels behave like
    # mirrors: from any angle facing the sky they showed a blurred reflection of the
    # world and read as half transparent, with the vehicle's own roll bar appearing
    # through its bed side. A twenty-year-old truck is not a show car.
    "car_paint": {
        "metallic": 0.0, "roughness": 0.45, "clearcoat": 0.25, "sheen": 0.0,
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
        "metallic": 0.0, "roughness": 0.3, "clearcoat": 0.6, "sheen": 0.0,
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

## Roughness is derived from a specular map as 1 - specular, then pulled toward the middle
## of this range: a legacy specular map is an artist's intensity mask rather than a
## measured reflectance, so taking it literally produces mirrors and chalk.
## The floor matters more than the ceiling: a legacy specular map is an artist's mask,
## and a bright one taken literally drives roughness to zero and turns a panel into a
## mirror of the sky.
const SPEC_ROUGHNESS_MIN: float = 0.35
const SPEC_ROUGHNESS_MAX: float = 0.95
