#pragma once

#include "ror_node.h"

#include <godot_cpp/variant/vector3.hpp>

namespace rorgd {

// One of Rigs of Rods' ground models: the friction surface a node lands on.
//
// The defaults are upstream's `concrete` entry from `resources/skeleton/config/
// ground_models.cfg`, which is also its default surface. They are data, not taste, so
// they are quoted rather than chosen; `alpha` and `strength` are the values upstream
// leaves commented out in that file, which means they take its built-in defaults.
struct RorGroundModel {
    // Adhesion velocity: below this a contact may be in static friction.
    float adhesion_velocity = 3.0f;
    // Static friction coefficient.
    float static_friction = 1.2f;
    // Sliding (Coulomb) friction coefficient.
    float sliding_friction = 0.75f;
    // Hydrodynamic friction, s/m: friction that grows with slip speed.
    float hydrodynamic_friction = 0.01f;
    // Stribeck velocity: the scale over which static friction decays into sliding.
    float stribeck_velocity = 6.0f;
    float alpha = 2.0f;
    float strength = 1.0f;
};

// Upstream's `primitiveCollision`, solid-ground branch.
//
// Returns the force to add to the node. Two parts, and both matter:
//
// A normal reaction that removes whatever is pushing the node into the surface and, for
// a node still approaching, adds the impulse that stops the approach within one step.
// That is not a penalty spring: a spring stiff enough to hold a vehicle up needs a
// timestep far below 0.5 ms, and this is what lets an explicit integrator rest on hard
// ground at upstream's rate.
//
// And friction, in two regimes. Below the adhesion velocity, with the tangential force
// inside the static friction cone, the tangential force is cancelled outright — textbook
// static friction, and the reason a parked vehicle stays parked on a slope instead of
// creeping. Above it, a Stribeck curve decays from the static coefficient to the sliding
// one, which is what makes a driven wheel able to spin up and still pull.
//
// Without the friction half, torque on a tread node does nothing but spin the wheel.
//
// `penetration` is positive when the node is below the surface. The fluid branch of
// upstream's function (mud, sand, water) is not here: it applies only to ground models
// with a non-zero `solid_ground_level`, and every hard surface has zero.
godot::Vector3 ground_contact_force(const RorNode &node, const godot::Vector3 &normal, float penetration,
                                    float dt, const RorGroundModel &model);

} // namespace rorgd
