#pragma once

#include <cstdint>

namespace rorgd {

// Upstream's `engturbo` turbo, the `NEW` mode of `Engine::UpdateEngine`: up to four turbos whose
// speed lags the throttle, each adding torque in proportion to its speed (version 1) or boost in
// proportion to its pressure (version 2, with blow-off valve, wastegate and anti-lag). Fields are
// upstream's, integers where upstream's are, and the arithmetic keeps upstream's double literals.
//
// Without an `engturbo` row an engine has upstream's `OLD` turbo, which only feeds sounds and the
// gauge; it is not modelled here.
struct RorTurbo {
    static constexpr int MAXTURBO = 4;

    bool enabled = false;
    int version = 1;
    float inertia_factor = 1.0f;
    int count = 1;
    int max_rpm = 200000;
    float addi_torque[MAXTURBO] = {0.0f, 0.0f, 0.0f, 0.0f};
    float engine_rpm_operation = 0.0f;
    bool has_bov = false;
    int min_bov_psi = 11;
    bool has_wastegate = false;
    float min_wastegate_psi = 20.0f;
    bool flutters = false;
    float wg_threshold_p = 0.0f;
    float wg_threshold_n = 0.0f;
    bool has_antilag = false;
    float antilag_min_rpm = 3000.0f;
    float antilag_rand_chance = 0.9975f;
    float antilag_power_factor = 170.0f;
    float rpm[MAXTURBO] = {0.0f, 0.0f, 0.0f, 0.0f};
    float bov_rpm[MAXTURBO] = {0.0f, 0.0f, 0.0f, 0.0f};
    // Upstream's `frand` state (`ApproxMath.h`), which starts at 1; upstream's is one per process.
    int32_t mirand = 1;

    // Upstream's `SetTurboOptions`; a parameter of 9999 is one the row did not state.
    void set_options(int type, float tinertia_factor, int nturbos, const float params[11]);
    // The turbo pass at the top of `UpdateEngine`. `acc` is the throttle with the idle and prime
    // mixtures applied, `cur_acc` the driver's own.
    void update(float dt, float acc, float cur_acc, float engine_rpm, float engine_max_rpm, bool running);
    // Upstream's `getTurboPower`, added to the engine's torque wherever it is asked for.
    float power(float engine_torque) const;
    float psi() const;
    // Upstream's `offStart`: every turbo spun down.
    void reset();
    float frand();
};

} // namespace rorgd
