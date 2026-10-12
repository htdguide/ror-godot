#include "ror_solver.h"

#include <algorithm>

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

void RorSolver::set_has_axles(bool has_axles) {
    sync();
    m_wheels.set_has_axles(has_axles);
}

void RorSolver::set_brake_forces(float foot, float handbrake) {
    sync();
    m_wheels.set_brake_forces(foot, handbrake);
}

int RorSolver::wheel_count() const {
    sync();
    return m_wheels.count();
}

float RorSolver::get_wheel_speed(int wheel) const {
    sync();
    if (wheel < 0 || wheel >= m_wheels.count()) {
        return 0.0f;
    }
    return m_wheels.at(wheel).speed;
}

float RorSolver::get_wheel_rotation(int wheel) const {
    sync();
    if (wheel < 0 || wheel >= m_wheels.count()) {
        return 0.0f;
    }
    return m_wheels.at(wheel).rotation;
}

float RorSolver::get_wheel_torque(int wheel) const {
    sync();
    if (wheel < 0 || wheel >= m_wheels.count()) {
        return 0.0f;
    }
    return m_wheels.at(wheel).last_torque;
}

int RorSolver::add_axle(int wheel_a, int wheel_b, const String &types) {
    sync();
    if (wheel_a < 0 || wheel_b < 0 || wheel_a >= m_wheels.count() || wheel_b >= m_wheels.count()) {
        return -1;
    }
    return m_wheels.differentials().add_axle(wheel_a, wheel_b,
                                             RorDifferentials::parse_types(types.utf8().get_data()));
}

int RorSolver::add_interaxle(int axle_a, int axle_b, const String &types) {
    sync();
    return m_wheels.differentials().add_interaxle(axle_a, axle_b,
                                                  RorDifferentials::parse_types(types.utf8().get_data()));
}

void RorSolver::toggle_wheel_differentials() {
    sync();
    m_wheels.prepare_differentials();
    m_wheels.differentials().toggle_wheel_diffs();
}

void RorSolver::toggle_axle_differentials() {
    sync();
    m_wheels.prepare_differentials();
    m_wheels.differentials().toggle_axle_diffs();
}

void RorSolver::clear_axle_differentials() {
    sync();
    m_wheels.prepare_differentials();
    m_wheels.differentials().clear_axle_diffs();
}

Vector2i RorSolver::wheel_differential_wheels(int index) {
    sync();
    m_wheels.prepare_differentials();
    const RorDifferential *diff = m_wheels.differentials().wheel_diff(index);
    return diff == nullptr ? Vector2i(-1, -1) : Vector2i(diff->a, diff->b);
}

Vector2i RorSolver::axle_differential_axles(int index) {
    sync();
    m_wheels.prepare_differentials();
    const RorDifferential *diff = m_wheels.differentials().axle_diff(index);
    return diff == nullptr ? Vector2i(-1, -1) : Vector2i(diff->a, diff->b);
}

float RorSolver::wheel_differential_wind(int index) {
    sync();
    const RorDifferential *diff = m_wheels.differentials().wheel_diff(index);
    return diff == nullptr ? 0.0f : diff->delta_rotation;
}

bool RorSolver::set_transfer_case(int axle_1, int axle_2, bool has_2wd, bool has_2wd_lo,
                                  const PackedFloat32Array &ratios) {
    sync();
    RorTransferCase transfer_case;
    transfer_case.ax_1 = axle_1;
    transfer_case.ax_2 = axle_2;
    transfer_case.has_2wd = has_2wd;
    transfer_case.has_2wd_lo = has_2wd_lo;
    if (!ratios.is_empty()) {
        transfer_case.ratios.assign(ratios.ptr(), ratios.ptr() + ratios.size());
    }
    return m_wheels.set_transfer_case(transfer_case);
}

bool RorSolver::has_transfer_case() {
    sync();
    return m_wheels.differentials().transfer_case() != nullptr;
}

Vector2i RorSolver::transfer_case_axles() {
    sync();
    const RorTransferCase *tc = m_wheels.differentials().transfer_case();
    return tc == nullptr ? Vector2i(-1, -1) : Vector2i(tc->ax_1, tc->ax_2);
}

