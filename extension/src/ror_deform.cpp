#include "ror_deform.h"

#include <algorithm>
#include <cmath>

using namespace godot;

namespace rorgd {

// Upstream's plastic deformation and breaking, from `ActorForcesEuler.cpp`.
//
// Past its yield stress a beam does not merely push back harder: its *rest length* moves, so the
// shape it returns to is the shape it was bent into. That is the difference between a rig that
// crumples and a rig that is a very stiff spring, and without it a vehicle bounces off a wall
// undamaged however hard it is driven at one.
//
// The arithmetic is upstream's, including the halving of the stress that is carried in the step
// where the yield happens and the asymmetry between compression and tension: compression keeps
// the beam's strength because removing it makes a structure fold up, while tension takes strength
// away because a stretched beam is a beam on its way to failing.
float apply_beam_deformation(RorBeam &beam, float extension, float spring, float stress,
                             NodeArray &nodes) {
    float magnitude = std::abs(stress);
    if (magnitude <= beam.minmax_stress || beam.strength <= 0.0f) {
        return stress;
    }
    if (beam.deformable && beam.bound != BeamBound::SHOCK1 && spring != 0.0f) {
        if (stress > beam.max_pos_stress && extension < 0.0f) {
            // Compression.
            const float yield_length = beam.max_pos_stress / spring;
            const float deform = extension + yield_length * (1.0f - beam.plastic_coef);
            const float old_length = beam.rest_length;
            beam.rest_length = std::max(MIN_BEAM_LENGTH_M, beam.rest_length + deform);
            stress = stress - (stress - beam.max_pos_stress) * 0.5f;
            magnitude = stress;
            if (beam.rest_length > 0.0f && old_length > beam.rest_length) {
                beam.max_pos_stress *= old_length / beam.rest_length;
                beam.minmax_stress = std::min(beam.max_pos_stress, -beam.max_neg_stress);
                beam.minmax_stress = std::min(beam.minmax_stress, beam.strength);
            }
        } else if (stress < beam.max_neg_stress && extension > 0.0f) {
            // Tension.
            const float yield_length = beam.max_neg_stress / spring;
            const float deform = extension + yield_length * (1.0f - beam.plastic_coef);
            const float old_length = beam.rest_length;
            beam.rest_length += deform;
            stress = stress - (stress - beam.max_neg_stress) * 0.5f;
            magnitude = -stress;
            if (old_length > 0.0f && beam.rest_length > old_length) {
                beam.max_neg_stress *= beam.rest_length / old_length;
                beam.minmax_stress = std::min(beam.max_pos_stress, -beam.max_neg_stress);
                beam.minmax_stress = std::min(beam.minmax_stress, beam.strength);
            }
            beam.strength -= deform * spring;
        }
    }
    if (magnitude > beam.strength) {
        // Upstream will not break the last beams holding a node that a collision triangle is
        // built on: a hole in the cab is worse than a beam that should have snapped.
        if (!(nodes[beam.a].cab_node && nodes[beam.a].active_beams < 3)
                && !(nodes[beam.b].cab_node && nodes[beam.b].active_beams < 3)) {
            beam.broken = true;
            nodes[beam.a].active_beams -= 1;
            nodes[beam.b].active_beams -= 1;
            return 0.0f;
        }
        // Held together, but softened: upstream halves what it can carry so the structure
        // around it takes the load instead.
        beam.strength = 2.0f * beam.minmax_stress;
    }
    return stress;
}

} // namespace rorgd
