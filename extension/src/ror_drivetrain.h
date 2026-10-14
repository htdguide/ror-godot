#pragma once

#include "ror_turbo.h"

#include <godot_cpp/variant/vector3.hpp>

#include <cmath>
#include <deque>
#include <vector>

namespace rorgd {

// What upstream's `Engine::UpdateEngine` reads of its actor, a frame at a time: node 0's velocity,
// the main camera's direction (its "gear hack" speed along the vehicle), wheel 0's radius, the
// brake, and the camera's longitudinal g-force (`getGForces().y`), which holds a shift back while
// the vehicle pitches.
struct RorEngineActor {
    godot::Vector3 node0_velocity;
    godot::Vector3 camera_dir;
    float wheel0_radius = 0.0f;
    float brake = 0.0f;
    float gforce_y = 0.0f;
};

// Rigs of Rods' engine, gearbox and clutch: upstream's `Engine` (gameplay/Engine.cpp), member for
// member, as a scalar system. Its `UpdateEngine` (the turbo, the torque balance, the starter, the
// clutch, the automatic shifting with its averages and kickdown, the auto clutch and the over-rev
// guard), its gearbox modes (automatic, semi-automatic, sequential manual, stick, stick with
// ranges), the shift methods, the manual clutch and its torque curve read through Ogre's
// `SimpleSpline` as upstream reads it. The turbo is `RorTurbo`, upstream's own turbo pass.
// Sounds, smoke and network state are not here.
//
// Nothing in this file knows about Godot or about nodes. It takes the wheels' rotation speed in
// and gives a torque out, which is exactly the interface upstream's `CalcDifferentials` uses.
class RorDrivetrain {
public:
    // Upstream's `SimGearboxMode` and `Engine::autoswitch`.
    enum Mode { AUTO, SEMI_AUTO, MANUAL, MANUAL_STICK, MANUAL_RANGES };
    enum Autoswitch { REAR, NEUTRAL, DRIVE, TWO, ONE, MANUALMODE };

    // From the `engine` section: "min_rpm, max_rpm, torque, diff_ratio, reverse_gear,
    // neutral_gear, forward gears..., -1", as upstream's constructor assembles them.
    void configure(float min_rpm, float max_rpm, float torque, float diff_ratio, float reverse_gear,
                   float neutral_gear, const std::vector<float> &forward_gears);
    // From the `engoption` section, upstream's `SetEngineOptions`. A value of 0 or less keeps the
    // default, which is how the file format says "unset".
    void set_options(float inertia, char type, float clutch_force, float clutch_time, float shift_time,
                     float post_shift_time, float idle_rpm, float stall_rpm, float braking_torque,
                     float max_idle_mixture = -1.0f, float min_idle_mixture = -1.0f);
    // The torque curve's points, (rpm, fraction of peak torque), as upstream adds them to its spline.
    void set_torque_curve(const std::vector<float> &rpm, const std::vector<float> &ratio);

    // Ignition (`m_contact`) and the starter, held.
    void set_contact(bool contact);
    void set_starter(bool starter) { m_starter = starter; }
    // The accelerator, upstream's `autoSetAcc`: the engine takes it now unless a shift holds it.
    void set_throttle(float acc) { auto_set_acc(std::fmax(0.0f, std::fmin(1.0f, acc))); }
    // -1 reverse, 0 neutral, 1 drive: upstream's `autoShiftSet(REAR, NEUTRAL, DRIVE)` in automatic,
    // and in the other modes a direct `shiftTo`.
    void set_selector(int selector);
    void start();  // Upstream's `startEngine`.
    void stop();   // Upstream's `offStart`, which leaves the engine dead.

    // Advances by `dt` (upstream's `UpdateEngine`). `wheel_rpm` is the driveshaft speed the wheels
    // turn at (`setWheelSpin`); `do_update` marks the first substep of a frame, where upstream
    // makes its gear decisions.
    void step(float dt, float wheel_rpm, bool do_update, const RorEngineActor &actor = RorEngineActor());

    // The gearbox: upstream's `shift`, `shiftTo`, `toggleAutoMode`, `autoShiftUp`/`Down`,
    // `setGearRange` and `setManualClutch` (a pedal 0 to 1, effective in the manual modes).
    void shift(int val);
    void shift_to(int gear) { shift(gear - m_cur_gear); }
    void toggle_auto_mode();
    void set_auto_mode(Mode mode) { m_auto_mode = mode; }
    void auto_shift_up();
    void auto_shift_down();
    void auto_shift_set(int mode);
    void set_gear_range(int range) { m_cur_gear_range = range; }
    void set_manual_clutch(float val);
    void set_gear(int gear) { m_cur_gear = gear; }
    Mode auto_mode() const { return m_auto_mode; }
    int autoselect() const { return m_autoselect; }
    int gear_range() const { return m_cur_gear_range; }
    int gear_ranges() const { return m_num_gears / 6 + 1; }
    bool electric() const { return m_engine_is_electric; }
    int shifting() const { return m_shifting; }
    int post_shifting() const { return m_post_shifting; }
    float shift_behaviour() const { return m_shift_behaviour; }

