#include "ror_wheels.h"

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

void RorWheelSet::set_brake_forces(float foot, float handbrake) {
    m_brake_force = foot;
    // Upstream's default when a rig states no parking brake force of its own.
    m_handbrake_force = handbrake > 0.0f ? handbrake : 2.0f * foot;
}

void RorWheelSet::apply(NodeArray &nodes, float clutch_torque, float dt) {
    if (dt <= 0.0f || m_wheels.empty()) {
        return;
    }
    // Upstream's differential chain, for the case a rig's differentials are split — which
    // every axle of the hero rig is. A split differential hands each output half of what
    // it was given, so across the axle differential and the two wheel differentials the
    // chain returns exactly what came in and reduces to this division. Open, locked and
    // viscous differentials do not, and they are not modelled yet.
    float drive_torque = 0.0f;
    if (m_driven_count > 0) {
        drive_torque = clutch_torque / static_cast<float>(m_driven_count);
        if (m_has_axles) {
            drive_torque *= 2.0f;
        }
    }

    m_driven_spin = 0.0f;
    m_driven_speed = 0.0f;
    for (RorWheel &wheel : m_wheels) {
        if (wheel.tread_count <= 0 || wheel.radius <= 0.0f) {
            continue;
        }
        wheel.torque = wheel.drive == WheelDrive::NONE ? 0.0f : drive_torque;

        if (wheel.brake != WheelBrake::NONE) {
            float stopping = m_brake_force * m_brake;
            if (m_parking_brake && wheel.brake != WheelBrake::FOOT_ONLY) {
                stopping += m_handbrake_force;
            }
            if (stopping > 0.0f) {
                // The torque that would bring this wheel to a stop in one step, less
                // whatever the last step already took out of it. Braking is a target
                // rather than a constant force, which is what stops a braked wheel
                // oscillating about zero.
                float force = -wheel.average_speed * wheel.radius * wheel.mass / dt;
                force -= wheel.last_retorque;
                if (wheel.speed > 0.0f) {
                    wheel.torque += std::fmax(std::fmin(force, 0.0f), -stopping);
                } else {
                    wheel.torque += std::fmin(std::fmax(force, 0.0f), stopping);
                }
            }
        }

        const Vector3 axis =
                (nodes[static_cast<size_t>(wheel.axis_b)].position - nodes[static_cast<size_t>(wheel.axis_a)].position)
                        .normalized();
        const float per_node = wheel.torque / static_cast<float>(wheel.tread_count);
        const float expected_before = wheel.speed;
        wheel.speed = 0.0f;

        for (int j = 0; j < wheel.tread_count; ++j) {
            RorNode &tread = nodes[static_cast<size_t>(wheel.first_tread + j)];
            const RorNode &inner = nodes[static_cast<size_t>((j % 2) ? wheel.axis_b : wheel.axis_a)];
            Vector3 radius = tread.position - inner.position;
            const float length = static_cast<float>(radius.length());
            if (length <= 0.0f) {
                continue;
            }
            const float inverse = 1.0f / length;
            if (wheel.drive == WheelDrive::BACKWARD) {
                radius = -radius;
            }
            // Unit tangent about the axle. Scaling by 1/length a second time turns a
            // torque into the force that delivers it at this node's actual radius, so a
            // squashed tyre pushes harder at its flattened contact patch.
            const Vector3 direction = axis.cross(radius) * inverse;
            tread.forces += direction * (per_node * inverse);
            wheel.speed += static_cast<float>((tread.velocity - inner.velocity).dot(direction));
        }
        wheel.speed /= static_cast<float>(wheel.tread_count);
        wheel.rotation += (wheel.speed / wheel.radius) * dt;
        wheel.average_speed = wheel.average_speed * 0.99f + wheel.speed * 0.1f;

        if (wheel.drive != WheelDrive::NONE) {
            m_driven_speed += wheel.speed / static_cast<float>(m_driven_count);
            m_driven_spin += (wheel.speed / wheel.radius) / static_cast<float>(m_driven_count);
        }

        // What the wheel's own inertia should have done with the last step's torque, and
        // therefore how much of this step's braking estimate has already been spent.
        const float expected = expected_before + ((wheel.last_torque / wheel.radius) / wheel.mass) * dt;
        wheel.last_retorque = wheel.mass * (wheel.speed - expected) / dt;

        // Reaction torque: driving a wheel pushes back along the suspension arm.
        if (std::fabs(wheel.torque) > 0.01f) {
            const RorNode &attach = nodes[static_cast<size_t>(wheel.near_attach_node)];
            const Vector3 arm = nodes[static_cast<size_t>(wheel.arm_node)].position - attach.position;
            // The part of the arm that is square to the axle: only that part can carry a
            // reaction about it.
            Vector3 lever = arm - axis * static_cast<float>(arm.dot(axis));
            const float offset = static_cast<float>((arm - lever).length());
            const float lever_length = static_cast<float>(lever.length());
            if (lever_length > 0.01f && offset * 2.0f < lever_length) {
                lever /= lever_length;
                const Vector3 force = axis.cross(lever) *
                        ((0.5f * wheel.torque / lever_length) * (1.0f - ((offset * 2.0f) / lever_length)));
                nodes[static_cast<size_t>(wheel.arm_node)].forces -= force;
                nodes[static_cast<size_t>(wheel.near_attach_node)].forces += force;
            }
        }

        wheel.last_torque = wheel.torque;
    }
}

} // namespace rorgd
