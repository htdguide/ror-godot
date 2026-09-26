#pragma once

#include <cstring>

namespace rorgd {

// Rigs of Rods' approximate maths, reproduced bit for bit.
//
// Upstream computes its physics with deliberately imprecise functions — `approx_exp` is three
// integer operations on the bit pattern of a float — and their error is not noise around the
// true value. It is a systematic bias that the force laws were tuned against for fifteen
// years, so reproducing the laws with exact maths does not reproduce the physics.
//
// Measured on the contact law: our `std::exp` against upstream's `approx_exp` moved the force
// on a node by 24.9 kN out of 566 kN. The static friction branch computes
// `1 - approx_exp(-slip/va)`, and for small slip that subtraction cancels almost everything,
// turning a few percent of error in the exponential into tens of percent of the friction
// force. Which is to say: at low slip — a parked vehicle, a tyre about to break traction —
// upstream's friction is materially not the textbook answer, and matching the textbook is
// the wrong target.
//
// The type punning is done with memcpy rather than upstream's `*(float*)&i`, which is
// undefined behaviour that happens to work. The bits produced are identical; the difference
// is only that this cannot be miscompiled.
//
// From ApproxMath.h, Copyright 2009 Lefteris Stamatogiannakis, GPL-3.0-or-later.

inline float bits_to_float(int bits) {
    float out;
    std::memcpy(&out, &bits, sizeof(out));
    return out;
}

inline int float_to_bits(float value) {
    int out;
    std::memcpy(&out, &value, sizeof(out));
    return out;
}

// Upstream's approx_exp. The integer arithmetic is written exactly as upstream writes it,
// including the conversion of 1064652319 to a float, which cannot represent it and becomes
// 1064652288.
inline float approx_exp(const float x) {
    if (x < -15.0f) {
        return 0.0f;
    }
    if (x > 88.0f) {
        return 1e38f;
    }
    const int i = static_cast<int>(12102203.0f * x + 1064652319.0f);
    return bits_to_float(i);
}

// Upstream's approx_pow.
inline float approx_pow(const float x, const float y) {
    const int i = static_cast<int>(y * static_cast<float>(float_to_bits(x) - 1065353216) + 1065353216.0f);
    return bits_to_float(i);
}

// Upstream's approx_sqrt. Used for the node speed that drives air drag — so a rig's
// aerodynamic damping is computed from an approximate speed, not its actual one.
inline float approx_sqrt(const float y) {
    const int i = ((float_to_bits(y) - 1065353216) >> 1) + 1065353216;
    return bits_to_float(i);
}

// Upstream's fast_invSqrt: the Quake reciprocal square root with one Newton step. Accurate to
// about 0.2%, and what every beam length in a Rigs of Rods rig is divided by.
inline float fast_invSqrt(const float v) {
    const int i = 0x5f3759df - (float_to_bits(v) >> 1);
    float y = bits_to_float(i);
    y *= (1.5f - (0.5f * v * y * y));
    return y;
}

} // namespace rorgd
