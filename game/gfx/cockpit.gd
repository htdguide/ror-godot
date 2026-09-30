class_name Cockpit
extends RefCounted
## The driver's instruments, built into the cab and driven by the drivetrain.
##
## Two dials — engine speed and road speed — with needles that move, ticks around them, and a
## backlight that comes on with the headlights. They are geometry in the world, parented to the
## vehicle, so they move with it, tilt with it, and are lit by whatever lights the cab. That is
## the difference between an instrument and a HUD: a HUD tells you the number, an instrument is
## part of the thing you are driving.
##
## The mod's own dials are painted into its dashboard texture with no needle mesh and no animator
## rows, so there is nothing in the file to animate. Upstream draws its own dashboard overlay for
## the same reason. These are built from `CockpitCfg`, placed from the dashboard prop's own frame,
## and stay with it when the cab deforms because the prop does.
##
## The steering wheel is the mod's own mesh, turned about its column by the steering: that one is
## not drawn here, only rotated — see `turn_wheel`.

## Which prop is the dashboard, by what its mesh is called. The file names it; nothing else in a
## rig is called that. Used to find the steering wheel, which is a child of that prop.
const DASHBOARD_MARK: String = "dashboard"


## Builds the cluster under `vehicle_root` and returns it, or null when the rig declares no cab to
## put it in.
##
## Mounted on the vehicle rather than on the dashboard prop, and placed from the driver's eye. The
## prop's own frame is the mod's — the hero truck turns its dashboard by -95, 0, 180 degrees — so
## an offset in that frame is an offset in no particular direction, and the first version of this
## put the dials in the driver's face. The eye is the rig's own cinecam, and the vehicle's local
## frame has -Z ahead and +Y up, which is a frame a person can reason in.
static func build(vehicle_root: Node3D, truck: TruckParser, built: Dictionary) -> Node3D:
    if truck.cinecams.is_empty():
        return null
    var eye: Vector3 = (built["rig_to_local"] as Transform3D) * eye_position(truck)
    var cluster: Node3D = Node3D.new()
    cluster.name = "Cockpit"
    cluster.transform = Transform3D(
        Basis.from_euler(Vector3(
            deg_to_rad(CockpitCfg.TILT_DEG.x), deg_to_rad(CockpitCfg.TILT_DEG.y),
            deg_to_rad(CockpitCfg.TILT_DEG.z)
        )),
        dials_position(truck, built)
    )
    cluster.add_child(_dial("Tacho", -CockpitCfg.DIAL_SPACING_M * 0.5))
    cluster.add_child(_dial("Speedo", CockpitCfg.DIAL_SPACING_M * 0.5))
    vehicle_root.add_child(cluster)
    return cluster


## Points the needles at what the drivetrain is doing and sets the backlight.
##
## `rpm` and `speed_ms` are the solver's own; the dials' ends are in `CockpitCfg`, so a rig with a
## different red line shows the same sweep against different numbers rather than a needle off the
## end of its dial.
static func update(cluster: Node3D, rpm: float, speed_ms: float, lit: bool) -> void:
    if cluster == null:
        return
    _point(cluster.get_node_or_null(^"Tacho"), clampf(rpm / CockpitCfg.TACHO_MAX_RPM, 0.0, 1.0))
    _point(
        cluster.get_node_or_null(^"Speedo"),
        clampf(absf(speed_ms) * 3.6 / CockpitCfg.SPEEDO_MAX_KMH, 0.0, 1.0)
    )
    var energy: float = CockpitCfg.BACKLIGHT_ON if lit else CockpitCfg.BACKLIGHT_OFF
    for dial: String in ["Tacho", "Speedo"]:
        var face: MeshInstance3D = cluster.get_node_or_null(
            NodePath("%s/Face" % dial)
        ) as MeshInstance3D
        if face == null:
            continue
        var material: StandardMaterial3D = face.material_override as StandardMaterial3D
        if material != null:
            material.emission_energy_multiplier = energy


## Turns the mod's own steering wheel by the steering, through the ratio its file declares.
##
## The ratio is the last number on the `props` row — degrees of wheel rotation per unit of
## steering input — and the rake is already in the wheel's resting transform, so this turns it
## about its own local axis rather than rebuilding the basis.
static func turn_wheel(built: Dictionary, truck: TruckParser, steer_state: float) -> void:
    var props: Array[Node3D] = built.get("prop_nodes", [] as Array[Node3D]) as Array[Node3D]
    for index: int in mini(props.size(), truck.props.size()):
        var entry: Dictionary = truck.props[index]
        if (entry["steering_mesh"] as String).is_empty():
            continue
        var wheel: Node3D = props[index].get_node_or_null(^"SteeringWheel") as Node3D
        if wheel == null:
            continue
        var degrees: float = float(entry["steering_deg_per_input"]) * steer_state
        wheel.transform.basis = steering_basis(degrees)


