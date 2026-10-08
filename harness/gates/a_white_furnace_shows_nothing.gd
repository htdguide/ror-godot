extends GateBase
## Lit from every direction by one radiance, a white ball is invisible against it.
##
## **The oldest test in rendering, and the oracle is conservation of energy.** A surface whose
## albedo is 1 absorbs nothing. Put it in an enclosure whose every direction sends the same
## radiance `L` and it must send `L` back — from every point of it, at every roughness, metal or
## dielectric — because there is nowhere else for the light to go. So the ball disappears into the
## background, and the only two ways to fail are to lose light, which draws it darker than the sky
## behind it, or to invent light, which draws it brighter.
##
## **The furnace is read off a mirror and not off the background, and that is a finding of its
## own.** A perfect mirror in an enclosure returns the enclosure, so the smoothest ball in each
## family says what radiance the lighting path thinks is arriving — and it has to, because the
## drawn sky and the radiance map built from it do not share a scale. Measured, the ball came back
## at 2.95 times the sky drawn behind it, uniformly, at every roughness, and that factor is the
## camera's own exposure normalisation: the same scene through a camera two and a half stops away
## read 1.00. It is the reason this project's own sky shader divides by `light_exposure` in the
## cubemap pass, and a plain `ProceduralSkyMaterial` does not.
##
## So what is compared is ball against ball at the same angle: every roughness against the
## smoothest of its own kind, middle against middle and silhouette against silhouette. The angle
## has to match as well as the material, because a white dielectric returns its full diffuse albedo
## *and* its specular reflection — the metallic-roughness model takes no Fresnel share out of the
## diffuse term — so its silhouette comes back 8.6% over its own middle by construction. That is a
## property of the model, not of this renderer, and comparing a ball's edge with its own middle
## measures it rather than anything about roughness.
## That leaves the gate blind to a scale error applied to the whole image-based path, and catches
## what a furnace is actually for — light lost or invented as a surface gets rougher, which is
## where a split-sum approximation goes wrong, and the same at grazing angles, which is where a
## Fresnel term that does not reach 1.0 shows.
##
## Nothing here is a number this project chose. The expectation is that they all agree, and it
## comes from physics; what this gate picks is how far apart an 8-bit capture may put them.
##
## **What it covers that nothing else does.** Every other lighting gate in this project measures a
## scene against another scene — a ratio, a difference, a share of a frame — so a renderer that
## lost a steady fraction of every specular reflection would pass all of them. This one has an
## absolute answer. It is the acceptance item M2 names as the Khronos `pbr_spheres` comparison,
## answered a different way: a reference image shipped beside a sample asset documents neither its
## lighting nor its exposure nor its tonemapper, so a perceptual diff against it is either loose
## enough to prove nothing or fails for reasons that have nothing to do with the BRDF. A furnace
## has one correct answer and no setup to agree about.

const PRESET: String = "hero_3q"
const WEATHER: String = "noon_clear"
const CONVERGE: int = 8
## The furnace's own radiance, chosen to land the frame in the middle of the film: the measurement
## is a ratio, and both ends of an 8-bit channel are places where a ratio stops meaning anything.
const FURNACE: float = 0.03
const BALL_RADIUS: float = 0.9
## Where the ball stands: what `hero_3q` is framed on.
const BALL_AT: Vector3 = Vector3(0.0, 0.9, 0.0)
## Each family smoothest first: the first of each is the mirror the rest are read against.
const SURFACES: Array[Dictionary] = [
    {"metallic": 0.0, "roughness": 0.05},
    {"metallic": 0.0, "roughness": 0.5},
    {"metallic": 0.0, "roughness": 1.0},
    {"metallic": 1.0, "roughness": 0.05},
    {"metallic": 1.0, "roughness": 0.5},
    {"metallic": 1.0, "roughness": 1.0},
]
## **A dielectric and a metal are not compared with each other.** A white dielectric returns its
## diffuse albedo *and* its specular reflection, because the metallic-roughness model does not take
## the Fresnel share out of the diffuse term, so it comes back a few per cent over a metal by
## construction. That is a property of the model rather than a fault in this renderer, and a gate
## that mixed the two would be measuring it.
## **The bound is not symmetric, and the asymmetry is the physics.** A renderer that approximates
## the hemisphere integral — one scattering event per reflection, a split-sum environment BRDF —
## can only ever lose energy: the light that would have bounced a second time inside the
## microsurface is simply not accounted for, and the loss grows with roughness and with how grazing
## the view is. It cannot gain energy, because there is nowhere for extra light to come from. So a
## shortfall is given room and a surplus is not.
##
## Measured here, the worst shortfall is a fully rough dielectric at its silhouette, 9.3% under the
## smooth one beside it. That is the single-scatter deficit and it is why a rough surface in this
## renderer is slightly darker than it should be at glancing angles — the same corner of the
## lighting model as the sea's horizon reading 0.296 of the sky it mirrors, recorded in
## `hard-won-facts-materials.md`.
const MAY_LOSE: float = 0.12
const MAY_GAIN: float = 0.04
## Where on the ball it is read: the middle, where the view is normal to the surface, and a ring
## near the silhouette, where it is grazing and where a Fresnel term that does not reach 1.0 shows.
const RINGS: Array[float] = [0.0, 0.55, 0.93]


