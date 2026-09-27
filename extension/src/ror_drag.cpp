#include "ror_drag.h"

#include "ror_approx.h"

#include <cmath>

namespace rorgd {

using godot::Vector3;

// Viscous drag, quadratic in speed. Small at walking pace and the dominant damping at road
// speed, which is why a rig without it keeps vibrating long after it should have settled and
// needs a smaller timestep to stay stable.
void apply_turbulent_drag(NodeArray &nodes, float coefficient) {
    for (RorNode &node : nodes) {
        // Upstream's approximate square root, not an exact one: a rig's aerodynamic damping is
        // computed from an approximate speed. See ror_approx.h.
        const float speed = approx_sqrt(static_cast<float>(node.velocity.length_squared()));
        if (speed <= 0.0f) {
            continue;
        }
        node.forces -= node.velocity * (coefficient * speed);
    }
}

// Upstream's fuselage drag, from `Actor::CalcFuseDrag`.
//
// Two things in it are upstream's and are reproduced rather than corrected. The wind is the
// *front node's* velocity, used for every node, so the whole rig is dragged as one body. And the
// fuselage's back node is set to its front node when the rig is spawned — upstream's own comment
// calls that probably a bug and it has been there since v0.38 — which makes the airfoil's own
// axis zero length, so the airfoil term drops out and what is left is the flat-plate term. A
// faithful port of a law includes the parts of it nobody meant.
void apply_fuselage_drag(NodeArray &nodes, int front_node, float width) {
    if (front_node < 0 || front_node >= static_cast<int>(nodes.size()) || nodes.empty()) {
        return;
    }
    const RorNode &front = nodes[static_cast<size_t>(front_node)];
    const Vector3 wind = -front.velocity;
    const float wind_speed = static_cast<float>(wind.length());
    if (wind_speed <= 0.0f) {
        return;
    }
    // Upstream's tropospheric model, valid to 11 km.
    const float altitude = static_cast<float>(front.position.y);
    const float pressure = 101325.0f * std::pow(1.0f - 0.0065f * altitude / 288.1f, 5.24947f);
    const float density = pressure * 0.0000120896f;
    const float plate = width * width * 0.5f;
    const Vector3 per_node =
        wind * (plate * 0.5f * density * wind_speed / static_cast<float>(nodes.size()));
    for (RorNode &node : nodes) {
        node.forces += per_node;
    }
}

} // namespace rorgd