void RorSolver::toggle_transfer_case_mode() {
    sync();
    RorTransferCase *tc = m_wheels.differentials().transfer_case();
    if (!m_drivetrain.configured() || tc == nullptr || tc->ax_2 < 0 || !tc->has_2wd) {
        return;
    }
    // Leaving 4WD without a 2WD low range shifts back up to high first.
    if (tc->four_wd && !tc->has_2wd_lo) {
        for (size_t i = 0; i < tc->ratios.size(); ++i) {
            toggle_transfer_case_ratio();
            if (tc->ratios[0] == 1.0f) {
                break;
            }
        }
    }
    tc->four_wd = !tc->four_wd;
    m_wheels.set_axle_driven(tc->ax_2, tc->four_wd);
}

void RorSolver::toggle_transfer_case_ratio() {
    sync();
    RorTransferCase *tc = m_wheels.differentials().transfer_case();
    if (!m_drivetrain.configured() || tc == nullptr || tc->ratios.size() < 2) {
        return;
    }
    if (tc->four_wd || tc->has_2wd_lo) {
        std::rotate(tc->ratios.begin(), tc->ratios.begin() + 1, tc->ratios.end());
        m_drivetrain.set_tcase_ratio(tc->ratios[0]);
    }
}

bool RorSolver::transfer_case_four_wd() {
    sync();
    const RorTransferCase *tc = m_wheels.differentials().transfer_case();
    return tc != nullptr && tc->four_wd;
}

float RorSolver::transfer_case_ratio() {
    sync();
    const RorTransferCase *tc = m_wheels.differentials().transfer_case();
    return tc == nullptr ? 1.0f : tc->ratios[0];
}

float RorSolver::transfer_case_wind() {
    sync();
    const RorTransferCase *tc = m_wheels.differentials().transfer_case();
    return tc == nullptr ? 0.0f : tc->diff.delta_rotation;
}

int RorSolver::driven_wheel_count() {
    sync();
    return m_wheels.driven_count();
}

PackedFloat32Array RorSolver::differential_probe(const String &type, float speed_a, float speed_b, float in_torque,
                                                float dt, float wind) const {
    RorDifferential diff;
    diff.types = RorDifferentials::parse_types(type.utf8().get_data());
    diff.delta_rotation = wind;
    float out_a = 0.0f;
    float out_b = 0.0f;
    diff.split(speed_a, speed_b, in_torque, dt, out_a, out_b);
    PackedFloat32Array out;
    out.push_back(out_a);
    out.push_back(out_b);
    out.push_back(diff.delta_rotation);
    return out;
}

int RorSolver::wheel_differential_count() {
    sync();
    m_wheels.prepare_differentials();
    return m_wheels.differentials().wheel_diff_count();
}

int RorSolver::axle_differential_count() {
    sync();
    m_wheels.prepare_differentials();
    return m_wheels.differentials().axle_diff_count();
}

String RorSolver::wheel_differential_type(int index) {
    sync();
    m_wheels.prepare_differentials();
    const char type = m_wheels.differentials().wheel_diff_type(index);
    return type == 0 ? String() : String::chr(type);
}

String RorSolver::axle_differential_type(int index) {
    sync();
    m_wheels.prepare_differentials();
    const char type = m_wheels.differentials().axle_diff_type(index);
    return type == 0 ? String() : String::chr(type);
}

// --- Drivetrain -----------------------------------------------------------------

void RorSolver::configure_engine(float min_rpm, float max_rpm, float torque, float diff_ratio, float reverse_gear,
                                 float neutral_gear, const PackedFloat32Array &forward_gears) {
    sync();
    m_drivetrain.configure(min_rpm, max_rpm, torque, diff_ratio, reverse_gear, neutral_gear,
                           to_vector(forward_gears));
}

void RorSolver::set_engine_options(float inertia, const String &type, float clutch_force, float clutch_time,
                                   float shift_time, float post_shift_time, float idle_rpm, float stall_rpm,
                                   float braking_torque) {
    sync();
    const CharString utf8 = type.utf8();
    const char kind = utf8.length() > 0 ? utf8.get_data()[0] : 't';
    m_drivetrain.set_options(inertia, kind, clutch_force, clutch_time, shift_time, post_shift_time, idle_rpm,
                             stall_rpm, braking_torque);
}

