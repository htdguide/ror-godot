#pragma once

#include "ror_drivetrain.h"
#include "ror_ground.h"
#include "ror_heightfield.h"
#include "ror_obstacles.h"
#include "ror_node.h"
#include "ror_steering.h"
#include "ror_wheels.h"

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>
#include <godot_cpp/variant/vector3.hpp>

namespace rorgd {

// The node/beam core of Rigs of Rods' soft-body simulation, and the force sources that
// make a rig a vehicle rather than a structure.
//
// Point masses joined by damped springs, integrated with symplectic (semi-implicit)
// Euler exactly as upstream does it: velocity from the force accumulated during the
// previous step, then position from the new velocity, then the accumulator reset to
// gravity for every other force to add onto.
//
// The force sources run in upstream's order, which is part of its behaviour rather than an
// implementation detail: air drag, then steering, then the drivetrain and the wheels, then
// the beams, then ground contact. Each lives in its own file and knows nothing about
// Godot, so each can be checked on its own.
//
// Not here yet: beam deformation and breaking, shock travel bounds, command beams,
// buoyancy, aerodynamics beyond node drag, and collision against anything but a flat
// plane. Those are separate force sources upstream and are added deliberately rather than
// opportunistically.
class RorSolver : public godot::RefCounted {
    GDCLASS(RorSolver, godot::RefCounted)

protected:
    static void _bind_methods();

public:
    // Returns the new node's index.
    int add_node(const godot::Vector3 &position, float mass);
    // Returns the new beam's index. A rest length of 0 or less takes the current
    // separation of the two nodes, which is how a rig at spawn defines itself.
    int add_beam(int node_a, int node_b, float rest_length, float spring, float damping);

    void set_gravity(const godot::Vector3 &gravity);
    // A flat hard ground at `height`. Upstream's contact law, not a penalty spring: see
    // ror_ground.h for why that distinction decides whether a rig is stable.
    void set_ground(float height, bool enabled);
    // Stands the rig on a grid of heights instead of a flat plane. `heights` is row-major,
    // `depth` rows of `width`, sampled every `spacing` metres from `origin`. Returns false if
    // the dimensions do not match the data. Clearing it returns the rig to the flat plane.
    bool set_heightfield(const godot::PackedFloat32Array &heights, int width, int depth,
                         const godot::Vector3 &origin, float spacing);
    void clear_heightfield();

