#pragma once

#include "ror_node.h"

#include <godot_cpp/variant/vector3.hpp>

#include <limits>
#include <vector>

namespace rorgd {

// A node held against a rail rather than pinned to one place: upstream's `SlideNode`.
//
// A strut suspension is a hub that slides along a fixed travel, and a rig that writes one as
// beams alone cannot stop the hub turning about them. Excavators and dozers run their track
// rollers on rails the same way, through a `railgroups` row the slide node names by id.
//
// The rail is upstream's `RailGroup`: a chain of the rig's own beams, one per pair of
// consecutive rail nodes, linked to their neighbours and closed into a loop when the first node
// is also the last. The node remembers the segment it is on and each step moves at most to a
// neighbour (`RailSegment::CheckCurSlideSegment`); only a reset searches the whole rail
// (`RailGroup::FindClosestSegment`). It is pulled towards the nearest point on its segment past
// its tolerance, and the reaction is shared between that beam's two ends by where along it the
// point fell. Upstream's `SlideNode::UpdatePosition`, `UpdateForces` and `CalcCorrectiveForces`.
struct RorRailSegment {
    int beam = -1;
    int prev = -1;
    int next = -1;
};

struct RorSlideNode {
    int node = 0;
    // The rail it was built on; empty when its nodes had no beam between them, where upstream
    // keeps the slide node with no rail and it does nothing.
    std::vector<RorRailSegment> rail;
    int segment = -1;
    float spring = 9000000.0f;
    float break_force = std::numeric_limits<float>::infinity();
    float initial_threshold = 0.0f;
    float threshold = 0.0f;
    float attach_rate = 1.0f;
    bool broken = false;
    // Cached by the position pass for the force pass, as upstream caches them.
    float ratio = 0.0f;
    godot::Vector3 ideal;
};

using SlideNodeArray = std::vector<RorSlideNode>;

// Upstream's `CreateRail`: the beam between each pair of consecutive `rail_nodes`, the first one
// found in beam order whichever way round it runs. False, and `out` empty, when a pair has none.
bool build_rail(const std::vector<int> &rail_nodes, const BeamArray &beams, std::vector<RorRailSegment> &out);

// Upstream's `ResetSlideNode`: back on its rail, unbroken, on the segment nearest it now.
void reset_slide_node(RorSlideNode &slide, const NodeArray &nodes, const BeamArray &beams);

// Upstream's `updateSlideNodeForces`: each slide node's position pass, then its force pass.
void apply_slide_nodes(SlideNodeArray &slide_nodes, NodeArray &nodes, const BeamArray &beams, float dt);

} // namespace rorgd
