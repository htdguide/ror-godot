// The part of Rigs of Rods' Differentials.h that its four differential laws use.
//
// `Differential::CalcSeparateDiff`, `CalcOpenDiff`, `CalcViscousDiff` and `CalcLockedDiff` are
// static and read only `DifferentialData`, so declaring the struct and the class's statics lets
// them be compiled from upstream's source unmodified. Names and layout are upstream's.
#pragma once

#include "actor_shocks.h"

namespace RoR {
struct DifferentialData {
    float speed[2];
    float delta_rotation;
    float out_torque[2];
    float in_torque;
    float dt;
};

class Differential {
public:
    static void CalcSeparateDiff(DifferentialData &diff_data);
    static void CalcOpenDiff(DifferentialData &diff_data);
    static void CalcViscousDiff(DifferentialData &diff_data);
    static void CalcLockedDiff(DifferentialData &diff_data);
};
} // namespace RoR
