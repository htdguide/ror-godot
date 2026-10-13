#include "ror_screwprop.h"

#include "ror_ogre_math.h"

#include <cmath>

using godot::Vector3;

namespace rorgd {

RorScrewprop::RorScrewprop(int noderef, int nodeback, int nodeup, float fullpower)
    : noderef(noderef), nodeback(nodeback), nodeup(nodeup), fullpower(fullpower) {
    reset();
}

void RorScrewprop::update_forces(NodeArray &nodes, bool has_water, float water_height) const {
    if (!has_water) {
        return;
    }
    RorNode &ref = nodes[static_cast<size_t>(noderef)];
    const float depth = water_height - ref.position.y;
    if (depth < 0) {
        return;
    }
    Vector3 dir = nodes[static_cast<size_t>(nodeback)].position - ref.position;
    Vector3 rudaxis = ref.position - nodes[static_cast<size_t>(nodeup)].position;
    ogre_normalise(dir);
    if (reverse) {
        dir = -dir;
    }
    ogre_normalise(rudaxis);
    dir = (throtle * fullpower) * ogre_rotate_degrees(rudder, rudaxis, dir);
    ref.forces += dir;
}

void RorScrewprop::set_throttle(float val) {
    if (val > 1.0) {
        val = 1.0;
    }
    if (val < -1.0) {
        val = -1.0;
    }
    throtle = std::fabs(val);
    reverse = (val < 0);
}

void RorScrewprop::set_rudder(float val) {
    if (val > 1.0) {
        val = 1.0;
    }
    if (val < -1.0) {
        val = -1.0;
    }
    rudder = val * 45.0;
}

void RorScrewprop::reset() {
    set_throttle(0);
    rudder = 0;
    reverse = false;
}

void RorScrewprop::toggle_reverse() {
    throtle = 0;
    reverse = !reverse;
}

} // namespace rorgd
