#pragma once

#include "ror_node.h"

#include <godot_cpp/variant/vector3.hpp>

#include <vector>

namespace rorgd {

// The two aerodynamic models Rigs of Rods has, and the rule for choosing between them.
//
// A rig whose file declares a `fusedrag` section is dragged as one body: a flat-plate force from
// the fuselage's own width, computed from the front node's velocity and shared over every node.
// Every other rig is dragged node by node with a viscous turbulent model. They are not close to
// each other, and picking the wrong one is what held the hero truck to 63 km/h at full throttle.

// Per-node viscous drag, quadratic in speed. Upstream's turbulent model, minus its random
// turbulence term.
void apply_turbulent_drag(NodeArray &nodes, float coefficient);

// Upstream's `Actor::CalcFuseDrag`, for a rig that declares a fuselage.
void apply_fuselage_drag(NodeArray &nodes, int front_node, float width);

} // namespace rorgd
