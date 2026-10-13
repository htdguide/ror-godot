#pragma once

#include "ror_node.h"

#include <vector>

namespace rorgd {

// Upstream's `Buoyance` (physics/water/Buoyance.cpp) and `Actor::CalcBuoyance`: each buoyant `cab`
// triangle, split at the waterline, pushed by the water it displaces and dragged by the water it
// moves through, every tenth substep from the nodes as they are and as they will be, the substeps
// between interpolated. The sea is flat at the terrain's water height: upstream's waves are off
// unless a player turns them on (`gfx_water_waves`), and so is the velocity they would give the
// water. Splashes and ripples are particles, and there are none yet.
class RorBuoyance {
public:
    enum { BUOY_NORMAL, BUOY_DRAGONLY, BUOY_DRAGLESS };
    struct CachedNode {
        int nodenum = 0;
        godot::Vector3 pos;
        godot::Vector3 vel;
        godot::Vector3 forces;
    };

    // A buoyant cab triangle of upstream's `type`.
    void add_cab(int a, int b, int c, int type);
    bool empty() const { return m_cabs.empty(); }
    // The water's height, or none: upstream skips buoyancy on a terrain without water.
    void set_water(bool has_water, float height) { m_has_water = has_water; m_height = height; }
    bool has_water() const { return m_has_water; }
    float water_height() const { return m_height; }
    // One substep of upstream's `CalcBuoyance`.
    void update(NodeArray &nodes, float dt);
    bool sink = false;
    // Upstream's `computePressureForce` on one triangle, for a probe.
    godot::Vector3 pressure_force(godot::Vector3 a, godot::Vector3 b, godot::Vector3 c, godot::Vector3 vel, int type) const;

private:
    struct Cab {
        int ids[3];
        int type;
    };
    int cache(int node);
    void compute_node_force(CachedNode &a, CachedNode &b, CachedNode &c, int type) const;
    godot::Vector3 pressure_force_sub(godot::Vector3 a, godot::Vector3 b, godot::Vector3 c, godot::Vector3 vel, int type) const;

    std::vector<CachedNode> m_cached;
    std::vector<CachedNode> m_projected;
    std::vector<Cab> m_cabs;
    long long m_total_steps = 0;
    long long m_last_sample_steps = 0;
    bool m_has_water = false;
    float m_height = 0.0f;
};

} // namespace rorgd