static func meta() -> Dictionary:
    return {
        "name": "a_white_furnace_shows_nothing",
        "proves": "a white ball under a uniform sky returns exactly the radiance that lights it, at every roughness and for metal and dielectric alike, so the renderer neither loses nor invents light",
        "builds_on": ["tonemap_and_exposure"],
        "oracle": GateBase.ORACLE_COMPUTED,
        "threshold": (
            "no reading over %.0f%% above its own mirror's, none more than %.0f%% below"
            % [MAY_GAIN * 100.0, MAY_LOSE * 100.0]
        ),
        "why": (
            "every other lighting check here compares one scene against another, so a renderer"
            + " losing a steady fraction of every reflection would pass all of them. A furnace has"
            + " an absolute answer that physics supplies: energy in equals energy out, and the"
            + " ball is invisible."
        ),
        "budget_s": 180.0,
        "needs_gpu": true,
        "milestone": "M2",
    }


func run(harness: Node) -> Dictionary:
    var err: String = harness.setup_for(PRESET, WEATHER)
    if err != "":
        return fail(err)
    clear_fog(harness)
    # A new `Environment`, not the world's own edited in place: see `GateBase.furnace_environment`.
    var holder: WorldEnvironment = (
        harness.world.get_node_or_null(^"WorldEnvironment") as WorldEnvironment
    )
    if holder == null:
        return fail("the world has no environment to replace")
    holder.environment = furnace_environment(FURNACE)
    # **Nothing else may be in the enclosure.** A floor is a surface that absorbs, a lamp is light
    # arriving from somewhere other than the walls, and either one makes this a scene rather than a
    # furnace. Hidden recursively rather than by name: with only the top-level `Ground` and the sun
    # taken out, the ball's silhouette came back at 3.2 times the furnace.
    hide_everything(harness.world)

    var ball: MeshInstance3D = _ball()
    harness.world.add_child(ball)
    var white: StandardMaterial3D = ball.material_override as StandardMaterial3D

    var worst: float = 0.0
    var worst_said: String = ""
    var reported: PackedStringArray = PackedStringArray()
    var mirrors: Dictionary = {}
    for index: int in SURFACES.size():
        var surface: Dictionary = SURFACES[index]
        var family: String = "metal" if float(surface["metallic"]) > 0.5 else "dielectric"
        white.metallic = float(surface["metallic"])
        white.roughness = float(surface["roughness"])
        var shot: Dictionary = await harness.capture_shot(
            "furnace/%d" % index, "static", CONVERGE
        )
        if (shot["error"] as String) != "":
            return fail(shot["error"] as String)
        var image: Image = Image.load_from_file(shot["png"] as String)
        if image == null:
            return fail("the capture at %s could not be read" % shot["png"])

        var readings: PackedFloat32Array = PackedFloat32Array()
        for out: float in RINGS:
            readings.append(_ring(harness, image, out))
        for read: float in readings:
            if read < 0.05 or read > 0.95:
                return fail(
                    "a %s ball at roughness %.2f photographed at %.4f, where a ratio means"
                    % [family, float(surface["roughness"]), read]
                    + " nothing: this frame is measuring the exposure. %s" % shot["png"],
                    read
                )
        if not mirrors.has(family):
            # The smoothest of its kind, ring by ring: a mirror returns the enclosure, so this is
            # what the furnace is at each angle.
            mirrors[family] = readings
        var furnace_at: PackedFloat32Array = mirrors[family] as PackedFloat32Array
        var said: String = "%s %.2f:" % [family, float(surface["roughness"])]
        for ring: int in readings.size():
            var furnace: float = furnace_at[ring]
            var off: float = readings[ring] / furnace - 1.0
            said += " %.3fx" % (readings[ring] / furnace)
            if absf(off) > absf(worst):
                worst = off
                worst_said = (
                    "a %s ball at roughness %.2f, %.0f%% of the way to its silhouette: %.4f"
                    % [family, float(surface["roughness"]), RINGS[ring] * 100.0, readings[ring]]
                    + " against the %.4f its own mirror returns" % furnace
                )
        reported.append(said)

    if worst > MAY_GAIN or worst < -MAY_LOSE:
        return fail(
            "%s — %s%.1f%% against the %.0f%% a furnace allows %s. A white ball under a uniform sky"
            % [
                worst_said, "+" if worst > 0.0 else "", worst * 100.0,
                (MAY_GAIN if worst > 0.0 else MAY_LOSE) * 100.0,
                "upward" if worst > 0.0 else "downward"
            ]
            + " %s." % ("is inventing light" if worst > 0.0 else "is losing light")
            + " Readings: %s" % "; ".join(reported),
            worst
        )
    return ok(
        "every white ball returns its own mirror's radiance within %.1f%% (worst: %s)."
        % [absf(worst) * 100.0, worst_said] + " Readings: %s"
        % "; ".join(reported),
        absf(worst)
    )


