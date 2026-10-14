#pragma once

#include "ror_autopilot.h"
#include "ror_screwprop.h"
#include "ror_node.h"

#include <godot_cpp/variant/string.hpp>

#include <memory>
#include <vector>

namespace rorgd {

class RorAeroEngine;

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
    // Upstream's prop wash: which engines blow over the wing, and what share of it each covers.
    std::vector<int> wash_engines;
    std::vector<float> wash_ratios;

    // Upstream's constructor, its physics: the control surface kind and the break reference.
    void setup(const NodeArray &nodes);
    void set_control_deflection(float val);
    void enable_induced_drag(float span, float area, bool left);
    // Upstream's `updateVerticesPhysics`, its physics: a panel stretched past its reference breaks.
    void update_broken(const NodeArray &nodes);
    // `engines` are the vehicle's aero engines, whose wash adds to the wind; null for none.
    void update_forces(NodeArray &nodes, const std::vector<std::unique_ptr<RorAeroEngine>> *engines = nullptr);
};

// Upstream's `Airbrake` (physics/air/AirBrake.cpp): a panel that drags its four nodes as it opens,
// by the sine of its angle and the air's density at the reference node's height.
struct RorAirbrake {
    int noderef = 0, nodex = 0, nodey = 0, nodea = 0;
    float maxangle = 0.0f;
    float area = 0.0f;
    float ratio = 0.0f;
    void apply_force(NodeArray &nodes) const;
};

// A vehicle's wings and aero engines, with what upstream's spawner and actor keep for them: the
// induced drag run being built, the prop wash over each wing, and the aileron, rudder, elevator and
// flap the control surfaces follow.
class RorWingSet {
public:
    RorWingSet();
    ~RorWingSet();
    int add(RorWing wing, const NodeArray &nodes);
    int add_engine(std::unique_ptr<RorAeroEngine> engine);
    // Upstream's wing closure and `WashCalculator`, once every wing and engine is built.
    void finish(const NodeArray &nodes);
    int engine_count() const { return static_cast<int>(m_engines.size()); }
    RorAeroEngine &engine(int index) { return *m_engines[static_cast<size_t>(index)]; }
    // Upstream's `SyncReset` for the aero engines and the screw props.
    void reset_engines();
    int add_screwprop(const RorScrewprop &prop);
    int screwprop_count() const { return static_cast<int>(m_screwprops.size()); }
    RorScrewprop &screwprop(int index) { return m_screwprops[static_cast<size_t>(index)]; }
    const RorScrewprop &screwprop(int index) const { return m_screwprops[static_cast<size_t>(index)]; }
    // The sea the screw props push in.
    void set_water(bool has_water, float height) { m_has_water = has_water; m_water_height = height; }
    void set_controls(float aileron, float rudder, float elevator, int flap);
    int flap() const { return m_flap; }
    int add_airbrake(const RorAirbrake &airbrake);
    int airbrake_count() const { return static_cast<int>(m_airbrakes.size()); }
    const RorAirbrake &airbrake(int index) const { return m_airbrakes[static_cast<size_t>(index)]; }
    // Upstream's `setAirbrakeIntensity`: 0 to 5, each air brake's ratio a fifth of it.
    void set_airbrake_intensity(int intensity);
    int airbrake_intensity() const { return m_airbrake_intensity; }
    // Upstream's `updateVisual` for the wings, once a frame: the autopilot's aileron and elevator
    // added to the controls, then the control surfaces. `fuselage_back` is the fuselage drag's
    // node, or -1.
    void update_frame(const NodeArray &nodes, int fuselage_back = -1, const std::vector<RorLocalizer> &localizers = {});
    // The aileron, rudder and elevator the surfaces and the hydros followed this frame.
    float auto_aileron() const { return m_auto[0]; }
    float auto_rudder() const { return m_auto[1]; }
    float auto_elevator() const { return m_auto[2]; }
    // Upstream's `ar_autopilot`: made with the first aero engine, its references set as the wings close.
    RorAutopilot *autopilot() { return m_autopilot.get(); }
    void update_forces(NodeArray &nodes, float dt, bool do_update);
    int count() const { return static_cast<int>(m_wings.size()); }
    const RorWing &at(int index) const { return m_wings[static_cast<size_t>(index)]; }

private:
    std::vector<RorWing> m_wings;
    std::vector<std::unique_ptr<RorAeroEngine>> m_engines;
    std::vector<RorAirbrake> m_airbrakes;
    std::vector<RorScrewprop> m_screwprops;
    bool m_has_water = false;
    float m_water_height = 0.0f;
    std::unique_ptr<RorAutopilot> m_autopilot;
    // The first run's last wing's tips, where upstream hangs the navigation lights.
    int m_left_light = -1, m_right_light = -1;
    float m_auto[3] = {0.0f, 0.0f, 0.0f};
    int m_airbrake_intensity = 0;
    int m_first = -1;
    float m_area = 0.0f;
    float m_aileron = 0.0f, m_rudder = 0.0f, m_elevator = 0.0f;
    int m_flap = 0;
};

// Upstream's `ComputeWingArea`.
float wing_area(const godot::Vector3 &ref, const godot::Vector3 &x, const godot::Vector3 &y, const godot::Vector3 &aref);

} // namespace rorgd
