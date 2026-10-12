#include "ror_wheels.h"

#include "ror_ogre_math.h"

#include <algorithm>
#include <cmath>

using namespace godot;

namespace rorgd {

int RorWheelSet::add(const RorWheel &wheel) {
    m_wheels.push_back(wheel);
    if (wheel.drive != WheelDrive::NONE) {
        ++m_driven_count;
    }
    return static_cast<int>(m_wheels.size()) - 1;
}

bool RorWheelSet::set_transfer_case(const RorTransferCase &transfer_case) {
    if (!m_diffs.set_transfer_case(transfer_case)) {
        return false;
    }
    for (RorWheel &wheel : m_wheels) {
        wheel.drive = WheelDrive::NONE;
    }
    m_driven_count = 0;
    set_axle_driven(transfer_case.ax_1, true);
    if (!transfer_case.has_2wd) {
        set_axle_driven(transfer_case.ax_2, true);
    }
    return true;
}

void RorWheelSet::set_axle_driven(int axle, bool driven) {
    const RorDifferential *diff = m_diffs.wheel_diff(axle);
    if (diff == nullptr) {
        return;
    }
    m_wheels[static_cast<size_t>(diff->a)].drive = driven ? WheelDrive::FORWARD : WheelDrive::NONE;
    m_wheels[static_cast<size_t>(diff->b)].drive = driven ? WheelDrive::FORWARD : WheelDrive::NONE;
    // Upstream counts the pair rather than recounting, so an axle naming one wheel twice counts two.
    m_driven_count += driven ? 2 : -2;
}

void RorWheelSet::set_brake_forces(float foot, float handbrake) {
    m_brake_force = foot;
    // Upstream's default when a rig states no parking brake force of its own.
    m_handbrake_force = handbrake > 0.0f ? handbrake : 2.0f * foot;
}

void RorWheelSet::apply(NodeArray &nodes, float clutch_torque, const Vector3 &direction, float steer, float dt) {
    if (dt <= 0.0f || m_wheels.empty()) {
        return;
    }
    // Upstream's `CalcDifferentials`: every driven wheel is handed an equal share of the clutch's
    // torque, doubled when the rig names its axles, and the differentials then share it out by
    // last step's wheel speeds.
    float drive_torque = 0.0f;
    if (m_driven_count > 0) {
        drive_torque = clutch_torque / static_cast<float>(m_driven_count);
        if (m_has_axles || m_diffs.has_axles()) {
            drive_torque *= 2.0f;
        }
    }
    for (RorWheel &wheel : m_wheels) {
        wheel.torque = wheel.drive == WheelDrive::NONE || wheel.detached ? 0.0f : drive_torque;
    }
    m_diffs.prepare(m_wheels);
    m_diffs.distribute(m_wheels, dt);
    apply_wheels(nodes, direction, steer, dt);
}

// Upstream's `Actor::CalcWheels`, line for line, without its sounds and debug fields.
void RorWheelSet::apply_wheels(NodeArray &nodes, const Vector3 &direction, float steer, float dt) {
    m_tc.tick(dt);
    m_abs.tick(dt);
    m_abs.active = false;
    m_tc.active = false;
    m_driven_spin = 0.0f;
    m_driven_speed = 0.0f;
    // Upstream's `tc_wheelslip_constant`.
    constexpr float TC_WHEELSLIP = 0.25f;
    for (RorWheel &wheel : m_wheels) {
        if (wheel.detached || wheel.tread_count <= 0 || wheel.radius <= 0.0f) {
            continue;
        }
        const float relspeed = static_cast<float>(nodes[0].velocity.dot(direction));
        const float curspeed = std::fabs(relspeed);
        const float wheel_slip = std::fabs(wheel.speed - relspeed) / std::max(1.0f, curspeed);

        // Traction control: a driven wheel spinning faster than the vehicle moves loses torque.
        if (m_tc.on && std::fabs(wheel.torque) > 0.0f && std::fabs(wheel.speed) > curspeed &&
            wheel_slip > TC_WHEELSLIP) {
            if (m_tc.pulse_state) {
                wheel.tc_coef = curspeed / std::fabs(wheel.speed);
                wheel.tc_coef = std::pow(wheel.tc_coef, m_tc.ratio);
            }
            const float tc_coef = std::pow(wheel.tc_coef, std::min(std::abs(wheel.speed) / 5.0f, 1.0f));
            wheel.torque *= tc_coef;
            m_tc.active = true;
        } else {
            wheel.tc_coef = 1.0f;
        }

        if (wheel.brake != WheelBrake::NONE) {
            const float abrake = m_brake_force * m_brake;
            float hbrake = 0.0f;
            if (m_parking_brake && wheel.brake != WheelBrake::FOOT_ONLY) {
                hbrake = m_handbrake_force;
            }
            // Directional braking: a skid-steer wheel brakes on its side of the steering.
            float dbrake = 0.0f;
            if ((wheel.speed < 20.0f) &&
                (((wheel.brake == WheelBrake::FOOT_HAND_SKID_LEFT) && (steer > 0.0f)) ||
                 ((wheel.brake == WheelBrake::FOOT_HAND_SKID_RIGHT) && (steer < 0.0f)))) {
                dbrake = m_brake_force * std::abs(steer);
            }
            if (abrake != 0.0f || dbrake != 0.0f || hbrake != 0.0f) {
                float adbrake = abrake + dbrake;
                // Anti-lock: a braked wheel turning slower than the vehicle moves is let off.
                if (m_abs.on && curspeed > m_abs.min_speed && curspeed > std::fabs(wheel.speed) && (adbrake > 0.0f) &&
                    wheel_slip > 0.25f) {
                    if (m_abs.pulse_state) {
                        wheel.alb_coef = std::fabs(wheel.speed) / curspeed;
                        wheel.alb_coef = std::pow(wheel.alb_coef, m_abs.ratio);
                    }
                    adbrake *= wheel.alb_coef;
                    m_abs.active = true;
                }
                // The torque that would stop this wheel in one step, less what the last step
                // already took out of it: braking is a target, which keeps a braked wheel from
                // oscillating about zero.
                float force = -wheel.average_speed * wheel.radius * wheel.mass / dt;
                force -= wheel.last_retorque;
                if (wheel.speed > 0) {
                    wheel.torque += std::max(std::min(force, 0.0f), -(adbrake + hbrake));
                } else {
                    wheel.torque += std::max(std::min(force, +(adbrake + hbrake)), 0.0f);
                }
            } else {
                wheel.alb_coef = 1.0f;
            }
        }

        // Application to the wheel: a tangential force on every tread node about the axle.
        const Vector3 axis = ogre_normalised(nodes[static_cast<size_t>(wheel.axis_b)].position -
                                             nodes[static_cast<size_t>(wheel.axis_a)].position);
        const float axis_precalc = wheel.torque / static_cast<float>(wheel.tread_count);
        float expected_wheel_speed = wheel.speed;
        wheel.speed = 0.0f;
        for (int j = 0; j < wheel.tread_count; ++j) {
            RorNode &outer = nodes[static_cast<size_t>(wheel.first_tread + j)];
            const RorNode &inner = nodes[static_cast<size_t>((j % 2) ? wheel.axis_b : wheel.axis_a)];
            Vector3 radius = outer.position - inner.position;
            const float inverted_rlen = 1.0f / static_cast<float>(radius.length());
            if (wheel.drive == WheelDrive::BACKWARD) {
                radius = -radius;
            }
            const Vector3 dir = axis.cross(radius) * inverted_rlen;
            outer.forces += dir * axis_precalc * inverted_rlen;
            wheel.speed += static_cast<float>((outer.velocity - inner.velocity).dot(dir));
        }
        wheel.speed /= static_cast<float>(wheel.tread_count);
        wheel.rotation += (wheel.speed / wheel.radius) * dt;
        // Upstream overweights the average on purpose, for its braking estimate, in double.
        wheel.average_speed = static_cast<float>(wheel.average_speed * 0.99 + wheel.speed * 0.1);
        if (wheel.drive == WheelDrive::FORWARD) {
            const float speedacc = wheel.speed / static_cast<float>(m_driven_count);
            m_driven_speed += speedacc;
            m_driven_spin += speedacc / wheel.radius;
        }
        expected_wheel_speed += ((wheel.last_torque / wheel.radius) / wheel.mass) * dt;
        wheel.last_retorque = wheel.mass * (wheel.speed - expected_wheel_speed) / dt;

        // Reaction torque: driving a wheel pushes back along its suspension arm, or the rig would
        // gain angular momentum from nothing.
        const RorNode &attach = nodes[static_cast<size_t>(wheel.near_attach_node)];
        RorNode &arm = nodes[static_cast<size_t>(wheel.arm_node)];
        const Vector3 rradius = arm.position - attach.position;
        Vector3 projected = ogre_project(axis, rradius);
        const float offset = static_cast<float>((rradius - projected).length());
        const float rlen = ogre_normalise(projected);
        if (rlen > 0.01 && offset * 2.0f < rlen && std::fabs(wheel.torque) > 0.01f) {
            Vector3 cforce = axis.cross(projected);
            cforce *= (0.5f * wheel.torque / rlen) * (1.0f - ((offset * 2.0f) / rlen));
            arm.forces -= cforce;
            nodes[static_cast<size_t>(wheel.near_attach_node)].forces += cforce;
        }
        wheel.last_torque = wheel.torque;
        wheel.torque = 0.0f;
    }
    m_avg_speed = static_cast<float>(m_avg_speed * 0.995 + m_driven_speed * 0.005);
}

} // namespace rorgd
