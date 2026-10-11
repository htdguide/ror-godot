#include "ror_shocks.h"

#include <algorithm>
#include <cmath>

namespace rorgd {

namespace {
// A rate made progressive towards a bound: grows by `prog` times itself as the square of how far
// along the travel the beam is, capped at 1. Upstream writes this out six times; the arithmetic,
// and its order, is the same each time.
float progress(float extension, float bound, float rest_length) {
    float factor = 1.0f;
    if (bound != 0.0f) {
        factor = extension / (bound * rest_length);
        factor = std::min(factor * factor, 1.0f);
    }
    return factor;
}

// Ogre's `Math::Clamp`, which upstream's `CalcShocks3` uses: `max(min(value, high), low)`.
float clamp(float value, float low, float high) {
    return std::max(std::min(value, high), low);
}
} // namespace

void shock2_law(const RorShock &shock, const RorShockBeam &beam, float extension, float v, float &k, float &d) {
    const float L = beam.rest_length;
    if (v > 0) {
        k = shock.spring_out;
        d = shock.damp_out;
        const float factor = progress(extension, beam.long_bound, L);
        k += shock.sprog_out * k * factor;
        d += shock.dprog_out * d * factor;
    } else {
        k = shock.spring_in;
        d = shock.damp_in;
        const float factor = progress(extension, beam.short_bound, L);
        k += shock.sprog_in * k * factor;
        d += shock.dprog_in * d * factor;
    }
    if (shock.soft_bump) {
        const float beams_lep = L * 0.8f;
        const float long_prelimit = beam.long_bound * beams_lep;
        const float short_prelimit = -beam.short_bound * beams_lep;
        if (extension > long_prelimit) {
            // Back to the extension's progressive rates (upstream: "oscillating beam workaround").
            k = shock.spring_out;
            d = shock.damp_out;
            float factor = progress(extension, beam.long_bound, L);
            k += shock.sprog_out * k * factor;
            d += shock.dprog_out * d * factor;
            // And the bump's own progression on top.
            factor = 1.0f;
            if (beam.long_bound != 0.0f) {
                factor = ((extension - long_prelimit) * 5.0f) / (beam.long_bound * L);
                factor = std::min(factor * factor, 1.0f);
            }
            k += (k + 100.0f) * shock.sprog_out * factor;
            d += (d + 100.0f) * shock.dprog_out * factor;
            if (v < 0) {
                k = shock.spring_in;
                d = shock.damp_in;
            }
        } else if (extension < short_prelimit) {
            k = shock.spring_in;
            d = shock.damp_in;
            float factor = progress(extension, beam.short_bound, L);
            k += shock.sprog_in * k * factor;
            d += shock.dprog_in * d * factor;
            factor = 1.0f;
            if (beam.short_bound != 0.0f) {
                factor = ((extension - short_prelimit) * 5.0f) / (beam.short_bound * L);
                factor = std::min(factor * factor, 1.0f);
            }
            // Upstream uses the out progressions here, on the compression side; kept as it is.
            k += (k + 100.0f) * shock.sprog_out * factor;
            d += (d + 100.0f) * shock.dprog_out * factor;
            if (v > 0) {
                k = shock.spring_out;
                d = shock.damp_out;
            }
        }
        if (extension > beam.long_bound * L || extension < -beam.short_bound * L) {
            // Hard bump in soft mode.
            k = std::max(k, beam.bump_spring);
            d = std::max(d, beam.bump_damp);
        }
    } else if (extension > beam.long_bound * L || extension < -beam.short_bound * L) {
        k = beam.bump_spring;
        d = beam.bump_damp;
    }
}

void shock3_law(const RorShock &shock, const RorShockBeam &beam, float extension, float v, float &k, float &d) {
    const float L = beam.rest_length;
    if (extension > beam.long_bound * L) {
        const float ratio = extension - beam.long_bound * L;
        k += (beam.bump_spring - k) * ratio;
        d += (beam.bump_damp - d) * ratio;
    } else if (extension < -beam.short_bound * L) {
        const float ratio = -extension - beam.short_bound * L;
        k += (beam.bump_spring - k) * ratio;
        d += (beam.bump_damp - d) * ratio;
    } else if (v > 0) {
        v = clamp(std::abs(v), +0.15f, +20.0f);
        k = shock.spring_out;
        d = shock.damp_out * shock.dslow_out * std::min(v, shock.split_out) +
            shock.damp_out * shock.dfast_out * std::max(0.0f, v - shock.split_out);
        d /= v;
    } else if (v < 0) {
        v = clamp(std::abs(v), +0.15f, +20.0f);
        k = shock.spring_in;
        d = shock.damp_in * shock.dslow_in * std::min(v, shock.split_in) +
            shock.damp_in * shock.dfast_in * std::max(0.0f, v - shock.split_in);
        d /= v;
    }
}

} // namespace rorgd
