#pragma once

#include "ror_node.h"

namespace rorgd {

// Upstream's `Screwprop` (physics/water/ScrewProp.cpp): a boat's propeller, pushing its reference
// node along the line to its back node, turned about the line to its up node by the rudder, while
// that node is under water. Its splashes and ripples are particles, and there are none yet.
class RorScrewprop {
public:
    RorScrewprop(int noderef, int nodeback, int nodeup, float fullpower);
    void update_forces(NodeArray &nodes, bool has_water, float water_height) const;
    void set_throttle(float val);
    void set_rudder(float val);
    float throttle() const { return reverse ? -throtle : throtle; }
    float rudder_value() const { return rudder / 45.0; }
    void reset();
    void toggle_reverse();

private:
    int noderef, nodeback, nodeup;
    float fullpower;
    bool reverse = false;
    float rudder = 0.0f;
    float throtle = 0.0f;
};

} // namespace rorgd
