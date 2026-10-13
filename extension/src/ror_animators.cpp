#include "ror_animators.h"

#include "ror_ogre_math.h"

#include <cmath>

namespace rorgd {

namespace {
// Upstream's fixed `PHYSICS_DT`, which the shifter's timer counts in.
constexpr float PHYSICS_DT = 0.0005f;
// Ogre 1.11's `Math::fRad2Deg`: `Real(180.0) / PI`, PI itself `Real(4.0 * atan(1.0))`.
const float RAD2DEG = 180.0f / static_cast<float>(4.0 * std::atan(1.0));
// SimConstants.h's `FLAP_ANGLES`.
constexpr float FLAP_ANGLES[6] = {0.f, -0.07f, -0.17f, -0.33f, -0.67f, -1.f};
} // namespace

void calc_animator(uint32_t flags, float param, const RorAnimatorInputs &in, RorAnimatorMemory &memory, float &cstate,
                   int &div) {
    // Boat rudder and throttle: the screw props' average, 0 with none.
    if (flags & ANIM_BRUDDER) {
        int spi;
        float ctmp = 0.0f;
        for (spi = 0; spi < static_cast<int>(in.screw_rudders.size()); spi++) {
            ctmp += in.screw_rudders[static_cast<size_t>(spi)];
        }
        if (spi > 0) {
            ctmp = ctmp / spi;
        }
        cstate = ctmp;
        div++;
    }
    if (flags & ANIM_BTHROTTLE) {
        int spi;
        float ctmp = 0.0f;
        for (spi = 0; spi < static_cast<int>(in.screw_throttles.size()); spi++) {
            ctmp += in.screw_throttles[static_cast<size_t>(spi)];
        }
        if (spi > 0) {
            ctmp = ctmp / spi;
        }
        cstate = ctmp;
        div++;
    }
    if (flags & ANIM_DIFFLOCK) {
        if (in.diff_kind >= 0) {
            if (in.diff_kind == 0) {
                cstate = 0.0f;
            }
            if (in.diff_kind == 1) {
                cstate = 0.5f;
            }
            if (in.diff_kind == 2) {
                cstate = 1.0f;
            }
        } else {
            cstate = 0.5f;
        }
        div++;
    }
    if (in.engine && (flags & ANIM_TORQUE)) {
        float torque = in.crank_factor;
        if (torque <= 0.0f) {
            torque = 0.0f;
        }
        if (torque >= memory.previous_crank) {
            cstate -= torque / 10.0f;
        } else {
            cstate = 0.0f;
        }
        if (cstate <= -1.0f) {
            cstate = -1.0f;
        }
        memory.previous_crank = torque;
        div++;
    }
    if (in.engine && (flags & ANIM_SHIFTER) && param == 3.0f) {
        const int shifter = in.gear;
        if (shifter > memory.previous_gear) {
            cstate = 1.0f;
            memory.shift_timer = 0.2f;
        }
        if (shifter < memory.previous_gear) {
            cstate = -1.0f;
            memory.shift_timer = -0.2f;
        }
        memory.previous_gear = shifter;
        if (memory.shift_timer > 0.0f) {
            cstate = 1.0f;
            memory.shift_timer -= PHYSICS_DT;
            if (memory.shift_timer < 0.0f) {
                memory.shift_timer = 0.0f;
            }
        }
        if (memory.shift_timer < 0.0f) {
            cstate = -1.0f;
            memory.shift_timer += PHYSICS_DT;
            if (memory.shift_timer > 0.0f) {
                memory.shift_timer = 0.0f;
            }
        }
        div++;
    }
    if (in.engine && (flags & ANIM_SHIFTER) && param == 1.0f) {
        const int shifter = in.gear;
        if (!shifter) {
            cstate = -0.5f;
        } else if (shifter < 0) {
            cstate = 1.0f;
        } else {
            cstate -= int((shifter - 1.0) / 2.0);
        }
        div++;
    }
    if (in.engine && (flags & ANIM_SHIFTER) && param == 2.0f) {
        const int shifter = in.gear;
        cstate = 0.5f;
        if (shifter < 0) {
            cstate = 1.0f;
        }
        if (shifter > 0) {
            cstate = shifter % 2;
        }
        div++;
    }
    if (in.engine && (flags & ANIM_SHIFTER) && param == 4.0f) {
        cstate -= (in.gear + 2.0) / (in.num_gears + 2.0);
        div++;
    }
    if (flags & ANIM_PBRAKE) {
        const float pbrake = in.parking_brake;
        cstate -= pbrake;
        div++;
    }
    if (flags & ANIM_SPEEDO) {
        const float speedo = in.wheel_speed / in.speedo_max_kph;
        cstate -= speedo * 3.0f;
        div++;
    }
    if (in.engine && (flags & ANIM_TACHO)) {
        const float tacho = in.rpm / in.shift_up_rpm;
        cstate -= tacho;
        div++;
    }
    if (in.engine && (flags & ANIM_TURBO)) {
        const float turbo = in.turbo_psi * 3.34;
        cstate -= turbo / 67.0f;
        div++;
    }
    if (flags & ANIM_BRAKE) {
        cstate -= in.brake;
        div++;
    }
    if (in.engine && (flags & ANIM_ACCEL)) {
        const float accel = in.acc;
        cstate -= accel + 0.06f;
        div++;
    }
    if (in.engine && (flags & ANIM_CLUTCH)) {
        const float clutch = in.clutch;
        cstate -= std::fabs(1.0f - clutch);
        div++;
    }
    // The aero engines: the parameter is the engine's index.
    if ((int)param < static_cast<int>(in.aero.size())) {
        const RorAnimatorAero &engine = in.aero[static_cast<size_t>((int)param)];
        if (flags & ANIM_RPM) {
            float angle;
            const float pcent = engine.rpm_pc;
            if (pcent < 60.0) {
                angle = -5.0 + pcent * 1.9167;
            } else if (pcent < 110.0) {
                angle = 110.0 + (pcent - 60.0) * 4.075;
            } else {
                angle = 314.0;
            }
            cstate -= angle / 314.0f;
            div++;
        }
        if (flags & ANIM_THROTTLE) {
            const float throttle = engine.throttle;
            cstate -= throttle;
            div++;
        }
        if ((flags & ANIM_AETORQUE) && engine.xprop) {
            cstate = (100.0 * engine.indicated_torque / engine.max_torque) / 120.0f;
            div++;
        }
        if ((flags & ANIM_AEPITCH) && engine.xprop) {
            cstate = engine.pitch / 120.0f;
            div++;
        }
        if (flags & ANIM_AESTATUS) {
            if (!engine.ignition) {
                cstate = 0.0f;
            } else {
                cstate = 0.5f;
            }
            if (engine.failed) {
                cstate = 1.0f;
            }
            div++;
        }
    }
    if (flags & ANIM_AIRSPEED) {
        const float ground_speed_kt = static_cast<float>(in.node0_velocity.length()) * 1.9438;
        const float altitude = in.node0_height;
        const float sea_level_pressure = 101325;
        const float airpressure = sea_level_pressure * std::pow(1.0 - 0.0065 * altitude / 288.15, 5.24947);
        const float airdensity = airpressure * 0.0000120896;
        const float kt = ground_speed_kt * std::sqrt(airdensity / 1.225);
        cstate -= kt / 100.0f;
        div++;
    }
    if (flags & ANIM_VVI) {
        const float vvi = in.node0_velocity.y * 196.85;
        cstate -= vvi / 6000.0f;
        if (cstate >= 1.0f) {
            cstate = 1.0f;
        }
        if (cstate <= -1.0f) {
            cstate = -1.0f;
        }
        div++;
    }
    if (flags & ANIM_ALTIMETER) {
        if (param == 3.0f) {
            const float altimeter = (in.node0_height * 1.1811) / 360.0f;
            const int alti_int = int(altimeter);
            const float alti_mod = (altimeter - alti_int);
            cstate -= alti_mod;
        }
        if (param == 2.0f) {
            const float alti = in.node0_height * 1.1811 / 3600.0f;
            const int alti_int = int(alti);
            const float alti_mod = (alti - alti_int);
            cstate -= alti_mod;
            if (cstate <= -1.0f) {
                cstate = -1.0f;
            }
        }
        if (param == 1.0f) {
            const float alti = in.node0_height * 1.1811 / 36000.0f;
            cstate -= alti;
            if (cstate <= -1.0f) {
                cstate = -1.0f;
            }
        }
        div++;
    }
    if (flags & ANIM_AOA) {
        float aoa = 0;
        if (in.num_wings > 4) {
            aoa = in.wing4_aoa / 25.0f;
        }
        if ((static_cast<float>(in.node0_velocity.length()) * 1.9438) < 10.0f) {
            aoa = 0;
        }
        cstate -= aoa;
        if (cstate <= -1.0f) {
            cstate = -1.0f;
        }
        if (cstate >= 1.0f) {
            cstate = 1.0f;
        }
        div++;
    }
    if (flags & ANIM_ROLL) {
        const godot::Vector3 rollv = in.camera_roll;
        const godot::Vector3 dirv = in.camera_dir;
        const godot::Vector3 upv = dirv.cross(-rollv);
        float rollangle = std::asin(static_cast<float>(rollv.y));
        rollangle = rollangle * RAD2DEG;
        if (upv.y < 0) {
            rollangle = 180.0f - rollangle;
        }
        cstate = rollangle / 180.0f;
        if (cstate >= 1.0f) {
            cstate = cstate - 2.0f;
        }
        div++;
    }
    if (flags & ANIM_PITCH) {
        const float pitchangle = std::asin(static_cast<float>(in.camera_dir.y));
        cstate = ((pitchangle * RAD2DEG) / 90.0f);
        div++;
    }
    if (flags & ANIM_AIRBRAKE) {
        const float airbrake = in.airbrake;
        cstate -= airbrake / 5.0f;
        div++;
    }
    if (flags & ANIM_FLAP) {
        const float flaps = FLAP_ANGLES[in.aerial_flap];
        cstate = flaps;
        div++;
    }
}

} // namespace rorgd
