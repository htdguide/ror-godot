#pragma once

#include "ror_node.h"

namespace rorgd {

// Upstream's floor on a beam's length: ten centimetres.
inline constexpr float MIN_BEAM_LENGTH_M = 0.1f;

// Upstream's plastic deformation and breaking, from `ActorForcesEuler.cpp`. Returns the stress the
// beam actually carries, which is not what the spring law gave it in the step where it yields, and
// mutates the beam: its rest length, its yield stresses, its strength and whether it is broken.
float apply_beam_deformation(RorBeam &beam, float extension, float spring, float stress,
                             NodeArray &nodes);

} // namespace rorgd
