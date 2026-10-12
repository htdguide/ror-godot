#include "ror_solver.h"

#include <godot_cpp/core/class_db.hpp>

#include <algorithm>
#include <cmath>

// Upstream's cruise control (gameplay/CruiseControl.cpp), which every vehicle with an engine has:
// `cruisecontrol` only sets the lowest speed it holds and whether it may brake.

using namespace godot;

namespace rorgd {

void RorSolver::set_cruise_control(float lower_limit, bool can_brake) {
    sync();
    m_cc_lower_limit = lower_limit;
    m_cc_can_brake = can_brake;
}

// Upstream's `cruisecontrolToggle`: on, it holds the speed and rpm it was switched on at.
void RorSolver::toggle_cruise_control() {
    sync();
    m_cc_mode = !m_cc_mode;
    if (m_cc_mode) {
        m_cc_target_speed = m_wheels.avg_speed();
        m_cc_target_rpm = m_drivetrain.rpm();
    } else {
        m_cc_target_speed = 0;
        m_cc_target_rpm = 0;
        m_cc_accs.clear();
    }
}

// Upstream's `UpdateCruiseControl`, once a frame while it is on, after the driver's own controls.
// `brake_input` and `accelerate_input` are the pedal keys, `faster`, `slower` and `match` the
// three adjusting keys. Upstream's manual clutch key, which pauses it, has no key here.
void RorSolver::update_cruise_control(float dt, float brake_input, float accelerate_input, bool faster, bool slower,
                                      bool match) {
    sync();
    if (!m_cc_mode || !m_drivetrain.configured()) {
        return;
    }
    const int gear = m_drivetrain.gear();
    if ((gear > 0 && brake_input > 0.05f) || (gear > 0 && m_cc_target_speed < m_cc_lower_limit) ||
        (gear > 0 && m_wheels.parking_brake()) || (gear < 0) || !m_drivetrain.running() || !m_drivetrain.contact()) {
        toggle_cruise_control();
        return;
    }
    const float rpm = m_drivetrain.rpm();
    float acc = m_drivetrain.acc_to_hold_rpm();
    if (gear > 0) {
        // Upstream's `getTotalMass(true)` adds the vehicles linked to this one; ours is its own.
        const float power_weight_ratio = total_mass() / m_drivetrain.engine_power(rpm);
        acc += (m_cc_target_speed - m_wheels.driven_speed()) * power_weight_ratio * 0.25;
    } else if (gear == 0) {
        const float speed_range = (m_drivetrain.max_rpm() - m_drivetrain.min_rpm()) / 50.0f;
        acc += m_drivetrain.inertia() * (m_cc_target_rpm - rpm) / speed_range;
    }
    m_cc_accs.push_front(std::clamp(acc, -1.0f, 1.0f));
    if (m_cc_accs.size() > 30) {
        m_cc_accs.pop_back();
    }
    float avg_acc = 0.0f;
    for (float each : m_cc_accs) {
        avg_acc += each;
    }
    avg_acc /= m_cc_accs.size();
    m_drivetrain.auto_set_acc(std::clamp(avg_acc, m_drivetrain.current_acc(), 1.0f));

    if (faster) {
        if (gear > 0) {
            m_cc_target_speed *= std::pow(2.0f, dt / 5.0f);
            m_cc_target_speed = std::max(m_cc_lower_limit, m_cc_target_speed);
            if (m_sl_enabled) {
                m_cc_target_speed = std::min(m_cc_target_speed, m_sl_speed_limit);
            }
        } else if (gear == 0) {
            m_cc_target_rpm *= std::pow(2.0f, dt / 5.0f);
            m_cc_target_rpm = std::min(m_cc_target_rpm, m_drivetrain.max_rpm());
        }
    }
    if (slower) {
        if (gear > 0) {
            m_cc_target_speed *= std::pow(0.5f, dt / 5.0f);
            m_cc_target_speed = std::max(m_cc_lower_limit, m_cc_target_speed);
        } else if (gear == 0) {
            m_cc_target_rpm *= std::pow(0.5f, dt / 5.0f);
            m_cc_target_rpm = std::max(m_drivetrain.min_rpm(), m_cc_target_rpm);
        }
    }
    if (match) {
        m_cc_target_speed = std::max(m_wheels.avg_speed(), m_cc_target_speed);
        if (m_sl_enabled) {
            m_cc_target_speed = std::min(m_cc_target_speed, m_sl_speed_limit);
        }
        m_cc_target_rpm = rpm;
    }
    if (m_cc_can_brake && m_wheels.avg_speed() > m_cc_target_speed + 0.5f && accelerate_input == 0.0f) {
        const float brake = (m_wheels.avg_speed() - m_cc_target_speed) * 0.5f;
        m_wheels.set_brake(std::min(brake, 1.0f));
    }
}

void RorSolver::set_speed_limiter(float limit) {
    sync();
    m_sl_enabled = true;
    m_sl_speed_limit = limit;
}

// Upstream's speed limiter, once a frame after the cruise control: in gear, the throttle is held
// to twice what is left of the limit, the wheel speed taken as 2% over the road's.
void RorSolver::update_speed_limiter() {
    sync();
    if (!m_sl_enabled || !m_drivetrain.configured() || m_drivetrain.gear() == 0) {
        return;
    }
    const float accl = (m_sl_speed_limit - std::abs(m_wheels.driven_speed() / 1.02f)) * 2.0f;
    m_drivetrain.set_acc(std::clamp(accl, 0.0f, m_drivetrain.current_acc()));
}

bool RorSolver::cruise_control_on() const {
    sync();
    return m_cc_mode;
}

float RorSolver::cruise_target_speed() const {
    sync();
    return m_cc_target_speed;
}

float RorSolver::avg_wheel_speed() const {
    sync();
    return m_wheels.avg_speed();
}

float RorSolver::wheel_speed() const {
    sync();
    return m_wheels.driven_speed();
}

float RorSolver::brake_command() const {
    sync();
    return m_wheels.brake();
}

float RorSolver::commanded_throttle() const {
    sync();
    return m_drivetrain.current_acc();
}

void RorSolver::bind_cruise_methods() {
    ClassDB::bind_method(D_METHOD("set_cruise_control", "lower_limit", "can_brake"), &RorSolver::set_cruise_control);
    ClassDB::bind_method(D_METHOD("toggle_cruise_control"), &RorSolver::toggle_cruise_control);
    ClassDB::bind_method(D_METHOD("update_cruise_control", "dt", "brake_input", "accelerate_input", "faster", "slower", "match"),
                         &RorSolver::update_cruise_control);
    ClassDB::bind_method(D_METHOD("cruise_control_on"), &RorSolver::cruise_control_on);
    ClassDB::bind_method(D_METHOD("cruise_target_speed"), &RorSolver::cruise_target_speed);
    ClassDB::bind_method(D_METHOD("avg_wheel_speed"), &RorSolver::avg_wheel_speed);
    ClassDB::bind_method(D_METHOD("commanded_throttle"), &RorSolver::commanded_throttle);
    ClassDB::bind_method(D_METHOD("brake_command"), &RorSolver::brake_command);
    ClassDB::bind_method(D_METHOD("wheel_speed"), &RorSolver::wheel_speed);
    ClassDB::bind_method(D_METHOD("set_speed_limiter", "limit"), &RorSolver::set_speed_limiter);
    ClassDB::bind_method(D_METHOD("update_speed_limiter"), &RorSolver::update_speed_limiter);
}

} // namespace rorgd