## How a steering wheel sits at a given amount of lock.
##
## Upstream's chain for a steering prop is: the prop's own rotation, then a rake about x, then
## the steering angle about **y** — `Quaternion(rake, UNIT_X) * Quaternion(steer, UNIT_Y)`. The
## order matters and so does the axis: composed the other way round, or about z, the wheel turns
## about an axis that is not its column, which a session reported as the wheel "not spinning
## around its correct axle". The rake is this project's measured 121 degrees rather than
## upstream's -59; see `PlacementRows`.
static func steering_basis(degrees: float) -> Basis:
    return (
        Basis(Vector3.RIGHT, deg_to_rad(PlacementRows.STEERING_COLUMN_RAKE_DEG))
        * Basis(Vector3.UP, deg_to_rad(degrees))
    )


## Where the cluster stands in the vehicle's own frame.
##
## On the dashboard where there is one, which is what a dashboard is for, and from the driver's
## eye where a rig has no dashboard prop. Only the prop's position is used: its basis is the
## mod's own and points nowhere in particular.
static func dials_position(truck: TruckParser, built: Dictionary) -> Vector3:
    var eye: Vector3 = (built["rig_to_local"] as Transform3D) * eye_position(truck)
    var wheel: AABB = _steering_wheel_box(truck, built)
    if wheel.size == Vector3.ZERO:
        return eye + CockpitCfg.EYE_TO_DIALS_M
    # Ahead of the wheel, on the driver's own centre line, and low enough to be a glance.
    var z: float = wheel.position.z - CockpitCfg.DIALS_AHEAD_OF_WHEEL_M
    var drop: float = (eye.z - z) * tan(deg_to_rad(CockpitCfg.GLANCE_DEG))
    return Vector3(wheel.get_center().x, eye.y - drop, z)


## The steering wheel's own box in the vehicle's frame, or a zero box when the rig has none.
##
## The wheel is the one thing in a cab that is always where a cab is: a dashboard prop can be a
## placeholder — the hero truck's is 0.8 mm across, because its dashboard is painted into the cab
## mesh — and a cinecam can be anywhere the mod hung it.
static func _steering_wheel_box(truck: TruckParser, built: Dictionary) -> AABB:
    var props: Array[Node3D] = built.get("prop_nodes", [] as Array[Node3D]) as Array[Node3D]
    for index: int in mini(props.size(), truck.props.size()):
        if (truck.props[index]["steering_mesh"] as String).is_empty():
            continue
        var wheel: MeshInstance3D = props[index].get_node_or_null(
            ^"SteeringWheel"
        ) as MeshInstance3D
        if wheel == null or wheel.mesh == null:
            continue
        return props[index].transform * (wheel.transform * wheel.mesh.get_aabb())
    return AABB()


## Where the driver's eye is, in the rig's own space, or the vehicle's centre when the file
## declares no cinecam in the cab.
static func eye_position(truck: TruckParser) -> Vector3:
    if truck.cinecams.is_empty():
        return Vector3.ZERO
    var index: int = mini(CockpitCfg.DRIVER_CINECAM_INDEX, truck.cinecams.size() - 1)
    return truck.cinecams[index] + CockpitCfg.EYE_OFFSET_M


## --------------------------------------------------------------------------------


## The prop node carrying the dashboard mesh, which is where the cluster is mounted.
static func _dashboard_prop(truck: TruckParser, built: Dictionary) -> Node3D:
    var props: Array[Node3D] = built.get("prop_nodes", [] as Array[Node3D]) as Array[Node3D]
    for index: int in mini(props.size(), truck.props.size()):
        if (truck.props[index]["mesh"] as String).to_lower().contains(DASHBOARD_MARK):
            return props[index]
    return null


