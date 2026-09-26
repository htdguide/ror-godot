extends GateBase
## The cab shows what the vehicle is doing: the needles read the drivetrain and the steering wheel
## turns with the steering.
##
## These are instruments rather than a HUD, which is the point of them: geometry in the cab,
## parented to the dashboard the mod supplies, moving and lit with it. A number in the corner of
## the screen tells you the same thing and tells you nothing about whether the vehicle is right.
##
## The mod has no needle to animate — its dials are painted into the dashboard texture and it
## declares no animators — so the cluster is built by this project from `CockpitCfg`, and what is
## checked here is that the geometry it builds actually follows the solver: a needle at the angle
## the dial's own sweep says, and a wheel turned by the ratio the vehicle's own file declares.

const MOD_DIR: String = "assets/mods/ChevyS1023"
const TRUCK: String = "S10offroad.truck"
## How close a needle has to sit to the angle its dial implies. A hundredth of a degree: this is
## arithmetic, not a measurement, and the only reason it is not exact is the float it travels in.
const ANGLE_TOLERANCE_DEG: float = 0.01
## The steering wheel's own ratio comes from the file; this is how closely the mesh has to follow
## it.
const WHEEL_TOLERANCE_DEG: float = 0.05


static func meta() -> Dictionary:
    return {
        "name": "cockpit_tracks_the_drivetrain",
        "proves": "the cab's needles point at what the engine and the wheels are doing, and the steering wheel turns by the ratio the vehicle's own file declares",
        # the props have to be built and placed before what is mounted on them can be checked.
        "builds_on": ["props_sit_in_the_vehicle"],
        "oracle": GateBase.ORACLE_COMPUTED,
        "threshold": (
            "every needle within %.2f degrees of its dial's own sweep, and the wheel within"
            % ANGLE_TOLERANCE_DEG
            + " %.2f degrees of the file's ratio" % WHEEL_TOLERANCE_DEG
        ),
        "why": (
            "instruments in the cab are the thing a driver actually reads, and a needle that"
            + " does not move is indistinguishable from a vehicle that is not doing anything."
            + " The angles are arithmetic, so they are checked as arithmetic rather than looked"
            + " at."
        ),
        "budget_s": 60.0,
        "needs_gpu": true,
        "milestone": "M1",
    }


func run(harness: Node) -> Dictionary:
    var mod_dir: String = SourceScan.repo_root().path_join(MOD_DIR)
    if not DirAccess.dir_exists_absolute(mod_dir):
        return ok("skipped: hero asset not present at %s" % MOD_DIR, 0)
    var err: String = harness.setup_for("hero_3q")
    if err != "":
        return fail(err)
    var built: Dictionary = VehicleBuilder.build(mod_dir, TRUCK)
    if (built.get("error", "") as String) != "":
        return fail(built["error"] as String)
    var truck: TruckParser = built["truck"] as TruckParser
    harness.world.add_child(built["root"] as Node3D)

    var cluster: Node3D = Cockpit.build(built["root"] as Node3D, truck, built)
    if cluster == null:
        return fail("%s has a dashboard prop but no cluster was built on it" % TRUCK)

    var reported: PackedStringArray = PackedStringArray()
    for case: Array in [
        [0.0, 0.0], [1500.0, 10.0], [3000.0, 22.0], [CockpitCfg.TACHO_MAX_RPM, 60.0],
    ]:
        var rpm: float = float(case[0])
        var speed: float = float(case[1])
        Cockpit.update(cluster, rpm, speed, false)
        var tacho: float = _needle_degrees(cluster, "Tacho")
        var speedo: float = _needle_degrees(cluster, "Speedo")
        var tacho_wanted: float = _wanted_degrees(rpm / CockpitCfg.TACHO_MAX_RPM)
        var speedo_wanted: float = _wanted_degrees(speed * 3.6 / CockpitCfg.SPEEDO_MAX_KMH)
        if absf(tacho - tacho_wanted) > ANGLE_TOLERANCE_DEG:
            return fail(
                "at %.0f rpm the tacho needle is at %.2f degrees, not the %.2f its sweep implies"
                % [rpm, tacho, tacho_wanted],
                tacho - tacho_wanted
            )
        if absf(speedo - speedo_wanted) > ANGLE_TOLERANCE_DEG:
            return fail(
                "at %.1f m/s the speedo needle is at %.2f degrees, not the %.2f its sweep implies"
                % [speed, speedo, speedo_wanted],
                speedo - speedo_wanted
            )
        reported.append("%.0f rpm %.1f deg, %.0f km/h %.1f deg" % [
            rpm, tacho, speed * 3.6, speedo])

    # The backlight: dark with the lights off, lit with them on. A dial a driver cannot read at
    # night is a dial that is not finished.
    Cockpit.update(cluster, 1000.0, 5.0, true)
    var lit: float = _backlight(cluster)
    Cockpit.update(cluster, 1000.0, 5.0, false)
    var dark: float = _backlight(cluster)
    if lit <= dark:
        return fail(
            "the dials glow at %.2f with the lights on and %.2f with them off: the backlight does"
            % [lit, dark] + " nothing",
            lit - dark
        )

    var wheel: String = _check_wheel(built, truck)
    if wheel != "":
        return fail(wheel)
    return ok(
        "needles: %s; backlight %.2f against %.2f; the wheel follows its file's ratio"
        % [", ".join(reported), lit, dark],
        lit - dark
    )