void RorSolver::set_torque_curve(const PackedFloat32Array &rpm, const PackedFloat32Array &ratio) {
    sync();
    m_drivetrain.set_torque_curve(to_vector(rpm), to_vector(ratio));
}

void RorSolver::start_engine() {
    sync();
    m_drivetrain.start();
}

void RorSolver::stop_engine() {
    sync();
    m_drivetrain.stop();
}

void RorSolver::set_throttle(float throttle) {
    sync();
    m_drivetrain.set_throttle(throttle);
}

void RorSolver::set_brake(float brake) {
    sync();
    m_wheels.set_brake(brake);
}

void RorSolver::set_parking_brake(bool on) {
    sync();
    m_wheels.set_parking_brake(on);
}

void RorSolver::set_gear_selector(int selector) {
    sync();
    m_drivetrain.set_selector(selector);
}

float RorSolver::engine_rpm() const {
    sync();
    return m_drivetrain.rpm();
}

float RorSolver::engine_max_rpm() const {
    sync();
    return m_drivetrain.max_rpm();
}

int RorSolver::engine_gear() const {
    sync();
    return m_drivetrain.gear();
}

int RorSolver::engine_gear_count() const {
    sync();
    return m_drivetrain.gear_count();
}

float RorSolver::engine_clutch() const {
    sync();
    return m_drivetrain.clutch();
}

float RorSolver::engine_torque() const {
    sync();
    return m_drivetrain.clutch_torque();
}

bool RorSolver::engine_running() const {
    sync();
    return m_drivetrain.running();
}

bool RorSolver::engine_contact() const {
    sync();
    return m_drivetrain.contact();
}

bool RorSolver::has_engine() const {
    sync();
    return m_drivetrain.configured();
}

float RorSolver::road_speed() const {
    sync();
    return m_wheels.driven_speed();
}

// --- Steering -------------------------------------------------------------------

void RorSolver::add_hydro(int beam, float factor) {
    sync();
    if (beam >= 0 && beam < static_cast<int>(m_beams.size())) {
        m_steering.add_hydro(beam, factor);
    }
}

int RorSolver::hydro_count() const {
    sync();
    return m_steering.count();
}

void RorSolver::set_steer_command(float command) {
    sync();
    m_steering.set_command(command);
}

float RorSolver::steer_state() const {
    sync();
    return m_steering.state();
}

// --- Script surface -------------------------------------------------------------

