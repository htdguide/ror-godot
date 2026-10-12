#pragma once

#include "ror_node.h"
#include "ror_wings.h"

#include <godot_cpp/variant/vector3.hpp>

#include <memory>
#include <vector>

namespace rorgd {

// Upstream's `AeroEngine` (physics/air/AeroEngine.h): what the airplane keys, the wings' prop wash
// and the gauges ask of an engine.
class RorAeroEngine {
public:
    virtual ~RorAeroEngine() = default;
    virtual void update_forces(NodeArray &nodes, float dt, bool do_update) = 0;
    virtual void set_throttle(float val) = 0;
    virtual float throttle() const = 0;
    virtual void reset() = 0;
    virtual void toggle_reverse() = 0;
    virtual void flip_start() = 0;
    virtual float propwash() const = 0;
    virtual godot::Vector3 axis() const = 0;
    virtual int noderef() const = 0;
    virtual float radius() const = 0;
    virtual float rpm_pc() const = 0;
    virtual bool failed() const = 0;
    virtual bool ignition() const = 0;
};

// Upstream's `Turboprop` (physics/air/TurboProp.cpp), a turboprop or, with a fixed pitch, a piston
// prop: blade-element lift and drag on each of two to four blades from the airfoil, the pitch
// governed towards 1010 rpm, a warm-up, a torque reaction on the couple node, and the prop wash.
class RorTurboprop : public RorAeroEngine {
public:
    RorTurboprop(const NodeArray &nodes, int nr, int nb, int np1, int np2, int np3, int np4, int tqn, float power,
                 std::shared_ptr<RorAirfoil> airfoil, bool ispiston, float fpitch);
    void update_forces(NodeArray &nodes, float dt, bool do_update) override;
    void set_throttle(float val) override;
    float throttle() const override { return throtle; }
    void reset() override;
    void toggle_reverse() override;
    void flip_start() override;
    float propwash() const override { return propwash_; }
    godot::Vector3 axis() const override { return axis_; }
    int noderef() const override { return noderef_; }
    float radius() const override { return radius_; }
    float rpm_pc() const override { return rpm / 10.0f; }
    bool failed() const override { return failed_; }
    bool ignition() const override { return ignition_; }

    float pitch = 0.0f;
    float indicated_torque = 0.0f;
    float rpm = 0.0f;

private:
    bool is_piston;
    float fixed_pitch;
    int torquenode;
    float torquedist;
    std::shared_ptr<RorAirfoil> airfoil;
    float fullpower;
    float max_torque;
    float proparea;
    float airdensity = 1.225f;
    float timer = 0.0f;
    float lastflip = 0.0f;
    float warmupstart = 0.0f;
    float warmuptime = 14.0f;
    int numblades = 4;
    float bladewidth = 0.4f;
    float pitchspeed = 5.0f;
    float regspeed = 1010.0f;
    float twistmap[5] = {2, 6, 10, 19, 32};
    double rotenergy = 0.0;
    bool reverse = false;
    bool warmup = false;
    bool ignition_ = false;
    float radius_ = 0.0f;
    bool failed_ = false;
    float throtle = 0.0f;
    float propwash_ = 0.0f;
    godot::Vector3 axis_;
    int nodeback;
    int noderef_;
    int nodep[4] = {0, 0, 0, 0};
};

// Upstream's `Turbojet` (physics/air/TurboJet.cpp): thrust along its axis as it spools up, an
// afterburner past 95% throttle and 80% rpm, a reverser, and failure when its axis stretches.
class RorTurbojet : public RorAeroEngine {
public:
    RorTurbojet(const NodeArray &nodes, int front, int back, int ref, bool reversable, float dry_thrust, float wet_thrust,
                float back_diameter);
    void update_forces(NodeArray &nodes, float dt, bool do_update) override;
    void set_throttle(float val) override;
    float throttle() const override { return m_throtle; }
    void reset() override;
    void toggle_reverse() override;
    void flip_start() override;
    float propwash() const override { return m_propwash; }
    godot::Vector3 axis() const override { return m_axis; }
    int noderef() const override { return m_node_back; }
    float radius() const override { return m_radius; }
    float rpm_pc() const override { return m_rpm_percent; }
    bool failed() const override { return m_is_failed; }
    bool ignition() const override { return m_ignition; }
    bool afterburner() const { return m_afterburner_active; }
    // Upstream's `setRPM`.
    void set_rpm(float rpm) { m_rpm_percent = rpm; }

private:
    godot::Vector3 m_axis;
    bool m_afterburnable;
    bool m_afterburner_active = false;
    bool m_is_failed = false;
    bool m_ignition = false;
    bool m_reversable;
    bool m_reverse = false;
    bool m_warmup = false;
    float m_afterburn_thrust;
    float m_area;
    float m_exhaust_velocity = 0.0f;
    float m_last_flip = 0.0f;
    float m_max_dry_thrust;
    float m_propwash = 0.0f;
    float m_radius;
    float m_reflen;
    float m_rpm_percent = 0.0f;
    float m_throtle = 0.0f;
    float m_timer = 0.0f;
    float m_warmup_start = 0.0f;
    float m_warmup_time = 15.0f;
    int m_node_back;
    int m_node_front;
};

using AeroEngineArray = std::vector<std::unique_ptr<RorAeroEngine>>;

} // namespace rorgd
