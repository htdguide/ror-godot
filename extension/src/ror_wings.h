#pragma once

#include "ror_node.h"

#include <godot_cpp/variant/string.hpp>

#include <memory>
#include <vector>

namespace rorgd {

// Upstream's `Airfoil` (physics/air/Airfoil.cpp): an X-Plane `.afl` polar read into lift, drag and
// moment coefficients every tenth of a degree from -180 to 180. One that cannot be read is all
// zeros, as upstream's is.
struct RorAirfoil {
    float cl[3601] = {};
    float cd[3601] = {};
    float cm[3601] = {};
    void load(const godot::String &text);
    void getparams(float a, float cratio, float cdef, float *ocl, float *ocd, float *ocm) const;
};

// Upstream's `FlexAirfoil`, its physics: a wing panel on eight nodes (front/back, left/right,
// down/up), its control surface of type `type` deflected between `mindef` and `maxdef`, and the
// lift, drag, induced drag and pitching moment `updateForces` puts on its corners.
struct RorWing {
    int nfld = 0, nfrd = 0, nflu = 0, nfru = 0, nbld = 0, nbrd = 0, nblu = 0, nbru = 0;
    char type = 'n';
    float chordratio = -1.0f;
    float mindef = -1.0f;
    float maxdef = -1.0f;
    float liftcoef = 1.0f;
    bool breakable = true;
    bool broken = false;
    bool hascontrol = false;
    bool isstabilator = false;
    float sref = 0.0f;
    float lratio = 0.0f;
    float rratio = 0.0f;
    float deflection = 0.0f;
    bool use_induced_drag = false;
    float id_span = 0.0f;
    float id_area = 0.0f;
    bool id_left = false;
    float aoa = 0.0f;
    std::shared_ptr<RorAirfoil> airfoil;

    // Upstream's constructor, its physics: the control surface kind and the break reference.
    void setup(const NodeArray &nodes);
    void set_control_deflection(float val);
    void enable_induced_drag(float span, float area, bool left);
    // Upstream's `updateVerticesPhysics`, its physics: a panel stretched past its reference breaks.
    void update_broken(const NodeArray &nodes);
    void update_forces(NodeArray &nodes);
};

// A vehicle's wings, with what upstream's spawner and actor keep for them: the induced drag run
// being built, and the aileron, rudder, elevator and flap the control surfaces follow.
class RorWingSet {
public:
    int add(RorWing wing, const NodeArray &nodes);
    void finish(const NodeArray &nodes);
    void set_controls(float aileron, float rudder, float elevator, int flap);
    // Upstream's `updateVisual` for the wings, once a frame.
    void update_frame(const NodeArray &nodes);
    void update_forces(NodeArray &nodes);
    int count() const { return static_cast<int>(m_wings.size()); }
    const RorWing &at(int index) const { return m_wings[static_cast<size_t>(index)]; }

private:
    std::vector<RorWing> m_wings;
    int m_first = -1;
    float m_area = 0.0f;
    float m_aileron = 0.0f, m_rudder = 0.0f, m_elevator = 0.0f;
    int m_flap = 0;
};

// Upstream's `ComputeWingArea`.
float wing_area(const godot::Vector3 &ref, const godot::Vector3 &x, const godot::Vector3 &y, const godot::Vector3 &aref);

} // namespace rorgd