void RorSolver::_bind_methods() {
    bind_wheel_methods();
    bind_hook_methods();
    bind_tie_methods();
    bind_slide_methods();
    ClassDB::bind_method(D_METHOD("add_node", "position", "mass"), &RorSolver::add_node);
    ClassDB::bind_method(D_METHOD("add_beam", "node_a", "node_b", "rest_length", "spring", "damping"),
                         &RorSolver::add_beam);
    ClassDB::bind_method(D_METHOD("set_gravity", "gravity"), &RorSolver::set_gravity);
    ClassDB::bind_method(D_METHOD("set_speed_limit", "metres_per_second"), &RorSolver::set_speed_limit);
    ClassDB::bind_method(D_METHOD("speed_limit"), &RorSolver::speed_limit);
    ClassDB::bind_method(D_METHOD("speed_limit_hits"), &RorSolver::speed_limit_hits);
    ClassDB::bind_method(D_METHOD("set_frame_follows", "follows"), &RorSolver::set_frame_follows);
    ClassDB::bind_method(D_METHOD("get_beam_nodes", "beam"), &RorSolver::get_beam_nodes);
    ClassDB::bind_method(D_METHOD("add_collision_cab", "node_o", "node_a", "node_b"),
                         &RorSolver::add_collision_cab);
    ClassDB::bind_method(D_METHOD("collision_cab_count"), &RorSolver::collision_cab_count);
    ClassDB::bind_method(D_METHOD("set_node_contact_role", "node", "contacter", "rim"),
                         &RorSolver::set_node_contact_role);
    ClassDB::bind_method(D_METHOD("contactable_count"), &RorSolver::contactable_count);
    ClassDB::bind_method(D_METHOD("set_node_tyre", "node"), &RorSolver::set_node_tyre);
    ClassDB::bind_method(D_METHOD("add_command", "beam", "contract_key", "extend_key",
                                  "shorten_rate", "lengthen_rate", "max_contraction",
                                  "max_extension", "force_restricted", "auto_center", "one_press",
                                  "one_press_center", "engine_coupling", "needs_engine"),
                         &RorSolver::add_command);
    ClassDB::bind_method(D_METHOD("command_count"), &RorSolver::command_count);
    ClassDB::bind_method(D_METHOD("set_command_key", "key", "value"), &RorSolver::set_command_key);
    ClassDB::bind_method(D_METHOD("add_inertia_model", "name", "x", "y"), &RorSolver::add_inertia_model);
    ClassDB::bind_method(D_METHOD("set_command_inertia", "key", "start_delay", "stop_delay", "start", "stop"),
                         &RorSolver::set_command_inertia);
    ClassDB::bind_method(D_METHOD("command_key_has_inertia", "key"), &RorSolver::command_key_has_inertia);
    ClassDB::bind_method(D_METHOD("set_hydro_inertia", "hydro", "start_delay", "stop_delay", "start", "stop"),
                         &RorSolver::set_hydro_inertia);
    ClassDB::bind_method(D_METHOD("hydro_has_inertia", "hydro"), &RorSolver::hydro_has_inertia);
    ClassDB::bind_method(D_METHOD("set_self_collision", "enabled"), &RorSolver::set_self_collision);
    ClassDB::bind_method(D_METHOD("self_contact_count"), &RorSolver::self_contact_count);
    ClassDB::bind_method(D_METHOD("set_node_ground_contact", "node", "touches"),
                         &RorSolver::set_node_ground_contact);
    ClassDB::bind_method(D_METHOD("set_collision_range", "metres"), &RorSolver::set_collision_range);
    ClassDB::bind_method(D_METHOD("get_beam_damping", "beam"), &RorSolver::get_beam_damping);
    ClassDB::bind_method(D_METHOD("set_beam_damping", "beam", "damping"), &RorSolver::set_beam_damping);
    ClassDB::bind_method(D_METHOD("frame_moves"), &RorSolver::frame_moves);
    ClassDB::bind_method(D_METHOD("set_frame_origin", "x", "z"), &RorSolver::set_frame_origin);
    ClassDB::bind_method(D_METHOD("frame_origin_x"), &RorSolver::frame_origin_x);
    ClassDB::bind_method(D_METHOD("frame_origin_z"), &RorSolver::frame_origin_z);
    ClassDB::bind_method(D_METHOD("set_node_local_position", "node", "local"),
                         &RorSolver::set_node_local_position);
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
    ClassDB::bind_method(D_METHOD("set_ground_fluid", "index", "solid_ground_level",
                                  "fluid_density", "flow_consistency_index",
                                  "flow_behavior_index", "drag_anisotropy"),
                         &RorSolver::set_ground_fluid);
    ClassDB::bind_method(D_METHOD("set_ground_model", "index", "adhesion_velocity",
                                  "static_friction", "sliding_friction", "hydrodynamic_friction",
                                  "stribeck_velocity", "alpha", "strength"),
                         &RorSolver::set_ground_model);
    ClassDB::bind_method(D_METHOD("set_surface_map", "surfaces", "width", "depth"),
                         &RorSolver::set_surface_map);
    ClassDB::bind_method(D_METHOD("ground_model_count"), &RorSolver::ground_model_count);
    ClassDB::bind_method(D_METHOD("surface_at", "position"), &RorSolver::surface_at);
    ClassDB::bind_method(D_METHOD("set_air_drag", "coefficient", "enabled"), &RorSolver::set_air_drag);
    ClassDB::bind_method(D_METHOD("set_fuselage_drag", "front_node", "width", "enabled"),
                         &RorSolver::set_fuselage_drag);
    ClassDB::bind_method(D_METHOD("set_node_immovable", "node", "immovable"), &RorSolver::set_node_immovable);
    ClassDB::bind_method(D_METHOD("set_node_position", "node", "position"), &RorSolver::set_node_position);
    ClassDB::bind_method(D_METHOD("set_node_velocity", "node", "velocity"), &RorSolver::set_node_velocity);
    ClassDB::bind_method(D_METHOD("set_node_mass", "node", "mass"), &RorSolver::set_node_mass);
    ClassDB::bind_method(D_METHOD("set_node_friction", "node", "friction_coef"), &RorSolver::set_node_friction);
    ClassDB::bind_method(D_METHOD("add_node_force", "node", "force"), &RorSolver::add_node_force);
    ClassDB::bind_method(D_METHOD("set_beam_rest_length", "beam", "length"), &RorSolver::set_beam_rest_length);
    ClassDB::bind_method(D_METHOD("set_beam_limits", "beam", "deform", "strength", "plastic_coef", "deformable"),
                         &RorSolver::set_beam_limits);
    ClassDB::bind_method(D_METHOD("reset_slide_nodes"), &RorSolver::reset_slide_nodes);
    ClassDB::bind_method(D_METHOD("add_slide_node", "node", "rail", "spring", "break_force",
                                  "tolerance"),
                         &RorSolver::add_slide_node);
    ClassDB::bind_method(D_METHOD("slide_node_count"), &RorSolver::slide_node_count);
    ClassDB::bind_method(D_METHOD("add_collision_triangle", "a", "b", "c", "surface"),
                         &RorSolver::add_collision_triangle);
    ClassDB::bind_method(D_METHOD("clear_collision_triangles"),
                         &RorSolver::clear_collision_triangles);
    ClassDB::bind_method(D_METHOD("collision_triangle_count"),
                         &RorSolver::collision_triangle_count);
    ClassDB::bind_method(D_METHOD("beam_broken", "beam"), &RorSolver::beam_broken);
    ClassDB::bind_method(D_METHOD("beam_strength", "beam"), &RorSolver::beam_strength);
    ClassDB::bind_method(D_METHOD("broken_beam_count"), &RorSolver::broken_beam_count);
    ClassDB::bind_method(D_METHOD("snapshot_undamaged"), &RorSolver::snapshot_undamaged);
    ClassDB::bind_method(D_METHOD("repair"), &RorSolver::repair);
    ClassDB::bind_method(D_METHOD("set_node_cab", "node", "is_cab"), &RorSolver::set_node_cab);
    ClassDB::bind_method(D_METHOD("set_beam_bounds", "beam", "bound_type", "short_bound",
                                  "long_bound", "bound_spring", "bound_damp", "precompression"),
                         &RorSolver::set_beam_bounds);
    ClassDB::bind_method(D_METHOD("get_beam_stress", "beam"), &RorSolver::get_beam_stress);
    ClassDB::bind_method(D_METHOD("set_beam_detacher_group", "beam", "group"), &RorSolver::set_beam_detacher_group);
    ClassDB::bind_method(D_METHOD("add_wheel_detacher", "wheel", "group"), &RorSolver::add_wheel_detacher);
    ClassDB::bind_method(D_METHOD("wheel_detached", "wheel"), &RorSolver::wheel_detached);
    ClassDB::bind_method(D_METHOD("beam_pass_probe", "passes"), &RorSolver::beam_pass_probe);
    ClassDB::bind_method(D_METHOD("air_drag_probe"), &RorSolver::air_drag_probe);
    ClassDB::bind_method(D_METHOD("set_beam_shock", "beam", "rates", "soft_bump"), &RorSolver::set_beam_shock);
    ClassDB::bind_method(D_METHOD("shock_law_probe", "kind", "rates", "soft_bump", "beam", "extension", "v"),
                         &RorSolver::shock_law_probe);
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
    ClassDB::bind_method(D_METHOD("add_axle", "wheel_a", "wheel_b", "types"), &RorSolver::add_axle);
    ClassDB::bind_method(D_METHOD("add_interaxle", "axle_a", "axle_b", "types"), &RorSolver::add_interaxle);
    ClassDB::bind_method(D_METHOD("toggle_wheel_differentials"), &RorSolver::toggle_wheel_differentials);
    ClassDB::bind_method(D_METHOD("toggle_axle_differentials"), &RorSolver::toggle_axle_differentials);
    ClassDB::bind_method(D_METHOD("clear_axle_differentials"), &RorSolver::clear_axle_differentials);
    ClassDB::bind_method(D_METHOD("wheel_differential_wheels", "index"), &RorSolver::wheel_differential_wheels);
    ClassDB::bind_method(D_METHOD("axle_differential_axles", "index"), &RorSolver::axle_differential_axles);
    ClassDB::bind_method(D_METHOD("wheel_differential_wind", "index"), &RorSolver::wheel_differential_wind);
    ClassDB::bind_method(D_METHOD("differential_probe", "type", "speed_a", "speed_b", "in_torque", "dt", "wind"),
                         &RorSolver::differential_probe);
    ClassDB::bind_method(D_METHOD("wheel_differential_count"), &RorSolver::wheel_differential_count);
    ClassDB::bind_method(D_METHOD("set_transfer_case", "axle_1", "axle_2", "has_2wd", "has_2wd_lo", "ratios"),
                         &RorSolver::set_transfer_case);
    ClassDB::bind_method(D_METHOD("has_transfer_case"), &RorSolver::has_transfer_case);
    ClassDB::bind_method(D_METHOD("transfer_case_axles"), &RorSolver::transfer_case_axles);
    ClassDB::bind_method(D_METHOD("toggle_transfer_case_mode"), &RorSolver::toggle_transfer_case_mode);
    ClassDB::bind_method(D_METHOD("toggle_transfer_case_ratio"), &RorSolver::toggle_transfer_case_ratio);
    ClassDB::bind_method(D_METHOD("transfer_case_four_wd"), &RorSolver::transfer_case_four_wd);
    ClassDB::bind_method(D_METHOD("transfer_case_ratio"), &RorSolver::transfer_case_ratio);
    ClassDB::bind_method(D_METHOD("transfer_case_wind"), &RorSolver::transfer_case_wind);
    ClassDB::bind_method(D_METHOD("driven_wheel_count"), &RorSolver::driven_wheel_count);
    ClassDB::bind_method(D_METHOD("axle_differential_count"), &RorSolver::axle_differential_count);
    ClassDB::bind_method(D_METHOD("wheel_differential_type", "index"), &RorSolver::wheel_differential_type);
    ClassDB::bind_method(D_METHOD("axle_differential_type", "index"), &RorSolver::axle_differential_type);

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
    ClassDB::bind_method(D_METHOD("engine_contact"), &RorSolver::engine_contact);
    ClassDB::bind_method(D_METHOD("engine_running"), &RorSolver::engine_running);
    ClassDB::bind_method(D_METHOD("has_engine"), &RorSolver::has_engine);
    ClassDB::bind_method(D_METHOD("road_speed"), &RorSolver::road_speed);

    ClassDB::bind_method(D_METHOD("add_hydro", "beam", "factor"), &RorSolver::add_hydro);
    ClassDB::bind_method(D_METHOD("hydro_count"), &RorSolver::hydro_count);
    ClassDB::bind_method(D_METHOD("set_steer_command", "command"), &RorSolver::set_steer_command);
    ClassDB::bind_method(D_METHOD("steer_state"), &RorSolver::steer_state);

    ClassDB::bind_method(D_METHOD("step", "dt", "substeps"), &RorSolver::step);
    ClassDB::bind_method(D_METHOD("step_async", "dt", "substeps"), &RorSolver::step_async);
    ClassDB::bind_method(D_METHOD("sync"), &RorSolver::sync);
    ClassDB::bind_method(D_METHOD("step_pending"), &RorSolver::step_pending);
    ClassDB::bind_method(D_METHOD("take_step_usec"), &RorSolver::take_step_usec);
    ClassDB::bind_method(D_METHOD("take_wait_usec"), &RorSolver::take_wait_usec);
    ClassDB::bind_method(D_METHOD("last_step_thread"), &RorSolver::last_step_thread);
    ClassDB::bind_method(D_METHOD("caller_thread"), &RorSolver::caller_thread);
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