    // Static boxes: ramps, walls, kerbs, rocks. Contacted with the same ground law as the
    // terrain, because a rig hitting a wall and a rig landing on a slope are the same physics.
    int add_obstacle_box(const godot::Transform3D &transform, const godot::Vector3 &half_extents,
                         int surface);
    void clear_obstacles();
    int obstacle_count() const;
    // What a point is inside, for a gate or a probe to ask: {"hit", "penetration", "normal",
    // "surface"}. Selects around the point first, so it answers about the whole park rather than
    // about whatever the rig happened to be near.
    godot::Dictionary obstacle_contact(const godot::Vector3 &position);
    // Ground height and surface normal where the solver believes they are. The terrain that
    // is drawn and the terrain that is collided against have to agree, and this is the side
    // of that comparison the solver owns.
    float ground_height_at(const godot::Vector3 &position) const;
    godot::Vector3 ground_normal_at(const godot::Vector3 &position) const;
    // Runs the ground contact law once on a node described entirely by its arguments, and
    // returns the force it produces. Nothing is stored and no node is touched: this exists so
    // the law can be compared against Rigs of Rods' own, case by case, without a rig.
    godot::Vector3 ground_contact_probe(const godot::Vector3 &velocity, const godot::Vector3 &forces,
                                        float mass, float friction_coef, const godot::Vector3 &normal,
                                        float penetration, float dt) const;
    // The friction surface. Defaults to upstream's `concrete`.
    void set_ground_friction(float adhesion_velocity, float static_friction, float sliding_friction,
                             float hydrodynamic_friction, float stribeck_velocity, float strength);
    // Defines the ground model at `index`, for a world with more than one surface. Index 0 is
    // the one `set_ground_friction` sets and the one used where no surface map says otherwise.
    // The soft half of a ground model: how deep the fluid layer is and what it is made of.
    // Separate from the friction setter because most surfaces have none of it, and because a
    // twelve-argument call is a call nobody can read.
    void set_ground_fluid(int index, float solid_ground_level, float fluid_density,
                          float flow_consistency_index, float flow_behavior_index,
                          float drag_anisotropy);
    void set_ground_model(int index, float adhesion_velocity, float static_friction,
                          float sliding_friction, float hydrodynamic_friction,
                          float stribeck_velocity, float alpha, float strength);
    // Which model applies where, on the same grid as the heightfield.
    bool set_surface_map(const godot::PackedByteArray &surfaces, int width, int depth);
    int ground_model_count() const;
    // The model a node standing here would be gripped by. For checking that a track's
    // surfaces are where they are drawn.
    int surface_at(const godot::Vector3 &position) const;
    // Per-node viscous drag against still air, upstream's turbulent model. Its random
    // turbulence term is deliberately left out: this project's gates may not depend on
    // unseeded randomness.
    void set_air_drag(float coefficient, bool enabled);
    // The fuselage drag a rig's own `fusedrag` section asks for, which replaces the per-node
    // turbulent model for rigs that declare one. `width` is the section's approximate width in
    // metres, or the area its autocalc form works out.
    void set_fuselage_drag(int front_node, float width, bool enabled);
    void set_node_immovable(int node, bool immovable);
    void set_node_position(int node, const godot::Vector3 &position);
    void set_node_velocity(int node, const godot::Vector3 &velocity);
    void set_node_mass(int node, float mass);
    void set_node_friction(int node, float friction_coef);
    void add_node_force(int node, const godot::Vector3 &force);
    // Actuation. Changing a beam's rest length is how upstream moves a rig from within.
    void set_beam_rest_length(int beam, float length);
    // Gives a beam a travel range and what happens outside it. `bound_type` is a BeamBound.
    // `precompression` scales the beam's rest and reference length, which is how a shock is
    // installed already under load. See ror_node.h for what each bound type means.
    // What a beam yields at and what it breaks at, from the file's own `set_beam_defaults`.
    // A strength of zero leaves the beam unbreakable and undeformable, which is what every
    // beam was before this existed.
    void set_beam_limits(int beam, float deform, float strength, float plastic_coef);
    // Whether a beam has broken, and what its rest length is now: a bent beam's rest length is
    // how the bend is recorded.
    bool beam_broken(int beam) const;
    float beam_strength(int beam) const;
    int broken_beam_count() const;
    // Taking the rig as built, and putting it back that way. Damage is spread over six beam
    // fields and a per-node count, so repairing it means restoring a snapshot rather than
    // recomputing values that building already worked out. See ror_repair.cpp.
    void snapshot_undamaged();
    void repair();
    // Marks a node as part of a collision triangle, which upstream protects from losing its
    // last beams.
    void set_node_cab(int node, bool is_cab);

    void set_beam_bounds(int beam, int bound_type, float short_bound, float long_bound,
                         float bound_spring, float bound_damp, float precompression);
    float get_beam_rest_length(int beam) const;
    float get_beam_reference_length(int beam) const;
    // The beam's length as the force law measures it — with upstream's approximate reciprocal
    // square root, not exactly. Exposed so a check of the force law can be made at the
    // extension the law was actually applied to, rather than at the one the caller intended.
    float get_beam_length(int beam) const;

