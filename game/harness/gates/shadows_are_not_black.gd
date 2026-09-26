extends GateBase
## A surface in shadow, and a surface facing away from the sun, both still show what they are.
##
## Reported in a session: "shadows are too dark from one side and everything is fine on another".
## That is not the same complaint as the scene being dark overall, and it needs its own
## measurement — a sunlit ground reading 0.5 and the shadow beside it reading 0.01 is a picture
## with a hole in it, whatever the average brightness says.
##
## So this puts a box on the ground in the light and reads three places in one frame: the ground
## in the sun, the ground in the box's own cast shadow, and the box's face on the side the sun
## cannot reach. The last two are where everything a session looks at lives — a ramp's face, a
## rock's shape, the suspension's geometry on the shaded side of a truck.
##
## The bound is a contrast ratio rather than a brightness, because brightness is the grading's
## business and this is about whether there is anything left in the dark part of the frame. Print
## and film hold about 1:8 between a lit subject and its own shadow before the shadow stops
## carrying detail; a renderer with no fill and no bounce will happily reach 1:40.

const PRESET: String = "diag_origin"
const SETTLE_FRAMES: int = 3
## The box: big enough to cast a shadow the camera can see across, small enough to stay in frame.
const BOX_SIZE: float = 4.0
const GROUND_SIZE: float = 40.0
const ALBEDO: Color = Color(0.35, 0.35, 0.35)
## Where the camera stands, and what it looks at: the ground beside the box, from the side away
## from the sun, so that lit ground, shadowed ground and the box's shaded face are all in shot.
const EYE: Vector3 = Vector3(-9.0, 5.5, -9.0)
const AIM: Vector3 = Vector3(0.0, 1.0, 0.0)
## Half the side of each sampled window, in pixels.
const WINDOW_PX: int = 24
## What the shadow has to hold, and how far the sunlit ground may be above it.
##
## Print and film hold about 1:8 before a shadow stops carrying detail, and these are tighter than
## that on purpose: they are the measured values with margin — 0.115 in the shadow at 2.4x — so
## that removing the fill light or taking the shadows back to full depth fails here rather than
## being noticed in a session. Measured without the fill and at full depth: 0.060 at 4.3x.
const MIN_SHADOW_LUMA: float = 0.085
const MAX_CONTRAST: float = 3.5


static func meta() -> Dictionary:
    return {
        "name": "shadows_are_not_black",
        "proves": "ground in cast shadow and a face turned away from the sun both keep enough light to read, and the sun-to-shadow contrast stays inside what an image can hold",
        # a frame has to render before what is in its dark parts can be measured.
        "builds_on": ["smoke"],
        "oracle": GateBase.ORACLE_INVARIANT,
        "threshold": (
            "shadowed ground at least %.3f display luma, and sunlit ground at most %.0fx it"
            % [MIN_SHADOW_LUMA, MAX_CONTRAST]
        ),
        "why": (
            "a session reported one side of everything reading as black while the other was"
            + " fine, which is a different fault from the scene being dark and wants a different"
            + " fix: fill and shadow depth rather than exposure. Print holds about 1:8 between a"
            + " subject and its shadow before the shadow stops carrying detail; a renderer with"
            + " no fill reaches 1:40 without trying."
        ),
        "budget_s": 120.0,
        "needs_gpu": true,
        "milestone": "M2b",
    }


