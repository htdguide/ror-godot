#include "ror_ground.h"

#include "ror_approx.h"

#include <cmath>

using namespace godot;

namespace rorgd {

// Upstream's own gravity constant, which its buoyancy term is written against.
constexpr float GRAVITY = 9.81f;

Vector3 ground_contact_force(const RorNode &node, const Vector3 &normal, float penetration, float dt,
                             const RorGroundModel &model) {
    if (dt <= 0.0f) {
        return Vector3();
    }
    const float normal_speed = static_cast<float>(node.velocity.dot(normal));
    const float normal_force = static_cast<float>(node.forces.dot(normal));

    Vector3 fluid;
    // Soft ground: the node is inside a power-law fluid before it reaches anything solid.
    // Upstream's own branch, and the whole of what makes sand different from asphalt.
    if (model.solid_ground_level != 0.0f && penetration >= 0.0f) {
        const float speed_squared = static_cast<float>(node.velocity.length_squared());
        const float viscosity =
                model.flow_consistency_index *
                approx_pow(speed_squared, (model.flow_behavior_index - 1.0f) * 0.5f);
        fluid = node.velocity * (-viscosity * node.surface_coef);
        // Anisotropic drag: a fluid that resists sinking more than sliding, or the other way.
        if (model.drag_anisotropy < 1.0f && normal_speed > 0.0f) {
            float factor = 1.0f;
            const float adhesion_squared = model.adhesion_velocity * model.adhesion_velocity;
            if (speed_squared <= adhesion_squared && adhesion_squared > 0.0f) {
                factor = speed_squared / adhesion_squared;
            }
            fluid += normal *
                     (normal_speed * viscosity * (1.0f - model.drag_anisotropy) * factor);
        }
        // Buoyancy, held to "stops a node sinking" for a pseudoplastic fluid.
        float buoyancy = model.fluid_density * penetration * GRAVITY * node.volume_coef;
        if (model.flow_behavior_index < 1.0f && normal_speed >= 0.0f) {
            if (normal_force < 0.0f && buoyancy > -normal_force) {
                buoyancy = -normal_force;
            }
        }
        fluid += normal * buoyancy;
    }
    // And nothing solid until the node is past the soft layer.
    if (penetration < model.solid_ground_level) {
        return fluid;
    }

    // Steady reaction: cancel the force pressing into the surface.
    float reaction = -normal_force;
    // Impact reaction: stop the approach within this step and give back the depth
    // already accumulated. Newton's second law, not a spring.
    if (normal_speed < 0.0f) {
        const float depth = model.solid_ground_level - penetration;
        reaction -= (0.8f * normal_speed + 0.2f * depth / dt) * node.mass / dt;
    }
    if (reaction <= 0.0f) {
        return fluid;
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
        return fluid + normal * reaction + slip * friction - tangential_force;
    }

    // Stribeck: static coefficient at rest decaying to the sliding one with slip speed,
    // plus a hydrodynamic term that grows with it.
    const float decay =
            model.sliding_friction +
            (model.static_friction - model.sliding_friction) *
                    approx_exp(-approx_pow(slip_speed / model.stribeck_velocity, model.alpha));
    const float friction = -(decay + std::fmin(model.hydrodynamic_friction * slip_speed, 5.0f)) * grip;
    return fluid + normal * reaction + slip * friction;
}

} // namespace rorgd
