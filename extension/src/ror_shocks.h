#pragma once

namespace rorgd {

// The rates of one `shocks2` or `shocks3` beam: upstream's `shock_t`, the part its laws read.
// Rates come in pairs, in (compression) and out (extension). `shocks2` makes each progressive
// towards its bound by `sprog`/`dprog`; `shocks3` splits each damping into a slow and a fast slope
// at `split` m/s.
struct RorShock {
    float spring_in = 0.0f;
    float damp_in = 0.0f;
    float spring_out = 0.0f;
    float damp_out = 0.0f;
    float sprog_in = 0.0f;
    float dprog_in = 0.0f;
    float sprog_out = 0.0f;
    float dprog_out = 0.0f;
    float split_in = 0.0f;
    float dslow_in = 0.0f;
    float dfast_in = 0.0f;
    float split_out = 0.0f;
    float dslow_out = 0.0f;
    float dfast_out = 0.0f;
    // `shocks2` option `s`: the bump is approached progressively instead of hit.
    bool soft_bump = false;
};

// What a shock's beam is besides its rates: its rest length, travel as fractions of it, and the
// structural spring and damping it meets past a bound (upstream's `sbd_spring`, `sbd_damp`).
struct RorShockBeam {
    float rest_length = 0.0f;
    float short_bound = 0.0f;
    float long_bound = 0.0f;
    float bump_spring = 0.0f;
    float bump_damp = 0.0f;
};

// Upstream's `Actor::CalcShocks2` and `CalcShocks3`, line for line: given the beam's extension
// (`difftoBeamL`) and its rate of stretch `v`, they replace the spring `k` and damping `d` the
// beam is computed with. `k` and `d` come in as the beam's own (the in rates).
void shock2_law(const RorShock &shock, const RorShockBeam &beam, float extension, float v, float &k, float &d);
void shock3_law(const RorShock &shock, const RorShockBeam &beam, float extension, float v, float &k, float &d);

} // namespace rorgd