    // The torque the clutch delivers to the driveshaft. Upstream's `getTorque()`.
    float clutch_torque() const { return m_cur_clutch_torque; }
    float rpm() const { return m_cur_engine_rpm; }
    float max_rpm() const { return m_engine_max_rpm; }
    float min_rpm() const { return m_engine_min_rpm; }
    float idle_rpm() const { return m_engine_idle_rpm; }
    int gear() const { return m_cur_gear; }
    int gear_count() const { return m_num_gears; }
    float clutch() const { return m_cur_clutch; }
    float crank_factor() const;
    // What the command rams ask of the engine: whether to prime it, and the pump's work.
    void set_hydraulics(bool priming, float pump_work) {
        m_engine_is_priming = priming;
        m_hydropump_state = pump_work;
    }
    bool running() const { return m_engine_is_running; }
    bool contact() const { return m_contact; }
    bool configured() const { return m_num_gears > 0; }
    // Upstream's `setTCaseRatio`: a transfer case's reduction multiplies every gear; below 1 ignored.
    void set_tcase_ratio(float ratio);
    float tcase_ratio() const { return m_tcase_ratio; }
    // Upstream's `getEnginePower`: peak torque times the curve at `rpm`, and the turbo's.
    float engine_power(float rpm) const;
    RorTurbo &turbo() { return m_turbo; }
    // What cruise control reads and drives (upstream's `getAccToHoldRPM`, `getAcc`, `autoSetAcc`).
    float acc_to_hold_rpm() const;
    float current_acc() const { return m_cur_acc; }
    void auto_set_acc(float acc);
    // An engine trigger's `setClutch` and `shift`; `setAcc`, which a trigger and the limiter use.
    void trigger_clutch(float clutch) { m_cur_clutch = clutch; }
    void trigger_shift(int by) { shift(by); }
    void set_acc(float acc) { m_cur_acc = acc; }
    float inertia() const { return m_engine_inertia; }
    float torque_curve(float rpm) const;  // Upstream's `TorqueCurve::getEngineTorque`.

private:
    float ratio_of(int gear) const;
    void update_shifts();
    void update_auto_shift(float acc, const RorEngineActor &actor);
    float idle_mixture() const;
    float prime_mixture() const;
    void stop_engine() { m_engine_is_running = false; }

    std::vector<float> m_gear_ratios;
    // The torque curve's spline: its points' x (rpm) and y, and the tangents' y.
    std::vector<float> m_curve_x;
    std::vector<float> m_curve_y;
    std::vector<float> m_curve_tangent_y;
    RorTurbo m_turbo;

    int m_num_gears = 0;
    float m_diff_ratio = 1.0f;
    float m_tcase_ratio = 1.0f;
    float m_engine_min_rpm = 0.0f;
    float m_engine_max_rpm = 0.0f;
    float m_engine_torque = 0.0f;
    float m_engine_idle_rpm = 0.0f;
    float m_engine_stall_rpm = 300.0f;
    float m_engine_inertia = 10.0f;
    float m_clutch_force = 10000.0f;
    float m_clutch_time = 0.2f;
    float m_shift_time = 0.5f;
    float m_post_shift_time = 0.2f;
    float m_braking_torque = 0.0f;
    float m_max_idle_mixture = 0.1f;
    float m_min_idle_mixture = 0.0f;
    bool m_engine_is_electric = false;
    float m_full_rpm_range = 0.0f;
    float m_half_rpm_range = 0.0f;
    float m_one_third_rpm_range = 0.0f;

    float m_cur_engine_rpm = 0.0f;
    float m_cur_acc = 0.0f;
    float m_auto_cur_acc = 0.0f;
    float m_cur_clutch = 0.0f;
    float m_cur_clutch_torque = 0.0f;
    float m_cur_engine_torque = 0.0f;
    float m_cur_wheel_revolutions = 0.0f;
    float m_ref_wheel_revolutions = 0.0f;
    int m_cur_gear = 0;
    int m_cur_gear_range = 0;
    bool m_contact = false;
    bool m_starter = false;
    bool m_engine_is_running = false;
    bool m_engine_is_priming = false;
    float m_hydropump_state = 0.0f;
    Mode m_auto_mode = AUTO;
    int m_autoselect = DRIVE;

    int m_shifting = 0;
    int m_shift_val = 0;
    float m_shift_clock = 0.0f;
    int m_post_shifting = 0;
    float m_post_shift_clock = 0.0f;
    int m_kickdown_delay_counter = 0;
    int m_upshift_delay_counter = 0;
    float m_shift_behaviour = 0.0f;
    std::deque<float> m_rpms;
    std::deque<float> m_accs;
    std::deque<float> m_brakes;
};

} // namespace rorgd
