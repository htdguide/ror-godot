#include "ror_turbo.h"

#include <cstring>

namespace rorgd {

void RorTurbo::set_options(int type, float tinertia_factor, int nturbos, const float params[11]) {
    enabled = true;
    count = nturbos > MAXTURBO ? 4 : nturbos;
    version = type;
    inertia_factor = tinertia_factor;
    const float param1 = params[0], param2 = params[1], param3 = params[2], param4 = params[3];
    const float param5 = params[4], param6 = params[5], param7 = params[6], param8 = params[7];
    const float param9 = params[8], param10 = params[9], param11 = params[10];
    if (param2 != 9999) {
        engine_rpm_operation = param2;
    }
    if (version == 1) {
        for (int i = 0; i < count; i++) {
            addi_torque[i] = param1 / count;
        }
        return;
    }
    max_rpm = static_cast<int>(param1 * 10000);
    has_bov = param3 == 1;
    if (param3 != 9999) {
        min_bov_psi = static_cast<int>(param4);
    }
    has_wastegate = param5 == 1;
    if (param6 != 9999) {
        min_wastegate_psi = param6 * 10000;
    }
    if (param7 != 9999) {
        wg_threshold_n = 1 - param7;
        wg_threshold_p = 1 + param7;
    }
    has_antilag = param8 == 1;
    if (param9 != 9999) {
        antilag_rand_chance = param9;
    }
    if (param10 != 9999) {
        antilag_min_rpm = param10;
    }
    if (param11 != 9999) {
        antilag_power_factor = param11;
    }
}

float RorTurbo::frand() {
    mirand = static_cast<int32_t>(static_cast<uint32_t>(mirand) * 16807u);
    const uint32_t a = (static_cast<uint32_t>(mirand) & 0x007fffffu) | 0x40000000u;
    float f;
    std::memcpy(&f, &a, sizeof f);
    return (f - 2.0f) * 0.5f;
}

void RorTurbo::update(float dt, float acc, float cur_acc, float engine_rpm, float engine_max_rpm, bool running) {
    if (!enabled) {
        if (!old_mode) {
            return;
        }
        // Upstream's `OLD` turbo.
        float turbotorque = 0.0f;
        const float inertia = 0.000003f;
        turbotorque -= rpm[0] / 200000.0f;
        if (rpm[0] < 200000.0f && running && cur_acc > 0.06f) {
            turbotorque += 1.5f * cur_acc * (engine_rpm / engine_max_rpm);
        } else {
            turbotorque += 0.1f * (engine_rpm / engine_max_rpm);
        }
        rpm[0] += dt * turbotorque / inertia;
        return;
    }
    for (int i = 0; i < count; i++) {
        float turbotorque = 0.0f;
        float bov_torque = 0.0f;
        float inertia = 0.000003f * inertia_factor;
        turbotorque -= rpm[i] / max_rpm;
        bov_torque -= bov_rpm[i] / max_rpm;
        if (engine_rpm >= engine_rpm_operation) {
            const float drive = (engine_rpm - engine_rpm_operation) / (engine_max_rpm - engine_rpm_operation);
            if (rpm[i] <= max_rpm && running && acc > 0.06f) {
                if (has_wastegate) {
                    if (rpm[i] < min_wastegate_psi * wg_threshold_p && !flutters) {
                        turbotorque += 1.5f * acc * drive;
                    } else {
                        flutters = true;
                        turbotorque -= (rpm[i] / max_rpm) * 1.5;
                    }
                    if (flutters && rpm[i] < min_wastegate_psi * wg_threshold_n) {
                        flutters = false;
                    }
                } else {
                    turbotorque += 1.5f * acc * drive;
                }
            } else {
                turbotorque += 0.1f * drive;
            }
            // The wastegate, a valve on the exhaust side that makes the turbo flutter at its limit.
            if (has_wastegate) {
                if (rpm[i] > min_wastegate_psi * 0.95) {
                    inertia = inertia * 0.7;
                } else {
                    inertia = inertia * 1.3;
                }
            }
        }
        // Compressor surge.
        if (!has_bov && rpm[i] > 13 * 10000 && cur_acc < 0.06f) {
            turbotorque += (turbotorque * 2.5);
        }
        if (has_antilag && cur_acc < 0.5) {
            const float f = frand();
            if (engine_rpm > antilag_min_rpm && f > antilag_rand_chance && rpm[i] > max_rpm * 0.35 && rpm[i] < max_rpm) {
                turbotorque -= (turbotorque * (f * antilag_power_factor));
            }
        }
        rpm[i] += dt * turbotorque / inertia;
        // The blow-off valve: a second rotor limited to the turbo's speed, which is what the
        // engine is fed from when there is one.
        if (has_bov) {
            if (bov_rpm[i] < rpm[i]) {
                bov_torque += 1.5f * acc * (engine_rpm / engine_max_rpm);
            } else {
                bov_torque += 0.07f * (engine_rpm / engine_max_rpm);
            }
            if (cur_acc < 0.06 && rpm[i] > min_bov_psi * 10000) {
                bov_rpm[i] += dt * bov_torque / (inertia * 0.1);
            } else if (bov_rpm[i] < rpm[i]) {
                bov_rpm[i] += dt * bov_torque / (inertia * 0.05);
            } else {
                bov_rpm[i] += dt * bov_torque / inertia;
            }
        }
    }
}

float RorTurbo::psi() const {
    if (!enabled) {
        return rpm[0] / 10000.0f;
    }
    float total = 0;
    for (int i = 0; i < count; i++) {
        total += (has_bov ? bov_rpm[i] : rpm[i]) / 10000.0f;
    }
    return total;
}

float RorTurbo::power(float engine_torque) const {
    if (!enabled) {
        return 0.0f;
    }
    float value = 0.0f;
    if (version == 1) {
        for (int i = 0; i < count; i++) {
            value += addi_torque[i] * (rpm[i] / max_rpm);
        }
    } else {
        value = (((psi() * 6.8) * engine_torque) / 100);
    }
    return value;
}

void RorTurbo::reset() {
    for (int i = 0; i < count; i++) {
        rpm[i] = 0.0f;
        bov_rpm[i] = 0.0f;
    }
}

} // namespace rorgd
