#include "ror_ogre_math.h"
#include "ror_solver.h"

#include <cmath>

using namespace godot;

namespace rorgd {

// Velocity from the force accumulated last step, then position from the new velocity,
// then reset the accumulator to gravity. Upstream's order, which is what makes the
// integrator symplectic and keeps a rig from gaining energy at rest.
//
// The speed limit sits between the two, so no node moves further than `limit * dt` in one
// substep — the property PLAN §0.12's causality bound is built on. The cut leaves a hair of
// margin under the limit, because scaling a vector by `limit / length` in floats can land an ulp
// over it, and a bound that is exceeded by an ulp is not a bound.
void RorSolver::integrate(float dt) {
    constexpr float CUT_MARGIN = 1.0f - 1.0e-6f;
    const float limit_squared = m_speed_limit * m_speed_limit;
    // Upstream records the camera node's acceleration as it integrates it.
    if (m_direction_pos >= 0 && m_direction_pos < static_cast<int>(m_nodes.size())) {
        const RorNode &camera = m_nodes[static_cast<size_t>(m_direction_pos)];
        m_camera_gforces_accu += camera.forces / camera.mass;
        m_gforce_steps++;
    }
    for (RorNode &node : m_nodes) {
        if (!node.immovable) {
            node.velocity += node.forces / node.mass * dt;
            const float speed_squared = static_cast<float>(node.velocity.length_squared());
            if (speed_squared > limit_squared) {
                node.velocity *= m_speed_limit / std::sqrt(speed_squared) * CUT_MARGIN;
                ++m_speed_limit_hits;
            }
            node.position += node.velocity * dt;
        }
        node.forces = m_gravity * node.mass;
        node.ground_contact = false;
    }
}

// Upstream's per-frame g-forces (`ActorManager` after the physics steps, then
// `Actor::calculateLocalGForces`): the camera node's acceleration averaged over the frame's steps,
// halved into the running value, and seen along the camera's axes against gravity.
void RorSolver::update_camera_gforces() {
    if (m_gforce_steps == 0) {
        return;
    }
    const Vector3 camera_gforces = ogre_div(m_camera_gforces_accu, static_cast<float>(m_gforce_steps));
    m_camera_gforces_accu = Vector3();
    m_gforce_steps = 0;
    m_camera_gforces = m_camera_gforces * 0.5f + camera_gforces * 0.5f;
    const int count = static_cast<int>(m_nodes.size());
    if (m_direction_dir < 0 || m_direction_dir >= count || m_camera_roll >= count) {
        return;
    }
    const Vector3 pos = m_nodes[static_cast<size_t>(m_direction_pos)].position;
    const Vector3 cam_dir = ogre_normalised(pos - m_nodes[static_cast<size_t>(m_direction_dir)].position);
    const Vector3 cam_roll = ogre_normalised(pos - m_nodes[static_cast<size_t>(m_camera_roll)].position);
    const Vector3 cam_up = cam_dir.cross(cam_roll);
    const float gravity = m_gravity.y;
    const float vertacc = static_cast<float>(m_camera_gforces.dot(cam_up)) + gravity;
    const float longacc = static_cast<float>(m_camera_gforces.dot(cam_dir));
    const float latacc = static_cast<float>(m_camera_gforces.dot(cam_roll));
    m_gforce_y = ogre_div(Vector3(vertacc, longacc, latacc), gravity).y;
}

// What `Engine::UpdateEngine` reads of the vehicle: node 0's velocity, the main camera's
// direction (`GetCameraDir`), wheel 0's radius, the brake and the longitudinal g-force.
RorEngineActor RorSolver::engine_actor() const {
    RorEngineActor actor;
    if (!m_nodes.empty()) {
        actor.node0_velocity = m_nodes[0].velocity;
    }
    const int count = static_cast<int>(m_nodes.size());
    if (m_direction_pos >= 0 && m_direction_dir >= 0 && m_direction_pos < count && m_direction_dir < count) {
        actor.camera_dir = ogre_normalised(m_nodes[static_cast<size_t>(m_direction_pos)].position -
                                           m_nodes[static_cast<size_t>(m_direction_dir)].position);
    }
    RorWheelSet &wheels = const_cast<RorWheelSet &>(m_wheels);
    if (wheels.count() > 0) {
        actor.wheel0_radius = wheels.wheel(0).radius;
    }
    actor.brake = m_wheels.brake();
    actor.gforce_y = m_gforce_y;
    return actor;
}

} // namespace rorgd
