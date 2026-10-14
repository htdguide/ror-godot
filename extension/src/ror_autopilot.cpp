#include "ror_autopilot.h"

#include "ror_ogre_math.h"

#include <cmath>

using godot::Vector3;

namespace rorgd {

RorLocalizer make_localizer(const Vector3 &position, const Vector3 &degrees, int type) {
    const OgreQuat q = ogre_mul(ogre_mul(ogre_quat(degrees.x, Vector3(1, 0, 0)), ogre_quat(degrees.y, Vector3(0, 1, 0))),
                                ogre_quat(degrees.z, Vector3(0, 0, 1)));
    RorLocalizer localizer;
    localizer.position = position;
    localizer.facing = ogre_rotate(q, Vector3(0, 0, 1));
    localizer.type = type;
    return localizer;
}

void RorAutopilot::reset() {
    mode_heading = HEADING_NONE;
    mode_alt = ALT_NONE;
    mode_ias = false;
    mode_gpws = true;
    heading = 0;
    alt = 1000;
    vs = 0;
    ias = 150;
    last_aileron = 0;
    m_ils_angle_vdev = -90;
    m_ils_angle_hdev = -90;
    m_ils_runway_heading = 0;
    m_ils_runway_distance = 0;
    wantsdisconnect = false;
    m_vertical_locator_available = false;
    m_horizontal_locator_available = false;
}

void RorAutopilot::disconnect() {
    mode_heading = HEADING_NONE;
    mode_alt = ALT_NONE;
    mode_ias = false;
    wantsdisconnect = false;
}

void RorAutopilot::set_references(const NodeArray &nodes, int left, int right, int back) {
    ref_l = left;
    ref_r = right;
    ref_b = back;
    if (left >= 0 && right >= 0) {
        ref_span = static_cast<float>(
                (nodes[static_cast<size_t>(left)].position - nodes[static_cast<size_t>(right)].position).length());
    }
}

float RorAutopilot::ailerons(const NodeArray &nodes) {
    float val = 0;
    if (ref_l >= 0 && ref_r >= 0) {
        const RorNode &l = nodes[static_cast<size_t>(ref_l)];
        const RorNode &r = nodes[static_cast<size_t>(ref_r)];
        const float rat = (r.position.y - l.position.y) / ref_span;
        float bank = 90.0;
        if (rat >= 1.0) {
            bank = 90.0;
        } else if (rat <= -1.0) {
            bank = -90.0;
        } else {
            bank = 57.3 * std::asin(rat);
        }
        if (mode_heading == HEADING_WLV) {
            val = bank / 100.0;
            if (val > 0.5) {
                val = 0.5;
            }
            if (val < -0.5) {
                val = -0.5;
            }
        }
        if (mode_heading == HEADING_FIXED || mode_heading == HEADING_NAV) {
            float target = (float)heading;
            if (mode_heading == HEADING_NAV) {
                float error_heading = m_ils_angle_hdev / 10.0;
                if (error_heading > 1.0) {
                    error_heading = 1.0;
                }
                if (error_heading < -1.0) {
                    error_heading = -1.0;
                }
                float offcourse_tolerance = m_ils_runway_distance / 30.0;
                if (offcourse_tolerance > 60.0) {
                    offcourse_tolerance = 60.0;
                }
                target = m_ils_runway_heading + error_heading * offcourse_tolerance;
            }
            const Vector3 vel = ogre_div(l.velocity + r.velocity, 2.0);
            const float curdir = std::atan2(static_cast<float>(vel.x), static_cast<float>(-vel.z)) * 57.295779513082;
            float want_bank = curdir - target;
            if (want_bank < -180.0) {
                want_bank += 360.0;
            }
            want_bank = want_bank * 2.0;
            if (want_bank > 45.0) {
                want_bank = 45.0;
            }
            if (want_bank < -45.0) {
                want_bank = -45.0;
            }
            val = (bank - want_bank) / 100.0;
            if (val > 0.5) {
                val = 0.5;
            }
            if (val < -0.5) {
                val = -0.5;
            }
        }
    }
    last_aileron = (last_aileron + val) / 2.0;
    return last_aileron;
}

float RorAutopilot::elevator(const NodeArray &nodes) const {
    float val = 0;
    if (ref_l >= 0 && ref_r >= 0 && ref_b >= 0) {
        const RorNode &l = nodes[static_cast<size_t>(ref_l)];
        const RorNode &r = nodes[static_cast<size_t>(ref_r)];
        float wanted_vs = (float)vs / 196.87;
        const float current_vs = (l.velocity.y + r.velocity.y) / 2.0;
        const float pitch_var = current_vs - nodes[static_cast<size_t>(ref_b)].velocity.y;
        if (mode_alt == ALT_VS) {
            if (mode_heading == HEADING_NAV) {
                const float ch = m_ils_runway_distance * std::sin((m_ils_angle_vdev + 4.0) / 57.295779513082);
                const float oh = m_ils_runway_distance * std::sin((4.0) / 57.295779513082);
                wanted_vs = 5000.0 / 196.87;
                float wanted_vs2 = (-ch + oh) / 5.0;
                if (wanted_vs2 < -wanted_vs) {
                    wanted_vs2 = -wanted_vs;
                }
                if (wanted_vs2 > wanted_vs) {
                    wanted_vs2 = wanted_vs;
                }
                val = (wanted_vs2 - current_vs) / 40.0 + pitch_var / 40.0;
                if (val > 0.75) {
                    val = 0.75;
                }
                if (val < -0.75) {
                    val = -0.75;
                }
            } else {
                val = (wanted_vs - current_vs) / 40.0 + pitch_var / 40.0;
                if (val > 0.5) {
                    val = 0.5;
                }
                if (val < -0.5) {
                    val = -0.5;
                }
            }
        }
        if (mode_alt == ALT_FIXED) {
            const float wanted_alt = (float)alt * 0.3048;
            const float current_alt = (l.position.y + r.position.y) / 2.0;
            if (wanted_vs < 0) {
                wanted_vs = -wanted_vs;
            }
            float wanted_vs2 = (wanted_alt - current_alt) / 8.0;
            if (wanted_vs2 < -wanted_vs) {
                wanted_vs2 = -wanted_vs;
            }
            if (wanted_vs2 > wanted_vs) {
                wanted_vs2 = wanted_vs;
            }
            val = (wanted_vs2 - current_vs) / 40.0 + pitch_var / 40.0;
            if (val > 0.5) {
                val = 0.5;
            }
            if (val < -0.5) {
                val = -0.5;
            }
        }
    }
    return val;
}

float RorAutopilot::throttle(const NodeArray &nodes, float thrtl, float dt) const {
    if (!mode_ias) {
        return thrtl;
    }
    float val = thrtl;
    if (ref_l >= 0 && ref_r >= 0) {
        const RorNode &l = nodes[static_cast<size_t>(ref_l)];
        const RorNode &r = nodes[static_cast<size_t>(ref_r)];
        const float altitude = l.position.y;
        const float sea_level_pressure = 101325;
        const float airpressure = sea_level_pressure * std::pow(1.0 - 0.0065 * altitude / 288.15, 5.24947);
        const float airdensity = airpressure * 0.0000120896;
        const float gspd = 1.94384449 * ogre_div(l.velocity + r.velocity, 2.0).length();
        const float spd = gspd * std::sqrt(airdensity / 1.225);
        if (spd > (float)ias) {
            val = val - dt / 15.0;
        }
        if (spd < (float)ias) {
            val = val + dt / 15.0;
        }
        if (val > 1.0) {
            val = 1.0;
        }
        if (val < 0.02) {
            val = 0.02;
        }
    }
    return val;
}

int RorAutopilot::toggle_heading(int mode) {
    mode_heading = mode == mode_heading ? HEADING_NONE : mode;
    return mode_heading;
}

int RorAutopilot::toggle_alt(int mode) {
    mode_alt = mode == mode_alt ? ALT_NONE : mode;
    return mode_alt;
}

bool RorAutopilot::toggle_ias() {
    mode_ias = !mode_ias;
    return mode_ias;
}

bool RorAutopilot::toggle_gpws() {
    mode_gpws = !mode_gpws;
    return mode_gpws;
}

int RorAutopilot::adj_hdg(int d) {
    heading += d;
    if (heading < 0) {
        heading += 360;
    }
    if (heading > 359) {
        heading -= 360;
    }
    return heading;
}

int RorAutopilot::adj_alt(int d) {
    alt += d;
    return alt;
}

int RorAutopilot::adj_vs(int d) {
    vs += d;
    if (vs > 9900) {
        vs = 9900;
    }
    if (vs < -9900) {
        vs = -9900;
    }
    return vs;
}

int RorAutopilot::adj_ias(int d) {
    ias += d;
    if (ias < 0) {
        ias = 0;
    }
    if (ias > 350) {
        ias = 350;
    }
    return ias;
}

void RorAutopilot::update_ils(const NodeArray &nodes, const std::vector<RorLocalizer> &localizers) {
    if (ref_l < 0 || ref_r < 0) {
        return;
    }
    const Vector3 position =
            ogre_div(nodes[static_cast<size_t>(ref_l)].position + nodes[static_cast<size_t>(ref_r)].position, 2.0);
    float closest_hdist = -1;
    float closest_hangle = -90;
    float closest_vdist = -1;
    float closest_vangle = -90;
    m_ils_runway_heading = 0;
    const Vector3 up(0, 1, 0);
    for (const RorLocalizer &localizer : localizers) {
        const Vector3 plocd = ogre_project(up, localizer.facing);
        const float loc = std::atan2(static_cast<float>(plocd.z), static_cast<float>(plocd.x));
        const Vector3 posd = ogre_project(up, position - localizer.position);
        const float dir = std::atan2(static_cast<float>(posd.z), static_cast<float>(posd.x));
        float diff = (dir - loc) * 57.295779513082;
        if (diff > 180.0) {
            diff -= 360.0;
        }
        if (diff < -180.0) {
            diff += 360.0;
        }
        if (diff < 80 && diff > -80) {
            const float dist = static_cast<float>((localizer.position - position).length());
            if (localizer.type == RorLocalizer::HORIZONTAL) {
                if (closest_hdist < 0 || closest_hdist > dist) {
                    closest_hdist = dist;
                    closest_hangle = diff;
                    m_ils_runway_heading = loc * 57.295779513082 - 90.0;
                    if (m_ils_runway_heading < 0.0) {
                        m_ils_runway_heading += 360.0;
                    }
                    m_ils_runway_distance = dist;
                }
            }
            if (localizer.type == RorLocalizer::VERTICAL) {
                if (closest_vdist < 0 || closest_vdist > dist) {
                    const Vector3 normv = localizer.facing.cross(up);
                    const float glideslope = 4;
                    const Vector3 posd2 = ogre_project(normv, position - localizer.position);
                    float d = static_cast<float>(posd2.length());
                    if (d < 0.01) {
                        d = 0.01;
                    }
                    float dir2 = 90.0;
                    d = posd2.y / d;
                    if (d >= 1.0) {
                        dir2 = 90.0;
                    } else if (d <= -1.0) {
                        dir2 = -90.0;
                    } else {
                        dir2 = std::asin(d) * 57.295779513082;
                    }
                    const float diff2 = dir2 - glideslope;
                    closest_vdist = dist;
                    closest_vangle = diff2;
                }
            }
        }
    }
    m_ils_angle_hdev = closest_hangle;
    m_ils_angle_vdev = closest_vangle;
    m_horizontal_locator_available = (closest_hdist != -1);
    m_vertical_locator_available = (closest_vdist != -1);
    last_closest_hdist = closest_hdist;
    if (mode_heading == HEADING_NAV) {
        // Disconnect close to the runway, or with no approach in range.
        if (closest_hdist < 20.0 || closest_vdist < 20.0) {
            wantsdisconnect = true;
        }
        if (!ils_available()) {
            wantsdisconnect = true;
        }
    }
}

} // namespace rorgd
