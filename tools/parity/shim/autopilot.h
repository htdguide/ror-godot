// What upstream's `Autopilot` (gameplay/AutoPilot.h) holds, with its names, types and the values its
// `reset` gives them, without its sounds. The methods are upstream's, lifted by extract.py.
#pragma once

#include "rig_types.h"

namespace RoR {
class Autopilot {
public:
    enum { HEADING_NONE, HEADING_FIXED, HEADING_WLV, HEADING_NAV };
    enum { ALT_NONE, ALT_FIXED, ALT_VS };
    int heading = 0;
    bool wantsdisconnect = false;
    void setInertialReferences(node_t *refl, node_t *refr, node_t *refb, node_t *refc);
    int toggleHeading(int mode);
    int toggleAlt(int mode);
    bool toggleIAS();
    int adjHDG(int d);
    int adjALT(int d);
    int adjVS(int d);
    int adjIAS(int d);
    float getAilerons();
    float getElevator();
    float getThrottle(float thrtl, float dt);
    void UpdateIls();
    bool IsIlsAvailable() { return m_horizontal_locator_available && m_vertical_locator_available; }
    int m_actor_id = 0;
    bool force_disabled = false;
    int mode_heading = HEADING_NONE;
    int mode_alt = ALT_NONE;
    bool mode_ias = false;
    bool mode_gpws = true;
    int alt = 1000;
    int vs = 0;
    int ias = 150;
    node_t *ref_l = nullptr, *ref_r = nullptr, *ref_b = nullptr, *ref_c = nullptr;
    float ref_span = 1.0f;
    float last_elevator = 0, last_aileron = 0, last_rudder = 0, last_gpws_height = 0, last_pullup_height = 0;
    bool m_vertical_locator_available = false, m_horizontal_locator_available = false;
    float m_ils_angle_vdev = -90, m_ils_angle_hdev = -90, m_ils_runway_heading = 0, m_ils_runway_distance = 0;
    float last_closest_hdist = 0;
};
} // namespace RoR
