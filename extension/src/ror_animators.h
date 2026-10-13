#pragma once

#include <vector>

#include <godot_cpp/variant/vector3.hpp>

#include <cstdint>

namespace rorgd {

// Upstream's `ANIM_FLAG_*` (SimData.h), by their own bits.
enum RorAnimFlag : uint32_t {
    ANIM_AIRSPEED = 1u << 0,
    ANIM_VVI = 1u << 1,
    ANIM_ALTIMETER = 1u << 2,
    ANIM_AOA = 1u << 3,
    ANIM_FLAP = 1u << 4,
    ANIM_AIRBRAKE = 1u << 5,
    ANIM_ROLL = 1u << 6,
    ANIM_PITCH = 1u << 7,
    ANIM_THROTTLE = 1u << 8,
    ANIM_RPM = 1u << 9,
    ANIM_ACCEL = 1u << 10,
    ANIM_BRAKE = 1u << 11,
    ANIM_CLUTCH = 1u << 12,
    ANIM_TACHO = 1u << 13,
    ANIM_SPEEDO = 1u << 14,
    ANIM_PBRAKE = 1u << 15,
    ANIM_TURBO = 1u << 16,
    ANIM_SHIFTER = 1u << 17,
    ANIM_AETORQUE = 1u << 18,
    ANIM_AEPITCH = 1u << 19,
    ANIM_AESTATUS = 1u << 20,
    ANIM_TORQUE = 1u << 21,
    ANIM_HEADING = 1u << 22,
    ANIM_DIFFLOCK = 1u << 23,
    ANIM_BRUDDER = 1u << 28,
    ANIM_BTHROTTLE = 1u << 29,
};

// What an animator reads of the vehicle, gathered once a substep: upstream's `Actor` and `Engine`
// fields that `CalcAnimators` asks for. A vehicle here has no aero engines, wings, screw props or
// air brake, so those read as upstream's do with none.
// What an animator reads of one aero engine (upstream's `AeroEngine` and, for a prop, `Turboprop`).
struct RorAnimatorAero {
    float rpm_pc = 0.0f;
    float throttle = 0.0f;
    bool xprop = false;
    float indicated_torque = 0.0f;
    float max_torque = 0.0f;
    float pitch = 0.0f;
    bool ignition = false;
    bool failed = false;
};

struct RorAnimatorInputs {
    bool engine = false;
    float crank_factor = 0.0f;
    int gear = 0;
    int num_gears = 0;
    bool parking_brake = false;
    float wheel_speed = 0.0f;
    float speedo_max_kph = 140.0f;
    float rpm = 0.0f;
    float shift_up_rpm = 0.0f;
    float turbo_psi = 0.0f;
    float brake = 0.0f;
    float acc = 0.0f;
    float clutch = 0.0f;
    // The first wheel differential's kind by upstream's name: 0 Open, 1 Split, 2 Locked, 3 any
    // other; -1 for a vehicle with none.
    int diff_kind = -1;
    godot::Vector3 node0_velocity;
    float node0_height = 0.0f;
    godot::Vector3 camera_dir;
    godot::Vector3 camera_roll;
    // An airplane's: the flap step and air brake step (0 to 5 each), the wing count and wing 4's
    // angle of attack (the one upstream's gauge reads), and the aero engines.
    int aerial_flap = 0;
    int airbrake = 0;
    int num_wings = 0;
    float wing4_aoa = 0.0f;
    std::vector<RorAnimatorAero> aero;
    // A boat's screw props' rudders and throttles, as upstream's `getRudder` and `getThrottle` read them.
    std::vector<float> screw_rudders;
    std::vector<float> screw_throttles;
};

// Upstream's `Actor` fields the animators share across all of a vehicle's animators.
struct RorAnimatorMemory {
    float previous_crank = 0.0f;
    int previous_gear = 0;
    float shift_timer = 0.0f;
};

// Upstream's `Actor::CalcAnimators`: what one animator adds to `cstate` and `div`.
void calc_animator(uint32_t flags, float param, const RorAnimatorInputs &in, RorAnimatorMemory &memory, float &cstate,
                   int &div);

} // namespace rorgd
