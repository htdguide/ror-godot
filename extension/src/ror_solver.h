#pragma once

#include "ror_actor_contact.h"
#include "ror_commands.h"
#include "ror_drivetrain.h"
#include "ror_ground.h"
#include "ror_heightfield.h"
#include "ror_obstacles.h"
#include "ror_node.h"
#include "ror_shocks.h"
#include "ror_slidenode.h"
#include "ror_step_worker.h"
#include "ror_triangles.h"
#include "ror_steering.h"
#include "ror_wheels.h"

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>
#include <godot_cpp/variant/vector2.hpp>
#include <godot_cpp/variant/vector3.hpp>

#include <atomic>
#include <cstdint>

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
    // Steps several solvers together and resolves contact between them; reaches the nodes, the
    // frame and the substep directly. See ror_world.h.
    friend class RorWorld;

protected:
    static void _bind_methods();

public:
    // Returns the new node's index.
    int add_node(const godot::Vector3 &position, float mass);
    // Returns the new beam's index. A rest length of 0 or less takes the current
    // separation of the two nodes, which is how a rig at spawn defines itself.
    int add_beam(int node_a, int node_b, float rest_length, float spring, float damping);

    void set_gravity(const godot::Vector3 &gravity);
    // A ceiling on every node's speed, in m/s, applied as the velocity is integrated. Upstream
    // has none; this project needs one because the causality bound of PLAN §0.12 is derived from
    // it, and a bound that a bad collision can exceed is not a bound. Defaults to 1000 km/h.
    // Each solver is one actor, so this is the per-actor v_max that section asks for.
    void set_speed_limit(float metres_per_second);
    float speed_limit() const;
    // How many times a node's speed has been cut to the limit since the solver was built. Zero
    // on any run the limit did not touch, which is how a gate tells a clamp that changed nothing
    // from one that rewrote the run.
    int64_t speed_limit_hits() const;
    // Whether the rig's frame follows it (PLAN §0.12, ror_frame.h). On by default. Off, the
    // frame stays where it is — at the world origin, for a solver that has not moved it — and
    // `set_frame_origin` is ignored, so nodes are stored in world coordinates as they were before
    // frames existed: the control a gate compares against.
    void set_frame_follows(bool follows);
    // How many times the frame has moved since the solver was built.
    int64_t frame_moves() const;
    // Puts the frame at the whole step nearest a world point given in double, re-expressing the
    // nodes so none of them moves, and reads where it is. With `set_node_local_position` this is
    // how a caller places a rig far from the origin without its world position passing through a
    // float32 Vector3 first: at 100 km that rounding alone is 7.8 mm, and it bent 127 beams.
    void set_frame_origin(double x, double z);
    double frame_origin_x() const;
    double frame_origin_z() const;
    void set_node_local_position(int node, const godot::Vector3 &local);
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
    // A `shocks2` (kind 4) or `shocks3` (kind 5) beam's own rates, in its row's order after the
    // nodes: shocks2 spring_in, damp_in, sprog_in, dprog_in, spring_out, damp_out, sprog_out,
    // dprog_out; shocks3 spring_in, damp_in, dslow_in, split_in, dfast_in, spring_out, damp_out,
    // dslow_out, split_out, dfast_out. Call after `set_beam_bounds` gives it the kind.
    void set_beam_shock(int beam, const godot::PackedFloat32Array &rates, bool soft_bump);
    // Runs a `shocks2`/`shocks3` law once on a beam described by its arguments and returns the
    // spring and damping it chooses, for comparison against upstream's own, case by case.
    godot::Vector2 shock_law_probe(int kind, const godot::PackedFloat32Array &rates, bool soft_bump,
                                   const godot::PackedFloat32Array &beam, float extension, float v) const;
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
    // A cab triangle other actors collide with: upstream's `collcab`, a `cab` row with option c, p
    // or u (or their buoyant twins). Node order is the file's. See ror_actor_contact.h.
    void add_collision_cab(int node_o, int node_a, int node_b);
    int collision_cab_count() const;
    // Which of a node's contact roles the file gives it: a `contacters` row, or a flexbody
    // wheel's rim. Either makes it hit other vehicles' collision triangles.
    void set_node_contact_role(int node, bool contacter, bool rim);
    // A key-driven ram: upstream's `commands`/`commands2`. See ror_commands.h. `beam` is the ram's
    // own beam; keys are numbered 1 to 84 and either may be 0 for none.
    void add_command(int beam, int contract_key, int extend_key, float shorten_rate,
                     float lengthen_rate, float max_contraction, float max_extension,
                     bool force_restricted, bool auto_center, bool one_press,
                     bool one_press_center, float engine_coupling, bool needs_engine);
    int command_count() const;
    // A command key held (1) or let go (0), as a player's input.
    void set_command_key(int key, float value);
    // Upstream's named inertia curves (`inertia_models.cfg`), and one key's inertia from them.
    void add_inertia_model(const godot::String &name, const godot::PackedFloat32Array &x,
                           const godot::PackedFloat32Array &y);
    void set_command_inertia(int key, float start_delay, float stop_delay, const godot::String &start,
                             const godot::String &stop);
    bool command_key_has_inertia(int key) const;
    void set_hydro_inertia(int hydro, float start_delay, float stop_delay, const godot::String &start,
                           const godot::String &stop);
    bool hydro_has_inertia(int hydro) const;
    // A generated tyre node, which never collides with its own actor.
    void set_node_tyre(int node);
    // Upstream's self-collisions, on unless `sim_no_self_collisions`, and on here since the owner
    // decided so (2026-10-11) knowing that the hero recovered from 0.40 m then breaks one cab beam.
    // Off is a gate's control.
    void set_self_collision(bool enabled);
    // How many self-contacts have been resolved since the solver was built.
    int64_t self_contact_count() const;
    // Upstream's node option `c`: false lets the node pass through the ground and the scenery.
    void set_node_ground_contact(int node, bool touches);
    // How many nodes other vehicles' triangles can hit, by upstream's rule.
    int contactable_count();
    // Upstream's `set_collision_range`; 0.02 m unless a file says otherwise.
    void set_collision_range(float metres);
    // A beam's two nodes and its damping, read and set: for probes that change one family of
    // beams to see whether it is the cause of something, never for building a rig.
    godot::Vector2i get_beam_nodes(int beam) const;
    float get_beam_damping(int beam) const;
    void set_beam_damping(int beam, float damping);
    // Gives a beam a travel range and what happens outside it. `bound_type` is a BeamBound.
    // `precompression` scales the beam's rest and reference length, which is how a shock is
    // installed already under load. See ror_node.h for what each bound type means.
    // What a beam yields at and what it breaks at, from the file's own `set_beam_defaults`.
    // A strength of zero leaves the beam unbreakable and undeformable, which is what every
    // beam was before this existed.
    void set_beam_limits(int beam, float deform, float strength, float plastic_coef,
                         bool deformable = true);
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
    // Upstream's detacher groups: the group a beam belongs to (0 none; see `RorBeam`), and a wheel
    // that comes off when a beam of `group` breaks (`wheeldetachers`).
    void set_beam_detacher_group(int beam, int group);
    void add_wheel_detacher(int wheel, int group);
    bool wheel_detached(int wheel) const;
    // The force along the beam last substep, signed as upstream's `beam.stress`: negative pulls.
    float get_beam_stress(int beam) const;
    // Runs the beam pass alone `passes` times, forces cleared before each and nothing integrated,
    // and returns every node's force: upstream's `CalcBeams`, for comparison case by case.
    godot::PackedVector3Array beam_pass_probe(int passes);

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
    // Upstream's differentials. `types` are its letters (s split, o open, v viscous, l locked), the
    // first active; `toggle` makes the next active on every differential of the kind. A rig with no
    // `axles` gets upstream's automatic ones on its first step, or on the first count asked for.
    int add_axle(int wheel_a, int wheel_b, const godot::String &types);
    int add_interaxle(int axle_a, int axle_b, const godot::String &types);
    void toggle_wheel_differentials();
    void toggle_axle_differentials();
    void clear_axle_differentials();
    int wheel_differential_count();
    int axle_differential_count();
    godot::String wheel_differential_type(int index);
    godot::String axle_differential_type(int index);
    // The two wheels an axle's differential joins, or the two axles one between axles joins;
    // (-1, -1) for none.
    godot::Vector2i wheel_differential_wheels(int index);
    godot::Vector2i axle_differential_axles(int index);
    // How far an axle's differential has wound its two wheels against each other, metres of tread.
    float wheel_differential_wind(int index);
    // Runs one differential law (`type` s, o, v or l) on the given speeds, torque and wind, and
    // returns [out_a, out_b, wind after], for comparison against upstream's laws case by case.
    godot::PackedFloat32Array differential_probe(const godot::String &type, float speed_a, float speed_b,
                                                 float in_torque, float dt, float wind) const;
    // Upstream's transfer case, axles counted from 0 in file order and `axle_2` -1 for none;
    // `ratios` start with 1, as upstream's parser starts them. False if upstream would skip it.
    bool set_transfer_case(int axle_1, int axle_2, bool has_2wd, bool has_2wd_lo,
                           const godot::PackedFloat32Array &ratios);
    bool has_transfer_case();
    // The axle always driven and the one driven only in 4WD; (-1, -1) for none.
    godot::Vector2i transfer_case_axles();
    // Upstream's two transfer case keys: 2WD and 4WD, and the next reduction; both need an engine.
    void toggle_transfer_case_mode();
    void toggle_transfer_case_ratio();
    bool transfer_case_four_wd();
    // The reduction in force, 1 for high range.
    float transfer_case_ratio();
    // How far the transfer case's locked differential has wound its two axles, metres of tread.
    float transfer_case_wind();
    int driven_wheel_count();

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

    // Advances by `substeps` steps of `dt` seconds each, on the calling thread.
    void step(float dt, int substeps);

    // --- Threading --------------------------------------------------------------
    // The same step on the solver's own thread, while the caller gets on with its frame. Every
    // other entry point waits for it first, so a caller that reads positions straight after
    // posting gets the stepped ones and loses the overlap; one that reads them before posting
    // keeps it. PlayDrive is that caller. See ror_solver_thread.cpp.
    void step_async(float dt, int substeps);
    // Waits for a posted step. Every entry point calls this; it is public for a caller that
    // wants to wait on purpose.
    void sync() const;
    bool step_pending() const;
    // Microseconds the completed steps took since the last call, on whichever thread ran them.
    // Waits for a pending step first, so the step it reports is the step that is done.
    int64_t take_step_usec();
    // Microseconds the calling thread spent blocked on the worker since the last call.
    int64_t take_wait_usec();
    // A hash of the thread that ran the last step, and of the thread asking. Two numbers in the
    // same space so a gate can compare them; they mean nothing else.
    int64_t last_step_thread() const;
    int64_t caller_thread() const;
    // A node held against a rail: upstream's `slidenodes`. `rail` is the rail's nodes in order.
    void add_slide_node(int node, const godot::PackedInt32Array &rail, float spring,
                        float break_force, float tolerance);
    int slide_node_count() const;
    // A terrain's own collision meshes, as triangles. `clear_collision_triangles` goes with
    // `clear_obstacles`: a world has one set of static collision and these are half of it.
    void add_collision_triangle(const godot::Vector3 &a, const godot::Vector3 &b,
                                const godot::Vector3 &c, int surface) {
        sync();
        m_triangles.add(a, b, c, surface);
    }
    void clear_collision_triangles() {
        sync();
        m_triangles.clear();
    }
    int collision_triangle_count() const {
        sync();
        return m_triangles.count();
    }

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
    SlideNodeArray m_slide_nodes;
    RorTriangleSet m_triangles;
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
    // PLAN §0.12's v_max: 1000 km/h.
    static constexpr float DEFAULT_SPEED_LIMIT = 1000.0f / 3.6f;
    float m_speed_limit = DEFAULT_SPEED_LIMIT;
    int64_t m_speed_limit_hits = 0;
    // Where the nodes are stored relative to; see ror_frame.h. Positions in and out of the
    // public API are world positions and are converted at the boundary.
    RorFrame m_frame;
    bool m_frame_follows = true;
    int64_t m_frame_moves = 0;
    float m_ground_height = 0.0f;
    bool m_ground_enabled = false;
    // Upstream's DEFAULT_DRAG.
    float m_air_drag = 0.05f;
    bool m_air_drag_enabled = false;
    int m_fuselage_node = -1;
    float m_fuselage_width = 0.0f;
    bool m_fuselage_enabled = false;

    // The worker that runs `step_async`, and what the two clocks around a step record. Mutable
    // because waiting is something a const reader has to be able to do.
    mutable RorStepWorker m_worker;
    mutable int64_t m_wait_usec = 0;
    std::atomic<int64_t> m_step_usec{0};
    std::atomic<int64_t> m_step_thread{0};

    // The step itself, with no waiting and no timing: what both `step` and the worker run.
    void step_now(float dt, int substeps);
    // `step_now` in its two parts, so a world can interleave several solvers substep by substep:
    // what is done once per call, then one substep. `first` is the call's first substep.
    void begin_steps();
    void substep(float dt, bool first);
    RorCollCabs m_collcabs;
    RorCommands m_commands;
    // Upstream's `CmdKeyInertiaConfig`, shared by command keys and hydros.
    RorInertiaModels m_inertia_models;
    const RorSpline *inertia_model(const godot::String &name) const;
    bool m_self_collision = true;
    int64_t m_self_contacts = 0;
    void integrate(float dt);
    void apply_air_drag();
    // `closing_speed` is the beam's rate of stretch, which the `shocks2`/`shocks3` laws read.
    void apply_bound_law(const RorBeam &beam, float extension, float closing_speed, float &spring,
                         float &damping) const;
    std::vector<RorShock> m_shocks;
    // {wheel, group} per `wheeldetachers` row.
    std::vector<std::pair<int, int>> m_wheel_detachers;
    // A beam of `group` broke by strength: the rest of the group goes, and its wheels come off.
    void detach_group(int group);
    void accumulate_beam_forces();
    void apply_ground_contact(float dt);
    void apply_obstacle_contact(float dt);
    void select_nearby_obstacles();
    void follow_frame();
    void shift_frame(double shift_x, double shift_z);
};

} // namespace rorgd
