#include "ror_wings.h"

#include "ror_approx.h"
#include "ror_ogre_math.h"

#include <godot_cpp/variant/packed_string_array.hpp>

#include <cmath>
#include <cstdio>
#include <cstring>
#include <algorithm>
#include <limits>

using namespace godot;

namespace rorgd {

namespace {

// Ogre 1.11's `Vector3::getRotationTo` (Sam Hocevar's "quaternion from two vectors") followed by
// `Quaternion::ToAngleAxis`, as `FlexAirfoil::updateForces` uses them: the angle in degrees and
// the axis.
void rotation_angle_axis(const Vector3 &from, const Vector3 &dest, float &degrees, Vector3 &axis) {
    float w = 1.0f, x = 0.0f, y = 0.0f, z = 0.0f;
    const float a = std::sqrt(static_cast<float>(from.length_squared()) * static_cast<float>(dest.length_squared()));
    float b = a + static_cast<float>(dest.dot(from));
    if (!(std::abs(b - 2 * a) <= std::numeric_limits<float>::epsilon() || a == 0)) {
        Vector3 c;
        if (b < 1e-06f * a) {
            b = 0.0f;
            c = std::abs(static_cast<float>(from.x)) > std::abs(static_cast<float>(from.z)) ? Vector3(-from.y, from.x, 0.0f)
                                                                                           : Vector3(0.0f, -from.z, from.y);
        } else {
            c = from.cross(dest);
        }
        w = b;
        x = c.x;
        y = c.y;
        z = c.z;
        const float len = std::sqrt(w * w + x * x + y * y + z * z);
        const float s = 1.0f / len;
        w *= s;
        x *= s;
        y *= s;
        z *= s;
    }
    const float sqr = x * x + y * y + z * z;
    float radians = 0.0f;
    if (sqr > 0.0) {
        // `Math::ACos`, then `2.0 * Radian`, the 2 a Real.
        const float acos_w = (-1.0 < w) ? (w < 1.0 ? std::acos(w) : 0.0f) : static_cast<float>(4.0 * std::atan(1.0));
        radians = 2.0f * acos_w;
        const float inv = 1.0f / std::sqrt(sqr);
        axis = Vector3(x * inv, y * inv, z * inv);
    } else {
        axis = Vector3(1.0f, 0.0f, 0.0f);
    }
    const float pi = static_cast<float>(4.0 * std::atan(1.0));
    degrees = radians * (180.0f / pi);
}

} // namespace

void RorAirfoil::load(const String &text) {
    bool process = false;
    bool neg = true;
    int lastia = -1;
    const PackedStringArray lines = text.split("\n");
    for (int k = 0; k < lines.size(); ++k) {
        const CharString row = lines[k].utf8();
        const char *line = row.get_data();
        if (std::strlen(line) == 0 || (std::strlen(line) == 1 && line[0] == '\r')) {
            continue;
        }
        if (!std::strncmp("alpha", line, 5)) {
            process = true;
            continue;
        }
        if (process) {
            float l = 0, d = 0, m = 0;
            int a = 0, b = 0;
            std::sscanf(line, "%i.%i %f %f %f", &a, &b, &l, &d, &m);
            if (neg) {
                b = -b;
            }
            if (a == 0 && b == 0) {
                neg = false;
            }
            const int ia = (a * 10 + b) + 1800;
            if (ia == 3600) {
                process = false;
            }
            if (ia < 0 || ia > 3600) {
                continue;
            }
            cl[ia] = l;
            cd[ia] = d;
            cm[ia] = m;
            if (lastia != -1 && ia - lastia > 1) {
                for (int i = 0; i < ia - lastia - 1; i++) {
                    cl[lastia + 1 + i] = cl[lastia] + (float)(i + 1) * (cl[ia] - cl[lastia]) / (float)(ia - lastia);
                    cd[lastia + 1 + i] = cd[lastia] + (float)(i + 1) * (cd[ia] - cd[lastia]) / (float)(ia - lastia);
                    cm[lastia + 1 + i] = cm[lastia] + (float)(i + 1) * (cm[ia] - cm[lastia]) / (float)(ia - lastia);
                }
            }
            lastia = ia;
        }
    }
}

void RorAirfoil::getparams(float a, float cratio, float cdef, float *ocl, float *ocd, float *ocm) const {
    const int ta = (int)(a / 360.0);
    float va = a - (float)(ta * 360);
    if (va > 180.0f) {
        va -= 360.0f;
    }
    if (va < -180.0f) {
        va += 360.0f;
    }
    const int ia = (int)((va + 180.0f) * 10.0f);
    float dva = va + 1.15 * (1.0 - cratio) * cdef;
    if (dva > 180.0f) {
        dva -= 360.0f;
    }
    if (dva < -180.0f) {
        dva += 360.0f;
    }
    const int dia = (int)((dva + 180.0f) * 10.0f);
    float sign = 1.0;
    if (cdef < 0) {
        sign = -1.0;
    }
    *ocl = cl[ia] - 0.66 * sign * (1.0 - cratio) * std::sqrt(std::fabs(cdef));
    *ocd = cd[dia] + 0.00015 * (1.0 - cratio) * cdef * cdef;
    *ocm = cm[ia] + 0.20 * sign * (1.0 - cratio) * std::sqrt(std::fabs(cdef));
}

void RorWing::setup(const NodeArray &nodes) {
    hascontrol = (type != 'n' && type != 'S' && type != 'T' && type != 'U' && type != 'V');
    isstabilator = (type == 'S' || type == 'T' || type == 'U' || type == 'V');
    const auto at = [&nodes](int n) { return nodes[static_cast<size_t>(n)].position; };
    const float tsref = 2.0 * static_cast<float>((at(nfrd) - at(nfld)).cross(at(nbld) - at(nfld)).length());
    sref = 2.0 * static_cast<float>((at(nfrd) - at(nfld)).cross(at(nbrd) - at(nfrd)).length());
    if (tsref > sref) {
        sref = tsref;
    }
    sref = sref * sref;
    lratio = static_cast<float>((at(nfld) - at(nflu)).length()) / static_cast<float>((at(nfld) - at(nbld)).length());
    rratio = static_cast<float>((at(nfrd) - at(nfru)).length()) / static_cast<float>((at(nfrd) - at(nbrd)).length());
}

void RorWing::set_control_deflection(float val) {
    if (val < 0) {
        deflection = -val * mindef;
    } else {
        deflection = val * maxdef;
    }
}

void RorWing::enable_induced_drag(float span, float area, bool left) {
    id_span = span;
    id_area = area;
    use_induced_drag = true;
    id_left = left;
}

void RorWing::update_broken(const NodeArray &nodes) {
    const auto at = [&nodes](int n) { return nodes[static_cast<size_t>(n)].position; };
    const Vector3 vx = at(nfrd) - at(nfld);
    const Vector3 vzl = at(nbld) - at(nfld);
    const Vector3 vzr = at(nbrd) - at(nfrd);
    const bool stretched = (static_cast<float>(vx.cross(vzl).length_squared()) > sref) ||
                           (static_cast<float>(vx.cross(vzr).length_squared()) > sref);
    broken = breakable ? (broken || stretched) : stretched;
}

void RorWing::update_forces(NodeArray &nodes) {
    if (!airfoil || broken) {
        return;
    }
    RorNode &fld = nodes[static_cast<size_t>(nfld)];
    RorNode &frd = nodes[static_cast<size_t>(nfrd)];
    const Vector3 wind = -(fld.velocity + frd.velocity) / 2.0;
    const float wspeed = static_cast<float>(wind.length());
    const auto at = [&nodes](int n) { return nodes[static_cast<size_t>(n)].position; };
    const Vector3 chordv = ((at(nbld) - at(nfld)) + (at(nbrd) - at(nfrd))) / 2.0;
    const float chord = static_cast<float>(chordv.length());
    const Vector3 spanv = ((at(nfrd) - at(nfld)) + (at(nbrd) - at(nbld))) / 2.0;
    const float span = static_cast<float>(spanv.length());
    const Vector3 liftv = spanv.cross(-wind);
    const float s = span * chord;
    Vector3 normv = chordv.cross(spanv);
    ogre_normalise(normv);
    // `Plane(Vector3::ZERO, normv, chordv)`: its normal is `normv x chordv`, normalised.
    Vector3 plane = normv.cross(chordv);
    ogre_normalise(plane);
    const Vector3 pwind = ogre_project(plane, -wind);
    Vector3 dumb;
    float angle = 0.0f;
    rotation_angle_axis(chordv, -pwind, angle, dumb);
    aoa = angle;
    if (static_cast<float>(dumb.dot(spanv)) > 0) {
        aoa = -aoa;
    }
    const float aoa_here = aoa;
    float cz, cx, cm;
    if (isstabilator) {
        airfoil->getparams(aoa_here - deflection, chordratio, 0, &cz, &cx, &cm);
    } else {
        airfoil->getparams(aoa_here, chordratio, deflection, &cz, &cx, &cm);
    }
    const float altitude = fld.position.y;
    const float sea_level_pressure = 101325;
    const float airpressure = sea_level_pressure * approx_pow(1.0 - 0.0065 * altitude / 288.15, 5.24947);
    const float airdensity = airpressure * 0.0000120896;
    Vector3 wforce = wind * static_cast<float>(cx * 0.5 * airdensity * wspeed * s);
    if (use_induced_drag) {
        const Vector3 idf = wind * static_cast<float>(cx * cx * 0.25 * airdensity * wspeed * id_area * id_area /
                                                      (3.14159 * id_span * id_span));
        if (id_left) {
            nodes[static_cast<size_t>(nblu)].forces += idf;
            nodes[static_cast<size_t>(nbld)].forces += idf;
        } else {
            nodes[static_cast<size_t>(nbru)].forces += idf;
            nodes[static_cast<size_t>(nbrd)].forces += idf;
        }
    }
    wforce += liftv * static_cast<float>(cz * 0.5 * airdensity * wspeed * chord);
    const float moment = -cm * 0.5 * airdensity * wspeed * wspeed * s;
    const Vector3 f1 = wforce * static_cast<float>(liftcoef * 0.75 / 4.0f) + normv * (liftcoef * moment / (4.0f * 0.25f));
    const Vector3 f2 = wforce * static_cast<float>(liftcoef * 0.25 / 4.0f) - normv * (liftcoef * moment / (4.0f * 0.75f));
    for (int n : {nfld, nflu, nfrd, nfru}) {
        nodes[static_cast<size_t>(n)].forces += f1;
    }
    for (int n : {nbld, nblu, nbrd, nbru}) {
        nodes[static_cast<size_t>(n)].forces += f2;
    }
}

int RorWingSet::add(RorWing wing, const NodeArray &nodes) {
    wing.setup(nodes);
    const auto at = [&nodes](int n) { return nodes[static_cast<size_t>(n)].position; };
    // Upstream's induced drag bookkeeping: a run of wings, each joined to the last by its node 1
    // being the last's node 0, shares an area and a span; a break in the run closes it.
    if (m_first == -1) {
        m_first = count();
        m_area = wing_area(at(wing.nfld), at(wing.nfrd), at(wing.nbld), at(wing.nbrd));
    } else {
        RorWing &previous = m_wings.back();
        if (wing.nfrd != previous.nfld) {
            RorWing &start = m_wings[static_cast<size_t>(m_first)];
            const float span = static_cast<float>(at(start.nfrd).distance_to(at(previous.nfld)));
            start.enable_induced_drag(span, m_area, false);
            previous.enable_induced_drag(span, m_area, true);
            m_first = count();
            m_area = wing_area(at(wing.nfld), at(wing.nfrd), at(wing.nbld), at(wing.nbrd));
        } else {
            m_area += wing_area(at(wing.nfld), at(wing.nfrd), at(wing.nbld), at(wing.nbrd));
        }
    }
    m_wings.push_back(wing);
    return count() - 1;
}

// Upstream's wing closure, once every wing is built.
void RorWingSet::finish(const NodeArray &nodes) {
    if (m_first == -1 || m_wings.empty()) {
        return;
    }
    RorWing &first = m_wings[static_cast<size_t>(m_first)];
    RorWing &last = m_wings.back();
    const float span = static_cast<float>(
            nodes[static_cast<size_t>(first.nfrd)].position.distance_to(nodes[static_cast<size_t>(last.nfld)].position));
    first.enable_induced_drag(span, m_area, false);
    last.enable_induced_drag(span, m_area, true);
}

void RorWingSet::set_controls(float aileron, float rudder, float elevator, int flap) {
    m_aileron = aileron;
    m_rudder = rudder;
    m_elevator = elevator;
    m_flap = flap;
}

// Each control surface deflected by the controls its kind follows, then the panel checked.
void RorWingSet::update_frame(const NodeArray &nodes) {
    const float aileron = std::clamp(m_aileron, -1.0f, 1.0f);
    const float rudder = std::clamp(m_rudder, -1.0f, 1.0f);
    const float elevator = std::clamp(m_elevator, -1.0f, 1.0f);
    static const float FLAP_ANGLES[6] = {0.f, -0.07f, -0.17f, -0.33f, -0.67f, -1.f};
    const float flap = FLAP_ANGLES[std::clamp(m_flap, 0, 5)];
    for (RorWing &wing : m_wings) {
        switch (wing.type) {
            case 'a': wing.set_control_deflection(aileron); break;
            case 'b': wing.set_control_deflection(-aileron); break;
            case 'r': wing.set_control_deflection(rudder); break;
            case 'e': case 'S': case 'T': wing.set_control_deflection(elevator); break;
            case 'f': wing.set_control_deflection(flap); break;
            case 'c': case 'V': wing.set_control_deflection((aileron + elevator) / 2.0); break;
            case 'd': case 'U': wing.set_control_deflection((-aileron + elevator) / 2.0); break;
            case 'g': wing.set_control_deflection((aileron + flap) / 2.0); break;
            case 'h': wing.set_control_deflection((-aileron + flap) / 2.0); break;
            case 'i': wing.set_control_deflection((-elevator + rudder) / 2.0); break;
            case 'j': wing.set_control_deflection((elevator + rudder) / 2.0); break;
            default: break;
        }
        wing.update_broken(nodes);
    }
}

void RorWingSet::update_forces(NodeArray &nodes) {
    for (RorWing &wing : m_wings) {
        wing.update_forces(nodes);
    }
}

float wing_area(const Vector3 &ref, const Vector3 &x, const Vector3 &y, const Vector3 &aref) {
    return (static_cast<float>(((x - ref).cross(y - ref)).length()) + static_cast<float>(((x - aref).cross(y - aref)).length())) *
           0.5f;
}

} // namespace rorgd
