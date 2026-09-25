#pragma once

#include <godot_cpp/variant/vector3.hpp>

#include <vector>

namespace rorgd {

// A point mass. Shared by the solver and by every force source that acts on one, so
// that wheels, ground contact and steering all write into the same accumulator the
// integrator reads. Upstream's `node_t`, reduced to the fields this bridge simulates.
struct RorNode {
    godot::Vector3 position;
    godot::Vector3 velocity;
    // Force accumulated since the last integration. Reset to gravity each step.
    godot::Vector3 forces;
    float mass = 1.0f;
    // Multiplies the ground's friction. Upstream takes it from `set_node_defaults`, and
    // it is how a rig asks for grippy tyres and a slippery chassis: the hero truck
    // states 0.65 for its bodywork and 1.06 for its tread.
    float friction_coef = 1.0f;
    bool immovable = false;
    // Set by ground contact each step, read by the wheels to tell a driven tread node
    // that is on the ground from one that is in the air.
    bool ground_contact = false;
};

// How a beam behaves outside the travel it was given. Upstream's `bounded` field.
enum class BeamBound {
    // A plain structural member: the same spring in tension and compression.
    NORMAL = 0,
    // A shock absorber. Inside its travel it is as soft as its own rates say; past either
    // bound its spring and damping ramp towards the rig's structural defaults, which is
    // what stops a suspension travelling through its own bump stops.
    SHOCK1 = 1,
    // A rope. Carries tension and nothing else: slack rope pushes nothing.
    ROPE = 2,
    // A support beam. Carries compression and nothing else: it holds a part up and lets it
    // be lifted away freely.
    SUPPORT = 3,
};

// A damped spring between two nodes. `rest_length` is live: steering and commands work
// by changing it, which is upstream's actuation mechanism rather than an added force.
struct RorBeam {
    int a = 0;
    int b = 0;
    float rest_length = 0.0f;
    // The length the rig was built with, before any actuation scaled it. Upstream's
    // `refL`, and the base every hydro and command factor multiplies.
    float reference_length = 0.0f;
    float spring = 0.0f;
    float damping = 0.0f;
    BeamBound bound = BeamBound::NORMAL;
    // Travel either side of the rest length, as a fraction of it. Upstream's `shortbound`
    // is how far the beam may compress and `longbound` how far it may stretch.
    float short_bound = 0.0f;
    float long_bound = 0.0f;
    // The rates a shock ramps towards once it is past a bound: the rig's own structural
    // defaults where the shock was declared, not the shock's soft rates.
    float bound_spring = 0.0f;
    float bound_damp = 0.0f;
};

using NodeArray = std::vector<RorNode>;
using BeamArray = std::vector<RorBeam>;

} // namespace rorgd