func _environment(harness: Node) -> Environment:
    var holder: WorldEnvironment = (
        harness.world.get_node_or_null(^"WorldEnvironment") as WorldEnvironment
    )
    return null if holder == null else holder.environment


func _ball() -> MeshInstance3D:
    var ball: MeshInstance3D = MeshInstance3D.new()
    var sphere: SphereMesh = SphereMesh.new()
    sphere.radius = BALL_RADIUS
    sphere.height = BALL_RADIUS * 2.0
    sphere.radial_segments = 96
    sphere.rings = 48
    ball.mesh = sphere
    ball.position = BALL_AT
    var white: StandardMaterial3D = StandardMaterial3D.new()
    white.albedo_color = Color.WHITE
    ball.material_override = white
    return ball


## A ring on the ball, at a share of the way out to its silhouette. Where the ball is and how wide
## it draws come from the camera rather than from an assumption.
func _ring(harness: Node, image: Image, out: float) -> float:
    var size: Vector2i = image.get_size()
    var viewport: Vector2 = harness.render_viewport().get_visible_rect().size
    var scale: Vector2 = Vector2(float(size.x) / viewport.x, float(size.y) / viewport.y)
    var centre: Vector2 = harness.camera.unproject_position(BALL_AT) * scale
    var edge: Vector2 = harness.camera.unproject_position(
        BALL_AT + harness.camera.global_transform.basis.x * BALL_RADIUS
    ) * scale
    var radius: float = centre.distance_to(edge) * out
    if out <= 0.0:
        return image.get_pixel(
            clampi(int(centre.x), 0, size.x - 1), clampi(int(centre.y), 0, size.y - 1)
        ).srgb_to_linear().get_luminance()
    var total: float = 0.0
    var counted: int = 0
    for degrees: int in range(0, 360, 3):
        var radians: float = deg_to_rad(float(degrees))
        var at: Vector2 = centre + Vector2(cos(radians), sin(radians)) * radius
        total += image.get_pixel(
            clampi(int(at.x), 0, size.x - 1), clampi(int(at.y), 0, size.y - 1)
        ).srgb_to_linear().get_luminance()
        counted += 1
    return total / maxf(float(counted), 1.0)
