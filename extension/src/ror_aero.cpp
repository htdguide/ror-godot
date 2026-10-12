#include "ror_aero.h"

#include "ror_ogre_math.h"

#include <cmath>

using namespace godot;

namespace rorgd {

namespace {
// SimConstants.h's `RAD_PER_SEC_TO_RPM`.
constexpr float RAD_PER_SEC_TO_RPM = 9.5492965855137f;

// Ogre's `Plane(normal, d).projectVector`: through `I - n n^T`, `n` as given, unit or not.
Vector3 project(const Vector3 &n, const Vector3 &v) {
    return ogre_project(n, v);
}

// Ogre's `isZeroLength`.
bool zero_length(const Vector3 &v) {
    const float sqlen = v.x * v.x + v.y * v.y + v.z * v.z;
    return sqlen < (1e-06 * 1e-06);
}
} // namespace

RorTurboprop::RorTurboprop(const NodeArray &nodes, int nr, int nb, int np1, int np2, int np3, int np4, int tqn,
                           float power, std::shared_ptr<RorAirfoil> foil, bool ispiston, float fpitch)
    : is_piston(ispiston), fixed_pitch(fpitch), torquenode(tqn), airfoil(std::move(foil)), nodeback(nb), noderef_(nr) {
    const auto at = [&nodes](int n) { return nodes[static_cast<size_t>(n)].position; };
    nodep[0] = np1;
    nodep[1] = np2;
    if (torquenode >= 0) {
        const Vector3 normal = ogre_normalised(at(nr) - at(nb));
        const Vector3 apos = project(normal, at(nr));
        const Vector3 tpos = project(normal, at(tqn));
        torquedist = static_cast<float>((apos - tpos).length());
    } else {
        torquedist = 1.0;
    }
    if (np3 < 0) {
        numblades = 2;
    } else {
        nodep[2] = np3;
        if (np4 < 0) {
            numblades = 3;
        } else {
            nodep[3] = np4;
        }
    }
    fullpower = power;
    max_torque = 9549.3 * fullpower / 1000.0;
    radius_ = static_cast<float>((at(noderef_) - at(nodep[0])).length());
    proparea = 3.14159 * radius_ * radius_;
    reset();
}

void RorTurboprop::update_forces(NodeArray &nodes, float dt, bool do_update) {
    RorNode &ref = nodes[static_cast<size_t>(noderef_)];
    const auto at = [&nodes](int n) { return nodes[static_cast<size_t>(n)].position; };
    if (do_update) {
        const float altitude = ref.position.y;
        const float sea_level_pressure = 101325;
        const float airpressure = sea_level_pressure * std::pow(1.0 - 0.0065 * altitude / 288.15, 5.24947);
        airdensity = airpressure * 0.0000120896;
    }
    timer += dt;
    float velacc = 0;
    for (int i = 0; i < numblades; i++) {
        velacc += static_cast<float>((nodes[static_cast<size_t>(nodep[i])].velocity - ref.velocity).length());
    }
    rpm = (velacc / numblades) * RAD_PER_SEC_TO_RPM / radius_;
    Vector3 avg;
    for (int i = 0; i < numblades; i++) {
        avg += at(nodep[i]);
    }
    avg = ogre_div(avg, static_cast<float>(numblades));
    if (static_cast<float>((avg - ref.position).length()) > 0.4) {
        failed_ = true;
    }
    float enginepower = 0;
    float warmupfactor = 1.0;
    if (warmup) {
        warmupfactor = (timer - warmupstart) / warmuptime;
        if (warmupfactor >= 1.0) {
            warmup = false;
        }
    }
    float revpenalty = 1.0;
    if (reverse) {
        revpenalty = 0.5;
    }
    if (!failed_ && ignition_) {
        enginepower = (0.0575 + throtle * revpenalty * 0.9425) * fullpower * warmupfactor;
    }
    float enginecouple = 0.0;
    if (rpm > 10.0) {
        enginecouple = 9549.3 * enginepower / rpm;
    } else {
        enginecouple = 9549.3 * enginepower / 10.0;
    }
    indicated_torque = enginecouple;
    if (torquenode >= 0) {
        const Vector3 along = at(noderef_) - at(nodeback);
        const Vector3 orth = project(along, at(noderef_)) - project(along, at(torquenode));
        Vector3 cdir = orth.cross(along);
        ogre_normalise(cdir);
        nodes[static_cast<size_t>(torquenode)].forces += cdir * (enginecouple / torquedist);
    }
    const float tipforce = (enginecouple / radius_) / numblades;
    if (fixed_pitch > 0) {
        pitch = fixed_pitch;
    } else if (!reverse) {
        if (throtle < 0.01) {
            if (pitch > 0 && rpm < regspeed * 1.4) {
                pitch -= pitchspeed * dt;
            }
            if (rpm > regspeed * 1.4) {
                pitch += pitchspeed * dt;
            }
        } else {
            float dpitch = rpm - regspeed;
            if (dpitch > pitchspeed) {
                dpitch = pitchspeed;
            }
            if (dpitch < -pitchspeed) {
                dpitch = -pitchspeed;
            }
            if (!(dpitch < 0 && pitch < 0) && !(dpitch > 0 && pitch > 45)) {
                pitch += dpitch * dt;
            }
        }
    } else {
        if (rpm < regspeed * 1.1) {
            if (pitch < -4.0) {
                pitch += pitchspeed * dt;
            } else {
                pitch -= pitchspeed * dt;
            }
        }
        if (rpm > regspeed * 1.11) {
            pitch -= pitchspeed * dt;
        }
    }
    if (!failed_) {
        axis_ = at(noderef_) - at(nodeback);
        ogre_normalise(axis_);
    }
    const float estrotenergy = 0.5 * numblades * nodes[static_cast<size_t>(nodep[0])].mass * radius_ * radius_ *
                               (rpm / RAD_PER_SEC_TO_RPM) * (rpm / RAD_PER_SEC_TO_RPM);
    float totthrust = 0;
    float tottorque = 0;
    for (int i = 0; i < numblades; i++) {
        RorNode &blade = nodes[static_cast<size_t>(nodep[i])];
        if (!failed_ && ignition_) {
            Vector3 totaltipforce;
            Vector3 spanv = blade.position - ref.position;
            ogre_normalise(spanv);
            const Vector3 refchordv = -axis_.cross(spanv);
            const Vector3 tipf = -refchordv;
            totaltipforce += tipf * static_cast<float>(tipforce - rpm / 10.0);
            for (int j = 0; j < 5; j++) {
                const float proport = ((float)j + 0.5) / 6.0;
                const Vector3 wind = -(blade.velocity * static_cast<float>(1.0 - proport) + ref.velocity * proport);
                const float wspeed = static_cast<float>(wind.length());
                Vector3 liftv = spanv.cross(-wind);
                ogre_normalise(liftv);
                const float degrees = static_cast<float>(pitch + twistmap[j] - 7.0);
                const Vector3 chordv = ogre_rotate_degrees(degrees, spanv, refchordv);
                const Vector3 normv = chordv.cross(spanv);
                Vector3 plane = normv.cross(chordv);
                ogre_normalise(plane);
                const Vector3 pwind = ogre_project(plane, wind);
                Vector3 dumb;
                float aoa = 0.0f;
                ogre_rotation_angle_axis(chordv, pwind, aoa, dumb);
                if (static_cast<float>(dumb.dot(spanv)) > 0) {
                    aoa = -aoa;
                }
                float cz, cx, cm;
                airfoil->getparams(aoa, 1.0, 0.0, &cz, &cx, &cm);
                const float s = radius_ * bladewidth / 6.0;
                Vector3 eforce = wind * static_cast<float>((4.0 * cx + cx * cx / (3.14159 * radius_ / bladewidth)) * 0.5 *
                                                           airdensity * wspeed * s);
                const float lift = cz * 0.5 * airdensity * wspeed * wspeed * s;
                eforce += liftv * lift;
                totthrust += static_cast<float>(eforce.dot(axis_));
                ref.forces += eforce * proport;
                totaltipforce += eforce * static_cast<float>(1.0 - proport);
            }
            tottorque += static_cast<float>(tipf.dot(totaltipforce)) * radius_;
            float correct = 0;
            if (rpm > 100) {
                correct = (rotenergy - estrotenergy) / (numblades * radius_ * dt * rpm / RAD_PER_SEC_TO_RPM);
            }
            if (correct > 1000.0) {
                correct = 1000.0;
            }
            if (correct < -1000.0) {
                correct = -1000.0;
            }
            blade.forces += totaltipforce + tipf * correct;
        } else if (!zero_length(ref.velocity)) {
            const Vector3 wind = -blade.velocity;
            const float wspeed = (static_cast<float>(wind.length()) / 15.0f) / (static_cast<float>(ref.velocity.length()) / 2.0f);
            blade.forces += wind * (airdensity * wspeed);
        }
    }
    rotenergy += (double)tottorque * dt * rpm / RAD_PER_SEC_TO_RPM;
    const float speed = static_cast<float>(ref.velocity.length());
    float thrsign = 1.0;
    if (totthrust < 0) {
        thrsign = -0.1;
        totthrust = -totthrust;
    }
    if (!failed_) {
        propwash_ = thrsign * std::sqrt(totthrust / (0.5 * airdensity * proparea) + speed * speed) - speed;
    } else {
        propwash_ = 0;
    }
    if (propwash_ < 0) {
        propwash_ = 0;
    }
}

void RorTurboprop::set_throttle(float val) {
    if (val > 1.0) {
        val = 1.0;
    }
    if (val < 0.0) {
        val = 0.0;
    }
    throtle = val;
}

void RorTurboprop::reset() {
    rpm = 0;
    throtle = 0;
    failed_ = false;
    ignition_ = false;
    reverse = false;
    pitch = 0;
    rotenergy = 0;
}

void RorTurboprop::toggle_reverse() {
    throtle = 0;
    reverse = !reverse;
    pitch = 0;
}

void RorTurboprop::flip_start() {
    if (timer - lastflip < 0.3) {
        return;
    }
    ignition_ = !ignition_;
    if (ignition_ && !failed_) {
        warmup = true;
        warmupstart = timer;
    }
    lastflip = timer;
}

RorTurbojet::RorTurbojet(const NodeArray &nodes, int front, int back, int ref, bool reversable, float dry_thrust,
                         float wet_thrust, float back_diameter)
    : m_afterburnable(wet_thrust > 0.f), m_reversable(reversable), m_afterburn_thrust(wet_thrust), m_max_dry_thrust(dry_thrust),
      m_node_back(back), m_node_front(front) {
    (void)ref;
    m_radius = back_diameter / 2.f;
    m_area = 2 * 3.14159 * m_radius * 0.6 * m_radius * 0.6;
    m_axis = nodes[static_cast<size_t>(front)].position - nodes[static_cast<size_t>(back)].position;
    m_reflen = static_cast<float>(m_axis.length());
    m_axis = ogre_div(m_axis, m_reflen);
    reset();
}

void RorTurbojet::update_forces(NodeArray &nodes, float dt, bool do_update) {
    (void)do_update;
    m_timer += dt;
    m_axis = nodes[static_cast<size_t>(m_node_front)].position - nodes[static_cast<size_t>(m_node_back)].position;
    const float axlen = static_cast<float>(m_axis.length());
    m_axis = ogre_div(m_axis, axlen);
    if (std::fabs(m_reflen - axlen) > 0.1) {
        m_rpm_percent = 0;
        m_is_failed = true;
    }
    float warmupfactor = 1.0;
    if (m_warmup) {
        warmupfactor = (m_timer - m_warmup_start) / m_warmup_time;
        if (warmupfactor >= 1.0) {
            m_warmup = false;
        }
    }
    if (m_rpm_percent < 0) {
        m_rpm_percent = 0;
    }
    float torque = -m_rpm_percent / 100.0;
    if (m_rpm_percent < 100.0 && !m_is_failed && m_ignition) {
        torque += ((0.2 + m_throtle * 0.8) * warmupfactor);
    }
    m_rpm_percent += (double)dt * torque * 30.0;
    float enginethrust = 0;
    if (!m_is_failed && m_ignition) {
        enginethrust = m_max_dry_thrust * m_rpm_percent / 100.0;
        m_afterburner_active = (m_afterburnable && m_throtle > 0.95 && m_rpm_percent > 80);
        if (m_afterburner_active) {
            enginethrust += (m_afterburn_thrust - m_max_dry_thrust);
        }
    } else {
        m_afterburner_active = false;
    }
    RorNode &back = nodes[static_cast<size_t>(m_node_back)];
    if (m_reverse) {
        back.forces -= m_axis * static_cast<float>(enginethrust * 1000.0);
    } else {
        back.forces += m_axis * static_cast<float>(enginethrust * 1000.0);
    }
    m_exhaust_velocity = enginethrust * 5.6 / m_area;
}

void RorTurbojet::set_throttle(float val) {
    if (val > 1.0) {
        val = 1.0;
    }
    if (val < 0.0) {
        val = 0.0;
    }
    m_throtle = val;
}

void RorTurbojet::reset() {
    m_rpm_percent = 0;
    m_throtle = 0;
    m_propwash = 0;
    m_is_failed = false;
    m_ignition = false;
    m_reverse = false;
}

void RorTurbojet::toggle_reverse() {
    if (!m_reversable) {
        return;
    }
    m_throtle = 0;
    m_reverse = !m_reverse;
}

void RorTurbojet::flip_start() {
    if (m_timer - m_last_flip < 0.3) {
        return;
    }
    m_ignition = !m_ignition;
    if (m_ignition && !m_is_failed) {
        m_warmup = true;
        m_warmup_start = m_timer;
    }
    m_last_flip = m_timer;
}

} // namespace rorgd
