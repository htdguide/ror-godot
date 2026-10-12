#pragma once

#include "ror_differentials.h"
#include "ror_node.h"

#include <godot_cpp/variant/vector3.hpp>

#include <vector>

namespace rorgd {

// How a wheel is driven. Upstream's `WheelPropulsion`, from the `propulsed` field.
enum class WheelDrive { NONE = 0, FORWARD = 1, BACKWARD = 2 };

// What a wheel's brakes answer to: upstream's `WheelBraking`, from the `braked` field, numbered as
// upstream numbers it ("DO NOT MODIFY NUMBERS - de/serialized from/to truck definition file"). Until
// 2026-10-12 this had foot-only at 2 and the skid brakes at 3 and 4, so a passenger car's foot-only
// front wheels (4) took the handbrake. The skid brakes brake one side under steering lock.
enum class WheelBrake { NONE = 0, FOOT_HAND = 1, FOOT_HAND_SKID_LEFT = 2, FOOT_HAND_SKID_RIGHT = 3, FOOT_ONLY = 4 };

// The wheels of a rig: where the drivetrain's torque becomes force on the tread.
//
// A Rigs of Rods wheel is not a rigid body. It is two axle nodes and a ring of tread
// nodes joined by beams, and driving it means putting a tangential force on each tread
// node about the axle. That is what makes a tyre deform under power, lose grip
// individually, and drive the vehicle through the same contact law as everything else,
// with no separate wheel-collision code.
//
// Tread nodes are laid out the way upstream's `wh_nodes` are: `count` of them starting at
// `first_tread`, alternating between the outer plane (even, braced to `axis_a`) and the
// inner one (odd, braced to `axis_b`).
struct RorWheel {
    int axis_a = 0;
    int axis_b = 0;
    int first_tread = 0;
    int tread_count = 0;
    // The node whose arm the reaction torque pushes against, and the axle node nearest
    // it. Driving a wheel has to push back on the suspension or the rig gains angular
    // momentum out of nothing, which is what makes a vehicle squat under power.
    int arm_node = 0;
    int near_attach_node = 0;
    float radius = 0.0f;
    float mass = 0.0f;
    WheelDrive drive = WheelDrive::NONE;
    WheelBrake brake = WheelBrake::NONE;

    // Tread speed at the rim, m/s, measured from the nodes each step.
    float speed = 0.0f;
    // Upstream's deliberately over-weighted average of that, which is what its braking
    // force estimate is built on.
    float average_speed = 0.0f;
    float torque = 0.0f;
    float last_torque = 0.0f;
    float last_retorque = 0.0f;
    // Accumulated rotation in radians, for turning the rim mesh.
    float rotation = 0.0f;
    // Upstream's `wh_is_detached`: taken off by a detacher group. It is handed no drive torque,
    // pushes nothing, and its speed is no longer measured; the differentials read its partner's.
    bool detached = false;
    // Upstream's `wh_tc_coef` and `wh_alb_coef`: how far traction control and the anti-lock brake
    // last held this wheel back. Zero until the first pulse sets them, as upstream's start.
    float tc_coef = 0.0f;
    float alb_coef = 0.0f;
};

// Upstream's traction control or anti-lock brake (`tc_*`, `alb_*`): its regulation ratio, its pulse
// and the timer that drives it, and whether it held a wheel back this step.
struct RorDriveAid {
    bool on = false;
    bool toggle = true;
    float ratio = 0.0f;
    float pulse_time = 0.0f;
    float min_speed = 0.0f;
    float timer = 0.0f;
    bool pulse_state = false;
    bool active = false;

    // Upstream's per-step pulse: the timer runs on, and past the pulse time flips the state.
    void tick(float dt) {
        timer += dt;
        if (timer >= pulse_time) {
            timer = 0.0f;
            pulse_state = !pulse_state;
        }
    }
};

// The wheel set of one rig.
class RorWheelSet {
public:
    // Returns the new wheel's index.
    int add(const RorWheel &wheel);
    int count() const { return static_cast<int>(m_wheels.size()); }
    const RorWheel &at(int index) const { return m_wheels[static_cast<size_t>(index)]; }
    int driven_count() const { return m_driven_count; }
    // Set when the rig declares an `axles` section. Upstream doubles the drive torque in
    // that case for backwards compatibility, so whether a rig has one changes how hard it
    // pulls and it has to be carried rather than assumed.
    void set_has_axles(bool has_axles) { m_has_axles = has_axles; }
    void set_brake_forces(float foot, float handbrake);
    RorDifferentials &differentials() { return m_diffs; }
    const RorDifferentials &differentials() const { return m_diffs; }
    void prepare_differentials() { m_diffs.prepare(m_wheels); }
    // Upstream's `ProcessTransferCase`: false if the differentials refuse it. Otherwise only the
    // case's first axle is driven, and its second as well when it has no 2WD.
    bool set_transfer_case(const RorTransferCase &transfer_case);
    // Upstream's `toggleTransferCaseMode` on the wheels: the second axle driven or not.
    void set_axle_driven(int axle, bool driven);
    void detach(int wheel) {
        if (wheel >= 0 && wheel < count()) {
            m_wheels[static_cast<size_t>(wheel)].detached = true;
        }
    }
    // Upstream's `SyncReset`: every wheel back on.
    void reattach_all() {
        for (RorWheel &wheel : m_wheels) {
            wheel.detached = false;
        }
    }

    // Driver input, 0..1 each.
    void set_brake(float brake) { m_brake = brake; }
    float brake() const { return m_brake; }
    void set_parking_brake(bool on) { m_parking_brake = on; }
    bool parking_brake() const { return m_parking_brake; }
    // Upstream's `ar_avg_wheel_speed`: the driven wheels' speed, smoothed every substep.
    float avg_speed() const { return m_avg_speed; }
    void reset_avg_speed() { m_avg_speed = 0.0f; }

    // Turns one step's drivetrain torque into force on every tread node, and measures
    // what the wheels are doing while it is there. `clutch_torque` is what the drivetrain
    // delivered to the driveshaft; `direction` is the vehicle's forward (upstream's
    // `getDirection`) and `steer` its steering state, which the driving aids and skid brakes read.
    void apply(NodeArray &nodes, float clutch_torque, const godot::Vector3 &direction, float steer, float dt);
    // Upstream's `CalcWheels` alone, on the torques the wheels already hold: aids, brakes, force
    // on the tread, speed, reaction. Public so it can be compared with upstream's case by case.
    void apply_wheels(NodeArray &nodes, const godot::Vector3 &direction, float steer, float dt);
    RorDriveAid &traction_control() { return m_tc; }
    RorDriveAid &antilock() { return m_abs; }
    RorWheel &wheel(int index) { return m_wheels[static_cast<size_t>(index)]; }

    // Average spin of the driven wheels, rad/s. What the drivetrain's clutch closes on.
    float driven_spin() const { return m_driven_spin; }
    // Average tread speed of the driven wheels, m/s.
    float driven_speed() const { return m_driven_speed; }

private:
    std::vector<RorWheel> m_wheels;
    int m_driven_count = 0;
    bool m_has_axles = false;
    RorDifferentials m_diffs;
    float m_brake_force = 0.0f;
    float m_handbrake_force = 0.0f;
    float m_brake = 0.0f;
    bool m_parking_brake = false;
    float m_driven_spin = 0.0f;
    float m_driven_speed = 0.0f;
    float m_avg_speed = 0.0f;
    RorDriveAid m_tc;
    RorDriveAid m_abs;
};

} // namespace rorgd
