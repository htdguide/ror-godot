// The fields of Rigs of Rods' Engine that its turbo reads and writes, with upstream's names, types
// and constructor defaults (gameplay/Engine.h, Engine.cpp), so that the turbo pass of
// `Engine::UpdateEngine`, `SetTurboOptions`, `getTurboPSI` and `getTurboPower` compile as written.
#pragma once

#define MAXTURBO 4
#ifndef SOUND_START
#define SOUND_START(actor, trig)
#define SOUND_STOP(actor, trig)
#endif
#ifndef LOG
#define LOG(message)
#endif

namespace RoR {

class Engine {
public:
    enum turbomode { OLD, NEW };

    void SetTurboOptions(int type, float tinertiaFactor, int nturbos, float param1, float param2, float param3, float param4, float param5, float param6, float param7, float param8, float param9, float param10, float param11);
    float getTurboPSI();
    float getTurboPower();
    // The `if (m_engine_has_turbo)` block of `UpdateEngine`, with its local `acc`.
    void UpdateTurbo(float dt, float acc);

    void *m_actor = nullptr;
    bool m_engine_has_turbo = true;
    int m_engine_turbo_mode = OLD;
    bool m_engine_is_running = true;
    float m_cur_acc = 0.0f;
    float m_cur_engine_rpm = 0.0f;
    float m_engine_max_rpm = 0.0f;
    float m_engine_torque = 0.0f;
    int m_turbo_ver = 1;
    float m_cur_turbo_rpm[MAXTURBO] = {0, 0, 0, 0};
    float m_turbo_inertia_factor = 1;
    int m_num_turbos = 1;
    int m_max_turbo_rpm = 200000;
    float m_engine_addi_torque[MAXTURBO] = {0, 0, 0, 0};
    float m_turbo_engine_rpm_operation = 0.0f;
    bool m_turbo_has_bov = false;
    float m_turbo_bov_rpm[MAXTURBO] = {0, 0, 0, 0};
    int m_min_bov_psi = 11;
    bool m_turbo_has_wastegate = false;
    float m_min_wastegate_psi = 20;
    bool m_turbo_flutters = false;
    float m_turbo_wg_threshold_p = 0;
    float m_turbo_wg_threshold_n = 0;
    bool m_turbo_has_antilag = false;
    float m_antilag_min_rpm = 3000;
    float m_antilag_rand_chance = 0.9975;
    float m_antilag_power_factor = 170;
};

} // namespace RoR

// `ApproxMath.h`'s `frand` state back to its start, between cases.
void reset_frand();
