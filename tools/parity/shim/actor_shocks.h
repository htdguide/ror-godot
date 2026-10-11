// The part of Rigs of Rods' Actor that its shock laws, `CalcShocks2` and `CalcShocks3`, read.
//
// Both are member functions reading `ar_beams[i]` and the `shock_t` it points at. Declaring an
// Actor with only those fields lets the functions be compiled from upstream's source unmodified.
// The names, types and flag values are upstream's (SimData.h, BitFlags.h); a rename there breaks
// this build, which is the point.
#pragma once

#include "OgreVector3.h"

#include <algorithm>
#include <cmath>

using Ogre::Real;

namespace Ogre {
struct Math {
    // OgreMath.h: `std::max(std::min(val, maxval), minval)`.
    template <typename T> static T Clamp(T val, T minval, T maxval) {
        return std::max(std::min(val, maxval), minval);
    }
};
} // namespace Ogre

#define BITMASK( OFFSET ) ( 1 << ((OFFSET) - 1) )

enum ShockFlags {
    SHOCK_FLAG_NORMAL = BITMASK(1),
    SHOCK_FLAG_ISSHOCK2 = BITMASK(5),
    SHOCK_FLAG_ISSHOCK3 = BITMASK(6),
    SHOCK_FLAG_SOFTBUMP = BITMASK(7),
};

struct shock_t {
    int flags = 0;
    float springin = 0, dampin = 0, springout = 0, dampout = 0;
    float sprogin = 0, dprogin = 0, sprogout = 0, dprogout = 0;
    float splitin = 0, dslowin = 0, dfastin = 0, splitout = 0, dslowout = 0, dfastout = 0;
    float sbd_spring = 0, sbd_damp = 0;
};

struct beam_t {
    float L = 0;
    float shortbound = 0;
    float longbound = 0;
    shock_t *shock = nullptr;
};

namespace RoR {
class Actor {
public:
    beam_t *ar_beams = nullptr;
    void CalcShocks2(int i, Real difftoBeamL, Real &k, Real &d, Real v);
    void CalcShocks3(int i, Real difftoBeamL, Real &k, Real &d, Real v);
};
} // namespace RoR
