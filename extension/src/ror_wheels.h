#pragma once

#include "ror_node.h"

#include <godot_cpp/variant/vector3.hpp>

#include <vector>

namespace rorgd {

// How a wheel is driven. Upstream's `WheelPropulsion`, from the `propulsed` field.
enum class WheelDrive { NONE = 0, FORWARD = 1, BACKWARD = 2 };

// What a wheel's brakes answer to. Upstream's `WheelBraking`, from the `braked` field.
// Only whether the handbrake applies matters here; the two skid variants brake one side
// under steering lock, which is a handbrake-turn behaviour and is not modelled yet.
enum class WheelBrake { NONE = 0, FOOT_HAND = 1, FOOT_ONLY = 2, FOOT_HAND_SKID_LEFT = 3, FOOT_HAND_SKID_RIGHT = 4 };

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

    // Driver input, 0..1 each.
    void set_brake(float brake) { m_brake = brake; }
    void set_parking_brake(bool on) { m_parking_brake = on; }

    // Turns one step's drivetrain torque into force on every tread node, and measures
    // what the wheels are doing while it is there. `clutch_torque` is what the drivetrain
    // delivered to the driveshaft.
    void apply(NodeArray &nodes, float clutch_torque, float dt);

    // Average spin of the driven wheels, rad/s. What the drivetrain's clutch closes on.
    float driven_spin() const { return m_driven_spin; }
    // Average tread speed of the driven wheels, m/s.
    float driven_speed() const { return m_driven_speed; }

private:
    std::vector<RorWheel> m_wheels;
    int m_driven_count = 0;
    bool m_has_axles = false;
    float m_brake_force = 0.0f;
    float m_handbrake_force = 0.0f;
    float m_brake = 0.0f;
    bool m_parking_brake = false;
    float m_driven_spin = 0.0f;
    float m_driven_speed = 0.0f;
};

} // namespace rorgd
