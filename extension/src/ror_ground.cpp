#include "ror_ground.h"

#include "ror_approx.h"

#include <cmath>

using namespace godot;

namespace rorgd {

Vector3 ground_contact_force(const RorNode &node, const Vector3 &normal, float penetration, float dt,
                             const RorGroundModel &model) {
    if (dt <= 0.0f) {
        return Vector3();
    }
    const float normal_speed = static_cast<float>(node.velocity.dot(normal));
    const float normal_force = static_cast<float>(node.forces.dot(normal));

    // Steady reaction: cancel the force pressing into the surface.
    float reaction = -normal_force;
    // Impact reaction: stop the approach within this step and give back the depth
    // already accumulated. Newton's second law, not a spring.
    if (normal_speed < 0.0f) {
        reaction -= (0.8f * normal_speed - 0.2f * penetration / dt) * node.mass / dt;
    }
    if (reaction <= 0.0f) {
        return Vector3();
    }

    const Vector3 tangential_force = node.forces - normal * normal_force;
    Vector3 slip = node.velocity - normal * normal_speed;
    const float slip_speed = static_cast<float>(slip.length());
    if (slip_speed > 0.0f) {
        slip /= slip_speed;
    }

    // The reaction the surface and the node's own friction coefficient actually deliver.
    const float grip = reaction * model.strength * node.friction_coef;
    const float static_limit = model.static_friction * grip;

    if (slip_speed < model.adhesion_velocity && grip > 0.0f &&
        static_cast<float>(tangential_force.length_squared()) <= static_limit * static_limit) {
        // Static friction. The tangential force is removed rather than opposed, with a
        // little smoothing so the integrator is not handed a discontinuity at zero slip.
        // Upstream's approximation, not std::exp: see ror_approx.h. This subtraction cancels
        // most of the exponential, so the difference between the two is tens of percent of
        // the friction holding a stationary vehicle in place.
        const float friction =
                -static_limit * (1.0f - approx_exp(-slip_speed / model.adhesion_velocity));
        return normal * reaction + slip * friction - tangential_force;
    }

    // Stribeck: static coefficient at rest decaying to the sliding one with slip speed,
    // plus a hydrodynamic term that grows with it.
    const float decay =
            model.sliding_friction +
            (model.static_friction - model.sliding_friction) *
                    approx_exp(-approx_pow(slip_speed / model.stribeck_velocity, model.alpha));
    const float friction = -(decay + std::fmin(model.hydrodynamic_friction * slip_speed, 5.0f)) * grip;
    return normal * reaction + slip * friction;
}

} // namespace rorgd