    // --- Wheels -----------------------------------------------------------------
    // `first_tread` and `tread_count` name the generated tread nodes, which alternate
    // between the two axle planes. `drive` and `brake` are the `propulsed` and `braked`
    // fields of the wheel's own row.
    int add_wheel(int axis_a, int axis_b, int first_tread, int tread_count, int arm_node, float radius, int drive,
                  int brake);
    void set_has_axles(bool has_axles);
    void set_brake_forces(float foot, float handbrake);
    int wheel_count() const;
    float get_wheel_speed(int wheel) const;
    float get_wheel_rotation(int wheel) const;
    float get_wheel_torque(int wheel) const;

    // --- Drivetrain -------------------------------------------------------------
    void configure_engine(float min_rpm, float max_rpm, float torque, float diff_ratio, float reverse_gear,
                          float neutral_gear, const godot::PackedFloat32Array &forward_gears);
    void set_engine_options(float inertia, const godot::String &type, float clutch_force, float clutch_time,
                            float shift_time, float post_shift_time, float idle_rpm, float stall_rpm,
                            float braking_torque);
    void set_torque_curve(const godot::PackedFloat32Array &rpm, const godot::PackedFloat32Array &ratio);
    void start_engine();
    void stop_engine();
    void set_throttle(float throttle);
    void set_brake(float brake);
    void set_parking_brake(bool on);
    void set_gear_selector(int selector);
    float engine_rpm() const;
    float engine_max_rpm() const;
    int engine_gear() const;
    int engine_gear_count() const;
    float engine_clutch() const;
    float engine_torque() const;
    bool engine_running() const;
    bool has_engine() const;
    // Average tread speed of the driven wheels, m/s. The rig's road speed as its own
    // drivetrain measures it.
    float road_speed() const;

    // --- Steering ---------------------------------------------------------------
    void add_hydro(int beam, float factor);
    int hydro_count() const;
    void set_steer_command(float command);
    float steer_state() const;

    // Advances by `substeps` steps of `dt` seconds each.
    void step(float dt, int substeps);

    godot::PackedVector3Array get_positions() const;
    godot::Vector3 get_node_position(int node) const;
    godot::Vector3 get_node_velocity(int node) const;
    float get_node_mass(int node) const;
    int node_count() const;
    int beam_count() const;
    float total_mass() const;
    // Total kinetic plus gravitational potential energy, for checking that a rig settles
    // rather than gaining energy from its own integrator.
    float total_energy() const;

private:
    NodeArray m_nodes;
    BeamArray m_beams;
    // The beams as the rig was built, and the active-beam count each node started with. Empty
    // until `snapshot_undamaged` is called, which makes `repair` a no-op on a rig built by code
    // that predates it rather than half-repairing one.
    BeamArray m_undamaged_beams;
    std::vector<int> m_undamaged_active_beams;
    RorWheelSet m_wheels;
    RorDrivetrain m_drivetrain;
    RorSteering m_steering;
    // Index 0 always exists and is upstream's `concrete`.
    std::vector<RorGroundModel> m_ground_models{RorGroundModel()};
    RorHeightfield m_heightfield;
    RorObstacles m_obstacles;
    // How far outside the rig's own bounds an obstacle still counts as near, in metres: one
    // call's travel at any speed the solver is stable at, plus a truck's length.
    static constexpr float OBSTACLE_MARGIN_M = 8.0f;
    godot::Vector3 m_gravity = godot::Vector3(0.0f, -9.81f, 0.0f);
    float m_ground_height = 0.0f;
    bool m_ground_enabled = false;
    // Upstream's DEFAULT_DRAG.
    float m_air_drag = 0.05f;
    bool m_air_drag_enabled = false;
    int m_fuselage_node = -1;
    float m_fuselage_width = 0.0f;
    bool m_fuselage_enabled = false;

    void integrate(float dt);
    void apply_air_drag();
    static void apply_bound_law(const RorBeam &beam, float extension, float &spring, float &damping);
    void accumulate_beam_forces();
    void apply_ground_contact(float dt);
    void apply_obstacle_contact(float dt);
    void select_nearby_obstacles();
};

} // namespace rorgd
