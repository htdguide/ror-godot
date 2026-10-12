#include "ror_solver.h"

#include "ror_ogre_math.h"

#include <godot_cpp/core/class_db.hpp>

// The wheels: adding one, and what the wheel step (`RorWheelSet::apply_wheels`, upstream's
// `CalcWheels`) reads besides torque, the vehicle's forward and the two driving aids, upstream's
// traction control and anti-lock brake.

using namespace godot;

namespace rorgd {

namespace {
RorDriveAid *aid_of(RorWheelSet &wheels, const String &kind) {
    if (kind == "tc") {
        return &wheels.traction_control();
    }
    if (kind == "abs") {
        return &wheels.antilock();
    }
    return nullptr;
}
} // namespace

int RorSolver::add_wheel(int axis_a, int axis_b, int first_tread, int tread_count, int arm_node, float radius,
                         int drive, int brake) {
    sync();
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
    // Upstream's `GetArgPropulsion` and `GetArgBraking`: a value it does not know is neither.
    wheel.drive = drive >= 0 && drive <= 2 ? static_cast<WheelDrive>(drive) : WheelDrive::NONE;
    wheel.brake = brake >= 0 && brake <= 4 ? static_cast<WheelBrake>(brake) : WheelBrake::NONE;
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

void RorSolver::set_direction_nodes(int pos, int dir, float yaw) {
    sync();
    const int count = static_cast<int>(m_nodes.size());
    if (pos < 0 || dir < 0 || pos >= count || dir >= count) {
        return;
    }
    m_direction_pos = pos;
    m_direction_dir = dir;
    m_direction_yaw = yaw;
}

Vector3 RorSolver::direction() const {
    if (m_direction_pos < 0) {
        return Vector3();
    }
    // Upstream's `ar_main_camera_dir_corr * GetCameraDir()`.
    const Vector3 forward = ogre_normalised(m_nodes[static_cast<size_t>(m_direction_pos)].position -
                                            m_nodes[static_cast<size_t>(m_direction_dir)].position);
    return m_direction_yaw == 0.0f ? forward : ogre_rotate_y(m_direction_yaw, forward);
}

void RorSolver::set_drive_aid(const String &kind, bool on, bool toggle, float ratio, float pulse_time,
                              float min_speed) {
    sync();
    RorDriveAid *aid = aid_of(m_wheels, kind);
    if (aid == nullptr) {
        return;
    }
    aid->on = on;
    aid->toggle = toggle;
    aid->ratio = ratio;
    aid->pulse_time = pulse_time;
    aid->min_speed = min_speed;
}

bool RorSolver::toggle_drive_aid(const String &kind) {
    sync();
    RorDriveAid *aid = aid_of(m_wheels, kind);
    if (aid == nullptr) {
        return false;
    }
    if (aid->toggle) {
        aid->on = !aid->on;
    }
    return aid->on;
}

bool RorSolver::drive_aid_on(const String &kind) {
    sync();
    const RorDriveAid *aid = aid_of(m_wheels, kind);
    return aid != nullptr && aid->on;
}

bool RorSolver::drive_aid_active(const String &kind) {
    sync();
    const RorDriveAid *aid = aid_of(m_wheels, kind);
    return aid != nullptr && aid->active;
}

// `wheel_states`: per wheel, torque, speed, average_speed, last_torque, last_retorque, tc_coef,
// alb_coef, detached. `aid_states`: per aid (tc then abs), on, ratio, pulse_time, min_speed, timer,
// pulse_state. Returns {forces, wheels: per wheel last_torque, speed, average_speed, last_retorque,
// tc_coef, alb_coef, rotation; spin, speed, tc_active, abs_active}.
Dictionary RorSolver::wheel_pass_probe(const PackedFloat32Array &wheel_states, const PackedFloat32Array &aid_states,
                                       const Vector3 &direction, float steer, float dt) {
    sync();
    constexpr int PER_WHEEL = 8;
    for (int i = 0; i < m_wheels.count() && (i + 1) * PER_WHEEL <= wheel_states.size(); ++i) {
        RorWheel &w = m_wheels.wheel(i);
        const int at = i * PER_WHEEL;
        w.torque = wheel_states[at];
        w.speed = wheel_states[at + 1];
        w.average_speed = wheel_states[at + 2];
        w.last_torque = wheel_states[at + 3];
        w.last_retorque = wheel_states[at + 4];
        w.tc_coef = wheel_states[at + 5];
        w.alb_coef = wheel_states[at + 6];
        w.detached = wheel_states[at + 7] != 0.0f;
    }
    RorDriveAid *aids[2] = {&m_wheels.traction_control(), &m_wheels.antilock()};
    for (int i = 0; i < 2 && (i + 1) * 6 <= aid_states.size(); ++i) {
        const int at = i * 6;
        aids[i]->on = aid_states[at] != 0.0f;
        aids[i]->ratio = aid_states[at + 1];
        aids[i]->pulse_time = aid_states[at + 2];
        aids[i]->min_speed = aid_states[at + 3];
        aids[i]->timer = aid_states[at + 4];
        aids[i]->pulse_state = aid_states[at + 5] != 0.0f;
    }
    for (RorNode &node : m_nodes) {
        node.forces = Vector3();
    }
    m_wheels.apply_wheels(m_nodes, direction, steer, dt);
    PackedVector3Array forces;
    for (const RorNode &node : m_nodes) {
        forces.push_back(node.forces);
    }
    PackedFloat32Array wheels;
    for (int i = 0; i < m_wheels.count(); ++i) {
        const RorWheel &w = m_wheels.at(i);
        for (float value : {w.last_torque, w.speed, w.average_speed, w.last_retorque, w.tc_coef, w.alb_coef, w.rotation}) {
            wheels.push_back(value);
        }
    }
    Dictionary out;
    out["forces"] = forces;
    out["wheels"] = wheels;
    out["spin"] = m_wheels.driven_spin();
    out["speed"] = m_wheels.driven_speed();
    out["tc_active"] = aids[0]->active;
    out["abs_active"] = aids[1]->active;
    return out;
}

void RorSolver::bind_wheel_methods() {
    ClassDB::bind_method(D_METHOD("set_direction_nodes", "pos", "dir", "yaw"), &RorSolver::set_direction_nodes);
    ClassDB::bind_method(D_METHOD("direction"), &RorSolver::direction);
    ClassDB::bind_method(D_METHOD("set_drive_aid", "kind", "on", "toggle", "ratio", "pulse_time", "min_speed"),
                         &RorSolver::set_drive_aid);
    ClassDB::bind_method(D_METHOD("toggle_drive_aid", "kind"), &RorSolver::toggle_drive_aid);
    ClassDB::bind_method(D_METHOD("drive_aid_on", "kind"), &RorSolver::drive_aid_on);
    ClassDB::bind_method(D_METHOD("drive_aid_active", "kind"), &RorSolver::drive_aid_active);
    ClassDB::bind_method(D_METHOD("wheel_pass_probe", "wheel_states", "aid_states", "direction", "steer", "dt"),
                         &RorSolver::wheel_pass_probe);
}

} // namespace rorgd