func run(harness: Node) -> Dictionary:
    var err: String = harness.setup_for(PRESET)
    if err != "":
        return fail(err)
    _hide_props(harness)
    var sun: DirectionalLight3D = harness.world.get_node_or_null(^"Sun") as DirectionalLight3D
    if sun == null:
        return fail("the world has no sun, so nothing casts a shadow")

    harness.world.add_child(_ground())
    var box: MeshInstance3D = _box()
    harness.world.add_child(box)
    harness.camera.look_at_from_position(EYE, AIM, Vector3.UP)
    await harness.advance_frames(1, "static", "shadow")

    # Where the shadow falls: along the sun's own direction from the box, on the ground.
    var toward_sun: Vector3 = -sun.global_transform.basis.z
    var away: Vector3 = Vector3(-toward_sun.x, 0.0, -toward_sun.z).normalized()
    var shadow_at: Vector3 = away * (BOX_SIZE * 0.85)
    # The sunlit sample goes *beside* the box rather than on the far side of it: the far side is
    # behind the box from this camera, and the first version of this gate sampled the box's own
    # shaded face there and reported a contrast of 1.3 whatever the lighting did.
    var across: Vector3 = Vector3(away.z, 0.0, -away.x).normalized()
    var lit_at: Vector3 = across * (BOX_SIZE * 1.4)
    # And the box's own shaded face: the middle of the side the sun cannot see.
    var shaded_face: Vector3 = away * (BOX_SIZE * 0.5 + 0.01) + Vector3(0.0, BOX_SIZE * 0.5, 0.0)

    var shot: Dictionary = await harness.capture_shot("shadows", "static", SETTLE_FRAMES)
    if (shot["error"] as String) != "":
        return fail(shot["error"] as String)
    var image: Image = Image.load_from_file(shot["png"] as String)
    if image == null:
        return fail("the capture at %s could not be read" % shot["png"])

    var camera: Camera3D = harness.camera
    var lit: float = _window(image, camera.unproject_position(lit_at))
    var shadow: float = _window(image, camera.unproject_position(shadow_at))
    var face: float = _window(image, camera.unproject_position(shaded_face))
    if lit <= shadow:
        return fail(
            "the ground in the sun reads %.4f and its own shadow %.4f: the samples are not where"
            % [lit, shadow] + " they are meant to be. See %s" % shot["png"],
            lit - shadow
        )
    if shadow < MIN_SHADOW_LUMA:
        return fail(
            "ground in shadow displays at %.4f, under %.3f: there is nothing in it. See %s"
            % [shadow, MIN_SHADOW_LUMA, shot["png"]],
            shadow
        )
    if face < MIN_SHADOW_LUMA:
        return fail(
            "the face turned away from the sun displays at %.4f, under %.3f: one side of every"
            % [face, MIN_SHADOW_LUMA]
            + " object is a silhouette. See %s" % shot["png"],
            face
        )
    var contrast: float = lit / maxf(shadow, 0.0001)
    if contrast > MAX_CONTRAST:
        return fail(
            "sunlit ground is %.1fx its own shadow (%.4f against %.4f), over %.0fx: the shadow is"
            % [contrast, lit, shadow, MAX_CONTRAST] + " a hole. See %s" % shot["png"],
            contrast
        )
    return ok(
        "sunlit %.4f, its shadow %.4f (%.1fx), the face away from the sun %.4f"
        % [lit, shadow, contrast, face],
        contrast
    )


func _ground() -> MeshInstance3D:
    var plane: PlaneMesh = PlaneMesh.new()
    plane.size = Vector2(GROUND_SIZE, GROUND_SIZE)
    var instance: MeshInstance3D = MeshInstance3D.new()
    instance.name = "ShadowGround"
    instance.mesh = plane
    instance.material_override = _material()
    return instance


func _box() -> MeshInstance3D:
    var mesh: BoxMesh = BoxMesh.new()
    mesh.size = Vector3(BOX_SIZE, BOX_SIZE, BOX_SIZE)
    var instance: MeshInstance3D = MeshInstance3D.new()
    instance.name = "ShadowCaster"
    instance.mesh = mesh
    instance.material_override = _material()
    instance.position = Vector3(0.0, BOX_SIZE * 0.5, 0.0)
    return instance


func _material() -> StandardMaterial3D:
    var material: StandardMaterial3D = StandardMaterial3D.new()
    material.albedo_color = ALBEDO
    material.roughness = 0.9
    material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
    return material


func _window(image: Image, centre: Vector2) -> float:
    var size: Vector2i = image.get_size()
    var total: float = 0.0
    var counted: int = 0
    for y: int in range(
        clampi(int(centre.y) - WINDOW_PX, 0, size.y - 1),
        clampi(int(centre.y) + WINDOW_PX, 1, size.y)
    ):
        for x: int in range(
            clampi(int(centre.x) - WINDOW_PX, 0, size.x - 1),
            clampi(int(centre.x) + WINDOW_PX, 1, size.x)
        ):
            var colour: Color = image.get_pixel(x, y)
            total += colour.r * 0.2126 + colour.g * 0.7152 + colour.b * 0.0722
            counted += 1
    return total / float(maxi(counted, 1))


## The blockout world's own scale props would stand in the shot.
func _hide_props(harness: Node) -> void:
    for child: Node in harness.world.get_children():
        var mesh: MeshInstance3D = child as MeshInstance3D
        if mesh != null:
            mesh.visible = false
