#pragma once

#include "ror_node.h"

#include <godot_cpp/variant/vector3.hpp>

#include <vector>

namespace rorgd {

// A node held against a rail rather than pinned to one place: upstream's `SlideNode`.
//
// A strut suspension is a hub that slides along a fixed travel, and a rig that writes one as
// beams alone cannot stop the hub turning about them. Eight vehicles in this project's library
// declare `slidenodes` and all eight are strut cars; without this the Mazda 626's front hubs
// have nothing locating them and lean 37 degrees.
//
// The rail is a chain of segments between the nodes the row names. Each step the closest
// segment is found, the node is pulled towards the closest point on it, and the reaction is
// shared between that segment's two ends by where along it the point fell. Upstream's
// `SlideNode::UpdateForces` and `CalcCorrectiveForces`.
struct RorSlideNode {
    int node = 0;
    // The rail's nodes in order; segment i runs from rail[i] to rail[i + 1].
    std::vector<int> rail;
    // Upstream's defaults: a very stiff spring, no tolerance, and a rail the node never leaves.
    float spring = 9000000.0f;
    float break_force = 0.0f;  // 0 means "never breaks", which is upstream's infinity.
    float tolerance = 0.0f;
    bool broken = false;
};

using SlideNodeArray = std::vector<RorSlideNode>;

// Applies every slide node's corrective force for one step.
void apply_slide_nodes(SlideNodeArray &slide_nodes, NodeArray &nodes);

} // namespace rorgd