## The angle a dial's sweep implies for a share of its range, in degrees.
func _wanted_degrees(share: float) -> float:
    return CockpitCfg.SWEEP_START_DEG + CockpitCfg.SWEEP_DEG * clampf(share, 0.0, 1.0)


## Where a needle actually points, in the same degrees.
func _needle_degrees(cluster: Node3D, dial: String) -> float:
    var needle: Node3D = cluster.get_node_or_null(NodePath("%s/Needle" % dial)) as Node3D
    if needle == null:
        return NAN
    # The needle turns about the dial's own facing axis, so its rotation about that axis is the
    # reading. Negated because a dial sweeps clockwise and Godot's rotations are the other way.
    return rad_to_deg(-needle.transform.basis.get_euler().z)


func _backlight(cluster: Node3D) -> float:
    var face: MeshInstance3D = cluster.get_node_or_null(^"Tacho/Face") as MeshInstance3D
    if face == null:
        return 0.0
    var material: StandardMaterial3D = face.material_override as StandardMaterial3D
    return material.emission_energy_multiplier if material != null else 0.0


## The steering wheel, turned by the ratio the file declares. Returns "" when it follows.
func _check_wheel(built: Dictionary, truck: TruckParser) -> String:
    var ratio: float = 0.0
    var wheel: Node3D = null
    var props: Array[Node3D] = built["prop_nodes"] as Array[Node3D]
    for index: int in mini(props.size(), truck.props.size()):
        if (truck.props[index]["steering_mesh"] as String).is_empty():
            continue
        ratio = float(truck.props[index]["steering_deg_per_input"])
        wheel = props[index].get_node_or_null(^"SteeringWheel") as Node3D
        break
    if wheel == null:
        return "%s declares no steering wheel mesh on any prop" % TRUCK
    if absf(ratio) < 1.0:
        return "the steering wheel's ratio reads %.2f degrees per unit: the file's last field on" \
            % ratio + " the props row is not being read"
    for input: float in [0.0, 0.5, -1.0]:
        Cockpit.turn_wheel(built, truck, input)
        var turned: float = rad_to_deg(
            wheel.transform.basis.get_euler(PlacementRows.PROP_EULER_ORDER).z
        )
        var wanted: float = ratio * input
        if absf(wrapf(turned - wanted, -180.0, 180.0)) > WHEEL_TOLERANCE_DEG:
            return (
                "at a steering input of %+.1f the wheel is turned %.2f degrees, not the %.2f its"
                % [input, turned, wanted] + " ratio of %.0f implies" % ratio
            )
    Cockpit.turn_wheel(built, truck, 0.0)
    return ""