## One dial: a face, a rim, ticks around it, and a needle that turns.
static func _dial(name: String, offset_x: float) -> Node3D:
    var dial: Node3D = Node3D.new()
    dial.name = name
    dial.position = Vector3(offset_x, 0.0, 0.0)

    var face: MeshInstance3D = MeshInstance3D.new()
    face.name = "Face"
    var face_mesh: CylinderMesh = CylinderMesh.new()
    face_mesh.top_radius = CockpitCfg.DIAL_RADIUS_M
    face_mesh.bottom_radius = CockpitCfg.DIAL_RADIUS_M
    face_mesh.height = CockpitCfg.DIAL_DEPTH_M
    face_mesh.radial_segments = 32
    face.mesh = face_mesh
    face.material_override = _material(CockpitCfg.FACE_COLOUR, CockpitCfg.FACE_COLOUR)
    # A cylinder stands up its own Y; the dial faces the driver, so it is laid on its back.
    face.transform = Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3.ZERO)
    dial.add_child(face)

    var rim: MeshInstance3D = MeshInstance3D.new()
    rim.name = "Rim"
    var rim_mesh: TorusMesh = TorusMesh.new()
    rim_mesh.inner_radius = CockpitCfg.DIAL_RADIUS_M
    rim_mesh.outer_radius = CockpitCfg.DIAL_RADIUS_M * 1.12
    rim_mesh.rings = 24
    rim.mesh = rim_mesh
    rim.material_override = _material(CockpitCfg.RIM_COLOUR, Color.BLACK)
    rim.transform = Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0.0, 0.0, 0.002))
    dial.add_child(rim)

    for index: int in CockpitCfg.TICK_COUNT:
        dial.add_child(_tick(float(index) / float(maxi(CockpitCfg.TICK_COUNT - 1, 1))))

    var needle: Node3D = Node3D.new()
    needle.name = "Needle"
    var blade: MeshInstance3D = MeshInstance3D.new()
    blade.name = "Blade"
    var blade_mesh: BoxMesh = BoxMesh.new()
    blade_mesh.size = Vector3(
        CockpitCfg.NEEDLE_WIDTH_M, CockpitCfg.DIAL_RADIUS_M * 0.86, CockpitCfg.NEEDLE_WIDTH_M
    )
    blade.mesh = blade_mesh
    blade.material_override = _material(CockpitCfg.NEEDLE_COLOUR, CockpitCfg.NEEDLE_COLOUR * 0.6)
    # Pivoted at its end rather than its middle, so the needle turns about the dial's centre.
    blade.position = Vector3(0.0, CockpitCfg.DIAL_RADIUS_M * 0.43, 0.0)
    needle.add_child(blade)
    needle.position = Vector3(0.0, 0.0, 0.006)
    dial.add_child(needle)
    return dial


## One mark around the dial, at a share of the way through the sweep.
static func _tick(share: float) -> MeshInstance3D:
    var tick: MeshInstance3D = MeshInstance3D.new()
    var mesh: BoxMesh = BoxMesh.new()
    mesh.size = Vector3(CockpitCfg.NEEDLE_WIDTH_M, CockpitCfg.TICK_LENGTH_M, 0.002)
    tick.mesh = mesh
    var late: bool = share > 0.78
    tick.material_override = _material(
        CockpitCfg.WARNING_COLOUR if late else CockpitCfg.TICK_COLOUR,
        (CockpitCfg.WARNING_COLOUR if late else CockpitCfg.TICK_COLOUR) * 0.5
    )
    var angle: float = deg_to_rad(CockpitCfg.SWEEP_START_DEG + CockpitCfg.SWEEP_DEG * share)
    var radius: float = CockpitCfg.DIAL_RADIUS_M * 0.82
    tick.transform = Transform3D(
        Basis(Vector3.BACK, -angle),
        Vector3(sin(angle) * radius, cos(angle) * radius, 0.004)
    )
    return tick


## Turns one needle to a share of its dial.
static func _point(dial: Node, share: float) -> void:
    if dial == null:
        return
    var needle: Node3D = dial.get_node_or_null(^"Needle") as Node3D
    if needle == null:
        return
    var angle: float = deg_to_rad(CockpitCfg.SWEEP_START_DEG + CockpitCfg.SWEEP_DEG * share)
    needle.transform.basis = Basis(Vector3.BACK, -angle)


static func _material(albedo: Color, emission: Color) -> StandardMaterial3D:
    var material: StandardMaterial3D = StandardMaterial3D.new()
    material.albedo_color = albedo
    material.roughness = 0.6
    material.emission_enabled = true
    material.emission = emission
    material.emission_energy_multiplier = CockpitCfg.BACKLIGHT_OFF
    return material
