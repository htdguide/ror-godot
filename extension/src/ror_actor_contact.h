#pragma once

#include "ror_ground.h"
#include "ror_node.h"

#include <godot_cpp/variant/vector3.hpp>

#include <cstdint>
#include <vector>

namespace rorgd {

// Upstream's `collcab_rate_t`: how many substeps a collision triangle may skip its test, grown
// while it keeps finding nothing near and reset the moment it hits.
struct RorCollCabRate {
    int rate = 0;
    int distance = 0;
};

// What one actor offers to collisions with other actors: upstream's `ar_collcabs`, its contactable
// nodes and the beam neighbours its back-face vote reads. See DynamicCollisions.cpp.
struct RorCollCabs {
    // Three nodes per triangle, in the file's order, which upstream calls `no`, `na`, `nb`.
    std::vector<int> triangles;
    std::vector<RorCollCabRate> rates;
    // Upstream's DEFAULT_COLLISION_RANGE: how close to a triangle's plane a node counts as in it.
    float range = 0.02f;
    // Per node: may this node hit another actor's triangles. Upstream's `nd_contactable`: every
    // node of a collision triangle, every rim node, and every node of an actor with no triangles.
    std::vector<uint8_t> contactable;
    // Per node, as the file says: a `contacters` row, or a rim node of a flexbody wheel.
    std::vector<uint8_t> contacter;
    std::vector<uint8_t> rim;
    // Per node: the nodes a beam joins it to, for the back-face vote.
    std::vector<std::vector<int>> neighbours;
    size_t prepared_nodes = 0;
    size_t prepared_beams = 0;

    void add(int no, int na, int nb);
    void set_roles(int node, size_t node_count, bool is_contacter, bool is_rim);
    size_t contactable_count() const;
    // Rebuilds `contactable` and `neighbours` if the rig has grown since they were built.
    void prepare(const NodeArray &nodes, const BeamArray &beams);
    size_t count() const { return triangles.size() / 3; }
};

// One substep of upstream's `ResolveInterActorCollisions`: `owner`'s collision triangles against
// `other`'s contactable nodes. `other_to_owner` turns the other actor's frame-local positions into
// the owner's frame (PLAN §0.12: one actor converted into the other's frame for the contact only).
// The contact law is the ground's, on the owner's default surface, with the pair's reduced mass.
// Returns how many node-in-triangle contacts it resolved.
int resolve_inter_actor(RorCollCabs &owner_cabs, NodeArray &owner_nodes,
                        const RorGroundModel &surface, const RorCollCabs &other_cabs,
                        NodeArray &other_nodes, const godot::Vector3 &other_to_owner, float dt);

// Upstream resets every triangle's skip rate when two actors close on each other faster than
// 4 m/s, so a fast approach is never tested late.
void reset_rates(RorCollCabs &cabs);

} // namespace rorgd
