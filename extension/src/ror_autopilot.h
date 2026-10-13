#pragma once

#include "ror_node.h"

namespace rorgd {

// Upstream's `Autopilot` (gameplay/AutoPilot.cpp): wings level, a heading, an altitude or a
// vertical speed held through the aileron and elevator, and an airspeed through the throttle,
// from the first wing run's tip nodes and the fuselage drag's node. Its ILS approach needs a
// terrain's localizers, which are not read here: as upstream with none in range, NAV disconnects.
// Its ground-proximity warnings are sounds, and there are none yet.
class RorAutopilot {
public:
    enum { HEADING_NONE, HEADING_FIXED, HEADING_WLV, HEADING_NAV };
    enum { ALT_NONE, ALT_FIXED, ALT_VS };

    RorAutopilot() { reset(); }
    void reset();
    void disconnect();
    // Upstream's `setInertialReferences`: the left and right tip nodes and the fuselage's back
    // node, -1 for one the vehicle does not have.
    void set_references(const NodeArray &nodes, int left, int right, int back);
    void set_back(int back) { ref_b = back; }
    int toggle_heading(int mode);
    int toggle_alt(int mode);
    bool toggle_ias();
    bool toggle_gpws();
    int adj_hdg(int d);
    int adj_alt(int d);
    int adj_vs(int d);
    int adj_ias(int d);
    float ailerons(const NodeArray &nodes);
    float elevator(const NodeArray &nodes) const;
    float rudder() const { return 0; }
    float throttle(const NodeArray &nodes, float thrtl, float dt) const;
    // Upstream's `UpdateIls` with no localizers: no approach, and NAV asks to disconnect.
    void update_ils();
    bool ils_available() const { return m_horizontal_locator_available && m_vertical_locator_available; }

    int heading = 0;
    bool wantsdisconnect = false;
    int mode_heading = HEADING_NONE;
    int mode_alt = ALT_NONE;
    bool mode_ias = false;
    bool mode_gpws = true;
    int alt = 1000;
    int vs = 0;
    int ias = 150;

private:
    int ref_l = -1, ref_r = -1, ref_b = -1;
    float ref_span = 1.0f;
    float last_aileron = 0;
    bool m_vertical_locator_available = false;
    bool m_horizontal_locator_available = false;
    float m_ils_angle_vdev = -90;
    float m_ils_angle_hdev = -90;
    float m_ils_runway_heading = 0;
    float m_ils_runway_distance = 0;
};

} // namespace rorgd
