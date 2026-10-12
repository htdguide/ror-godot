#pragma once

#include "ror_turbo.h"

#include <vector>

namespace rorgd {

// Rigs of Rods' engine, gearbox and clutch, as a scalar system.
//
// A port of upstream's `Engine` reduced to what a ground vehicle with a keyboard needs:
// the torque curve, the engine's rotational inertia, the clutch that couples it to the
// wheels, upstream's automatic gearbox and the `engturbo` turbo (`RorTurbo`). Aero engines,
// manual clutch ranges, gear-shift sounds and the analogue input smoothing are not here.
//
// Nothing in this file knows about Godot or about nodes. It takes the wheels' rotation
// speed in and gives a torque out, which is exactly the interface upstream's
// `CalcDifferentials` uses, and it means the engine can be checked on its own.
class RorDrivetrain {
public:
    // From the `engine` section: "min_rpm, max_rpm, torque, diff_ratio, reverse_gear,
    // neutral_gear, forward gears..., -1". The gear ratios are stated at the crank and
    // multiplied by the differential here, the way upstream assembles them.
    void configure(float min_rpm, float max_rpm, float torque, float diff_ratio, float reverse_gear,
                   float neutral_gear, const std::vector<float> &forward_gears);
    // From the `engoption` section. A negative value means "keep the default", which is
    // how the file format says "unset".
    void set_options(float inertia, char type, float clutch_force, float clutch_time, float shift_time,
                     float post_shift_time, float idle_rpm, float stall_rpm, float braking_torque);
    // The torque curve, as (rpm, fraction of peak torque) pairs. Upstream's own models
    // live in `torque_models.cfg` and are passed in from there rather than invented here.
    void set_torque_curve(const std::vector<float> &rpm, const std::vector<float> &ratio);

    // Ignition. Without it the engine is a flywheel being dragged by the wheels.
    void set_contact(bool contact);
    void set_starter(bool starter);
    void set_throttle(float acc);
    // -1 reverse, 0 neutral, 1 drive. Upstream's `autoselect`, trimmed to the three a
    // ground vehicle uses; in drive the gearbox picks the gear itself.
    void set_selector(int selector);
    void start();
    void stop();

    // Advances by `dt`. `wheel_rpm` is the driveshaft speed the wheels are turning at,
    // which is what closes the loop: the clutch torque follows from the difference
    // between it and the engine. `do_update` marks the first substep of a rendered
    // frame, which is the rate upstream runs its gear decisions at.
    void step(float dt, float wheel_rpm, bool do_update);

    // The torque the clutch delivers to the driveshaft. Upstream's `getTorque()`.
    float clutch_torque() const { return m_clutch_torque; }
    float rpm() const { return m_rpm; }
    float max_rpm() const { return m_max_rpm; }
    int gear() const { return m_gear; }
    int gear_count() const { return m_gear_count; }
    float clutch() const { return m_clutch; }
    float crank_factor() const;
    float idle_rpm() const { return m_idle_rpm; }
    // What the command rams ask of the engine: whether to prime it, and the pump's work.
    void set_hydraulics(bool priming, float pump_work) {
        m_priming = priming;
        m_hydropump_work = pump_work;
    }
    bool running() const { return m_running; }
    bool contact() const { return m_contact; }
    bool configured() const { return m_gear_count > 0; }
    // Upstream's `setTCaseRatio`: a transfer case's reduction multiplies every gear; below 1 ignored.
    void set_tcase_ratio(float ratio);
    float tcase_ratio() const { return m_tcase_ratio; }
    // Peak torque times the curve's value at `rpm`. Upstream's `getEnginePower`.
    float engine_power(float rpm) const;
    // The `engturbo` turbo, whose power `engine_power` adds as upstream's `getEnginePower` does.
    RorTurbo &turbo() { return m_turbo; }
    // What cruise control reads and drives (upstream's `getAccToHoldRPM`, `getAcc`, `autoSetAcc`).
    float acc_to_hold_rpm() const;
    float current_acc() const { return m_shifting ? m_acc : m_commanded_acc; }
    // Ours keeps upstream's `m_auto_cur_acc` as the commanded throttle, which `step` turns into
    // the engine's own outside a shift, as `autoSetAcc` does.
    void auto_set_acc(float acc) { m_commanded_acc = acc; }
    float min_rpm() const { return m_min_rpm; }
    // An engine trigger's `setClutch` and `setAcc`.
    void trigger_clutch(float clutch) { m_clutch = clutch; }
    // An engine trigger's `shift`, upstream's own shift with its clutch timing.
    void trigger_shift(int by) { shift(by); }
    // Upstream's `setAcc`, which an engine trigger and the speed limiter use.
    void set_acc(float acc) {
        m_acc = acc;
        m_commanded_acc = acc;
    }
    float inertia() const { return m_inertia; }

private:
    float curve_power(float rpm) const;
    // The gear ratio in force, indexed upstream's way: 0 reverse, 1 neutral, 2 first.
    float ratio_of(int gear) const;
    void shift(int by);
    void update_gear_choice(float dt);
    void update_auto_clutch(float acc);
    float idle_mixture() const;
    float prime_mixture() const;

    std::vector<float> m_gear_ratios;
    // The torque curve's points and the Catmull-Rom tangents through them, so the curve
    // reads the same as the Ogre spline upstream evaluates it with.
    std::vector<float> m_curve_rpm;
    std::vector<float> m_curve_ratio;
    std::vector<float> m_curve_tangent;

    int m_gear_count = 0;
    float m_tcase_ratio = 1.0f;
    float m_min_rpm = 0.0f;
    float m_max_rpm = 0.0f;
    float m_torque = 0.0f;
    RorTurbo m_turbo;
    float m_idle_rpm = 0.0f;
    float m_stall_rpm = 300.0f;
    float m_inertia = 10.0f;
    float m_clutch_force = 10000.0f;
    float m_clutch_time = 0.2f;
    float m_shift_time = 0.5f;
    float m_post_shift_time = 0.2f;
    float m_braking_torque = 0.0f;
    float m_max_idle_mixture = 0.1f;
    float m_min_idle_mixture = 0.0f;

    float m_rpm = 0.0f;
    float m_acc = 0.0f;
    float m_commanded_acc = 0.0f;
    float m_clutch = 0.0f;
    float m_clutch_torque = 0.0f;
    float m_wheel_rpm = 0.0f;
    int m_gear = 0;
    int m_selector = 0;
    bool m_contact = false;
    bool m_starter = false;
    bool m_running = false;
    bool m_priming = false;
    float m_hydropump_work = 0.0f;

    int m_shifting = 0;
    int m_shift_val = 0;
    float m_shift_clock = 0.0f;
    int m_post_shifting = 0;
    float m_post_shift_clock = 0.0f;
};

} // namespace rorgd
