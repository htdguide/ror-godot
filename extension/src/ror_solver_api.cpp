#include "ror_solver.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/string.hpp>

using namespace godot;

namespace rorgd {

namespace {
std::vector<float> to_vector(const PackedFloat32Array &array) {
    std::vector<float> out;
    out.reserve(static_cast<size_t>(array.size()));
    for (int64_t i = 0; i < array.size(); ++i) {
        out.push_back(array[i]);
    }
    return out;
}
} // namespace

// --- Wheels ---------------------------------------------------------------------

int RorSolver::add_wheel(int axis_a, int axis_b, int first_tread, int tread_count, int arm_node, float radius,
                         int drive, int brake) {
    const int nodes = static_cast<int>(m_nodes.size());
    if (axis_a < 0 || axis_b < 0 || axis_a >= nodes || axis_b >= nodes || first_tread < 0 ||
        first_tread + tread_count > nodes || tread_count <= 0) {
        return -1;
    }
    RorWheel wheel;
    wheel.axis_a = axis_a;
    wheel.axis_b = axis_b;
    wheel.first_tread = first_tread;
    wheel.tread_count = tread_count;
    wheel.radius = radius;
    wheel.drive = static_cast<WheelDrive>(drive);
    wheel.brake = static_cast<WheelBrake>(brake);
    // Upstream sums the tread nodes' own masses rather than taking the row's stated wheel
    // mass, so a wheel whose nodes were floored by minimass weighs what it actually
    // weighs in the simulation.
    wheel.mass = 0.0f;
    for (int i = 0; i < tread_count; ++i) {
        wheel.mass += m_nodes[static_cast<size_t>(first_tread + i)].mass;
    }
    if (wheel.mass <= 0.0f) {
        wheel.mass = 1.0f;
    }
    wheel.arm_node = (arm_node >= 0 && arm_node < nodes) ? arm_node : axis_a;
    // The axle end nearest the arm carries the reaction. Upstream picks it by distance
    // rather than by which node the file named first.
    const float to_a = static_cast<float>(
            (m_nodes[static_cast<size_t>(axis_a)].position - m_nodes[static_cast<size_t>(wheel.arm_node)].position)
                    .length());
    const float to_b = static_cast<float>(
            (m_nodes[static_cast<size_t>(axis_b)].position - m_nodes[static_cast<size_t>(wheel.arm_node)].position)
                    .length());
    wheel.near_attach_node = to_a < to_b ? axis_a : axis_b;
    return m_wheels.add(wheel);
}

void RorSolver::set_has_axles(bool has_axles) {
    m_wheels.set_has_axles(has_axles);
}

void RorSolver::set_brake_forces(float foot, float handbrake) {
    m_wheels.set_brake_forces(foot, handbrake);
}

int RorSolver::wheel_count() const {
    return m_wheels.count();
}

float RorSolver::get_wheel_speed(int wheel) const {
    if (wheel < 0 || wheel >= m_wheels.count()) {
        return 0.0f;
    }
    return m_wheels.at(wheel).speed;
}

float RorSolver::get_wheel_rotation(int wheel) const {
    if (wheel < 0 || wheel >= m_wheels.count()) {
        return 0.0f;
    }
    return m_wheels.at(wheel).rotation;
}

float RorSolver::get_wheel_torque(int wheel) const {
    if (wheel < 0 || wheel >= m_wheels.count()) {
        return 0.0f;
    }
    return m_wheels.at(wheel).last_torque;
}

// --- Drivetrain -----------------------------------------------------------------

void RorSolver::configure_engine(float min_rpm, float max_rpm, float torque, float diff_ratio, float reverse_gear,
                                 float neutral_gear, const PackedFloat32Array &forward_gears) {
    m_drivetrain.configure(min_rpm, max_rpm, torque, diff_ratio, reverse_gear, neutral_gear,
                           to_vector(forward_gears));
}

void RorSolver::set_engine_options(float inertia, const String &type, float clutch_force, float clutch_time,
                                   float shift_time, float post_shift_time, float idle_rpm, float stall_rpm,
                                   float braking_torque) {
    const CharString utf8 = type.utf8();
    const char kind = utf8.length() > 0 ? utf8.get_data()[0] : 't';
    m_drivetrain.set_options(inertia, kind, clutch_force, clutch_time, shift_time, post_shift_time, idle_rpm,
                             stall_rpm, braking_torque);
}

void RorSolver::set_torque_curve(const PackedFloat32Array &rpm, const PackedFloat32Array &ratio) {
    m_drivetrain.set_torque_curve(to_vector(rpm), to_vector(ratio));
}

void RorSolver::start_engine() {
    m_drivetrain.start();
}

void RorSolver::stop_engine() {
    m_drivetrain.stop();
}

void RorSolver::set_throttle(float throttle) {
    m_drivetrain.set_throttle(throttle);
}

void RorSolver::set_brake(float brake) {
    m_wheels.set_brake(brake);
}

void RorSolver::set_parking_brake(bool on) {
    m_wheels.set_parking_brake(on);
}

void RorSolver::set_gear_selector(int selector) {
    m_drivetrain.set_selector(selector);
}

float RorSolver::engine_rpm() const {
    return m_drivetrain.rpm();
}

float RorSolver::engine_max_rpm() const {
    return m_drivetrain.max_rpm();
}

int RorSolver::engine_gear() const {
    return m_drivetrain.gear();
}

int RorSolver::engine_gear_count() const {
    return m_drivetrain.gear_count();
}

float RorSolver::engine_clutch() const {
    return m_drivetrain.clutch();
}

float RorSolver::engine_torque() const {
    return m_drivetrain.clutch_torque();
}

bool RorSolver::engine_running() const {
    return m_drivetrain.running();
}

bool RorSolver::has_engine() const {
    return m_drivetrain.configured();
}

float RorSolver::road_speed() const {
    return m_wheels.driven_speed();
}

// --- Steering -------------------------------------------------------------------

void RorSolver::add_hydro(int beam, float factor) {
    if (beam >= 0 && beam < static_cast<int>(m_beams.size())) {
        m_steering.add_hydro(beam, factor);
    }
}

int RorSolver::hydro_count() const {
    return m_steering.count();
}

void RorSolver::set_steer_command(float command) {
    m_steering.set_command(command);
}

float RorSolver::steer_state() const {
    return m_steering.state();
}

// --- Script surface -------------------------------------------------------------

void RorSolver::_bind_methods() {
    ClassDB::bind_method(D_METHOD("add_node", "position", "mass"), &RorSolver::add_node);
    ClassDB::bind_method(D_METHOD("add_beam", "node_a", "node_b", "rest_length", "spring", "damping"),
                         &RorSolver::add_beam);
    ClassDB::bind_method(D_METHOD("set_gravity", "gravity"), &RorSolver::set_gravity);
    ClassDB::bind_method(D_METHOD("set_ground", "height", "enabled"), &RorSolver::set_ground);
    ClassDB::bind_method(D_METHOD("set_ground_friction", "adhesion_velocity", "static_friction",
                                  "sliding_friction", "hydrodynamic_friction", "stribeck_velocity", "strength"),
                         &RorSolver::set_ground_friction);
    ClassDB::bind_method(D_METHOD("set_heightfield", "heights", "width", "depth", "origin", "spacing"),
                         &RorSolver::set_heightfield);
    ClassDB::bind_method(D_METHOD("clear_heightfield"), &RorSolver::clear_heightfield);
    ClassDB::bind_method(D_METHOD("add_obstacle_box", "transform", "half_extents", "surface"),
                         &RorSolver::add_obstacle_box);
    ClassDB::bind_method(D_METHOD("clear_obstacles"), &RorSolver::clear_obstacles);
    ClassDB::bind_method(D_METHOD("obstacle_count"), &RorSolver::obstacle_count);
    ClassDB::bind_method(D_METHOD("obstacle_contact", "position"),
                         &RorSolver::obstacle_contact);
    ClassDB::bind_method(D_METHOD("ground_height_at", "position"), &RorSolver::ground_height_at);
    ClassDB::bind_method(D_METHOD("ground_normal_at", "position"), &RorSolver::ground_normal_at);
    ClassDB::bind_method(D_METHOD("ground_contact_probe", "velocity", "forces", "mass",
                                  "friction_coef", "normal", "penetration", "dt"),
                         &RorSolver::ground_contact_probe);
    ClassDB::bind_method(D_METHOD("set_ground_model", "index", "adhesion_velocity",
                                  "static_friction", "sliding_friction", "hydrodynamic_friction",
                                  "stribeck_velocity", "alpha", "strength"),
                         &RorSolver::set_ground_model);
    ClassDB::bind_method(D_METHOD("set_surface_map", "surfaces", "width", "depth"),
                         &RorSolver::set_surface_map);
    ClassDB::bind_method(D_METHOD("ground_model_count"), &RorSolver::ground_model_count);
    ClassDB::bind_method(D_METHOD("surface_at", "position"), &RorSolver::surface_at);
    ClassDB::bind_method(D_METHOD("set_air_drag", "coefficient", "enabled"), &RorSolver::set_air_drag);
    ClassDB::bind_method(D_METHOD("set_node_immovable", "node", "immovable"), &RorSolver::set_node_immovable);
    ClassDB::bind_method(D_METHOD("set_node_position", "node", "position"), &RorSolver::set_node_position);
    ClassDB::bind_method(D_METHOD("set_node_velocity", "node", "velocity"), &RorSolver::set_node_velocity);
    ClassDB::bind_method(D_METHOD("set_node_mass", "node", "mass"), &RorSolver::set_node_mass);
    ClassDB::bind_method(D_METHOD("set_node_friction", "node", "friction_coef"), &RorSolver::set_node_friction);
    ClassDB::bind_method(D_METHOD("add_node_force", "node", "force"), &RorSolver::add_node_force);
    ClassDB::bind_method(D_METHOD("set_beam_rest_length", "beam", "length"), &RorSolver::set_beam_rest_length);
    ClassDB::bind_method(D_METHOD("set_beam_bounds", "beam", "bound_type", "short_bound",
                                  "long_bound", "bound_spring", "bound_damp", "precompression"),
                         &RorSolver::set_beam_bounds);
    ClassDB::bind_method(D_METHOD("get_beam_rest_length", "beam"), &RorSolver::get_beam_rest_length);
    ClassDB::bind_method(D_METHOD("get_beam_reference_length", "beam"), &RorSolver::get_beam_reference_length);
    ClassDB::bind_method(D_METHOD("get_beam_length", "beam"), &RorSolver::get_beam_length);

    ClassDB::bind_method(D_METHOD("add_wheel", "axis_a", "axis_b", "first_tread", "tread_count", "arm_node",
                                  "radius", "drive", "brake"),
                         &RorSolver::add_wheel);
    ClassDB::bind_method(D_METHOD("set_has_axles", "has_axles"), &RorSolver::set_has_axles);
    ClassDB::bind_method(D_METHOD("set_brake_forces", "foot", "handbrake"), &RorSolver::set_brake_forces);
    ClassDB::bind_method(D_METHOD("wheel_count"), &RorSolver::wheel_count);
    ClassDB::bind_method(D_METHOD("get_wheel_speed", "wheel"), &RorSolver::get_wheel_speed);
    ClassDB::bind_method(D_METHOD("get_wheel_rotation", "wheel"), &RorSolver::get_wheel_rotation);
    ClassDB::bind_method(D_METHOD("get_wheel_torque", "wheel"), &RorSolver::get_wheel_torque);

    ClassDB::bind_method(D_METHOD("configure_engine", "min_rpm", "max_rpm", "torque", "diff_ratio",
                                  "reverse_gear", "neutral_gear", "forward_gears"),
                         &RorSolver::configure_engine);
    ClassDB::bind_method(D_METHOD("set_engine_options", "inertia", "type", "clutch_force", "clutch_time",
                                  "shift_time", "post_shift_time", "idle_rpm", "stall_rpm", "braking_torque"),
                         &RorSolver::set_engine_options);
    ClassDB::bind_method(D_METHOD("set_torque_curve", "rpm", "ratio"), &RorSolver::set_torque_curve);
    ClassDB::bind_method(D_METHOD("start_engine"), &RorSolver::start_engine);
    ClassDB::bind_method(D_METHOD("stop_engine"), &RorSolver::stop_engine);
    ClassDB::bind_method(D_METHOD("set_throttle", "throttle"), &RorSolver::set_throttle);
    ClassDB::bind_method(D_METHOD("set_brake", "brake"), &RorSolver::set_brake);
    ClassDB::bind_method(D_METHOD("set_parking_brake", "on"), &RorSolver::set_parking_brake);
    ClassDB::bind_method(D_METHOD("set_gear_selector", "selector"), &RorSolver::set_gear_selector);
    ClassDB::bind_method(D_METHOD("engine_rpm"), &RorSolver::engine_rpm);
    ClassDB::bind_method(D_METHOD("engine_max_rpm"), &RorSolver::engine_max_rpm);
    ClassDB::bind_method(D_METHOD("engine_gear"), &RorSolver::engine_gear);
    ClassDB::bind_method(D_METHOD("engine_gear_count"), &RorSolver::engine_gear_count);
    ClassDB::bind_method(D_METHOD("engine_clutch"), &RorSolver::engine_clutch);
    ClassDB::bind_method(D_METHOD("engine_torque"), &RorSolver::engine_torque);
    ClassDB::bind_method(D_METHOD("engine_running"), &RorSolver::engine_running);
    ClassDB::bind_method(D_METHOD("has_engine"), &RorSolver::has_engine);
    ClassDB::bind_method(D_METHOD("road_speed"), &RorSolver::road_speed);

    ClassDB::bind_method(D_METHOD("add_hydro", "beam", "factor"), &RorSolver::add_hydro);
    ClassDB::bind_method(D_METHOD("hydro_count"), &RorSolver::hydro_count);
    ClassDB::bind_method(D_METHOD("set_steer_command", "command"), &RorSolver::set_steer_command);
    ClassDB::bind_method(D_METHOD("steer_state"), &RorSolver::steer_state);

    ClassDB::bind_method(D_METHOD("step", "dt", "substeps"), &RorSolver::step);
    ClassDB::bind_method(D_METHOD("get_positions"), &RorSolver::get_positions);
    ClassDB::bind_method(D_METHOD("get_node_position", "node"), &RorSolver::get_node_position);
    ClassDB::bind_method(D_METHOD("get_node_velocity", "node"), &RorSolver::get_node_velocity);
    ClassDB::bind_method(D_METHOD("get_node_mass", "node"), &RorSolver::get_node_mass);
    ClassDB::bind_method(D_METHOD("node_count"), &RorSolver::node_count);
    ClassDB::bind_method(D_METHOD("beam_count"), &RorSolver::beam_count);
    ClassDB::bind_method(D_METHOD("total_mass"), &RorSolver::total_mass);
    ClassDB::bind_method(D_METHOD("total_energy"), &RorSolver::total_energy);
}

} // namespace rorgd
