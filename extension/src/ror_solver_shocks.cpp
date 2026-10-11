#include "ror_solver.h"

// The beam laws past a beam's travel: what bound a beam has and what it does there. Kept apart
// from `ror_solver.cpp`, which steps them, because `shocks2` and `shocks3` each bring a law and a
// set of rates of their own (`ror_shocks.cpp`).

using namespace godot;

namespace rorgd {

// What a beam does outside the travel it was given. Upstream's `CalcBeams` branches, and the
// reason a rig has suspension rather than springs: a shock is soft over its own travel and
// then hands over to the structure around it.
void RorSolver::apply_bound_law(const RorBeam &beam, float extension, float closing_speed, float &spring,
                                float &damping) const {
    switch (beam.bound) {
        case BeamBound::NORMAL:
            return;
        case BeamBound::SHOCK1: {
            // How far past a bound the beam is, in metres. Not normalised, so the handover
            // to the structural rates gets firmer the further it is pushed — which is what
            // makes a bump stop feel like one instead of a wall.
            float overshoot = 0.0f;
            if (extension > beam.long_bound * beam.rest_length) {
                overshoot = extension - beam.long_bound * beam.rest_length;
            } else if (extension < -beam.short_bound * beam.rest_length) {
                overshoot = -extension - beam.short_bound * beam.rest_length;
            }
            if (overshoot != 0.0f) {
                spring += (beam.bound_spring - spring) * overshoot;
                damping += (beam.bound_damp - damping) * overshoot;
            }
            return;
        }
        case BeamBound::ROPE:
            // Slack: a rope pushes nothing.
            if (extension < 0.0f) {
                spring = 0.0f;
                damping *= 0.1f;
            }
            return;
        case BeamBound::SUPPORT:
            // Lifted away: a support beam pulls nothing.
            if (extension > 0.0f) {
                spring = 0.0f;
                damping *= 0.1f;
            }
            return;
        case BeamBound::SHOCK2:
        case BeamBound::SHOCK3: {
            if (beam.shock < 0 || beam.shock >= static_cast<int>(m_shocks.size())) {
                return;
            }
            const RorShockBeam travel{beam.rest_length, beam.short_bound, beam.long_bound, beam.bound_spring,
                                      beam.bound_damp};
            const RorShock &shock = m_shocks[static_cast<size_t>(beam.shock)];
            if (beam.bound == BeamBound::SHOCK2) {
                shock2_law(shock, travel, extension, closing_speed, spring, damping);
            } else {
                shock3_law(shock, travel, extension, closing_speed, spring, damping);
            }
            return;
        }
    }
}

namespace {
// A `shocks2` or `shocks3` row's rates, in the row's order, as upstream's spawner stores them.
RorShock shock_from(BeamBound kind, const PackedFloat32Array &rates, bool soft_bump) {
    RorShock shock;
    auto at = [&rates](int i) { return i < rates.size() ? rates[i] : 0.0f; };
    if (kind == BeamBound::SHOCK2) {
        shock.spring_in = at(0);
        shock.damp_in = at(1);
        shock.sprog_in = at(2);
        shock.dprog_in = at(3);
        shock.spring_out = at(4);
        shock.damp_out = at(5);
        shock.sprog_out = at(6);
        shock.dprog_out = at(7);
        shock.soft_bump = soft_bump;
    } else {
        shock.spring_in = at(0);
        shock.damp_in = at(1);
        shock.dslow_in = at(2);
        shock.split_in = at(3);
        shock.dfast_in = at(4);
        shock.spring_out = at(5);
        shock.damp_out = at(6);
        shock.dslow_out = at(7);
        shock.split_out = at(8);
        shock.dfast_out = at(9);
    }
    return shock;
}
} // namespace

void RorSolver::set_beam_shock(int beam, const PackedFloat32Array &rates, bool soft_bump) {
    sync();
    if (beam < 0 || beam >= static_cast<int>(m_beams.size())) {
        return;
    }
    RorBeam &target = m_beams[static_cast<size_t>(beam)];
    if (target.bound != BeamBound::SHOCK2 && target.bound != BeamBound::SHOCK3) {
        return;
    }
    const RorShock shock = shock_from(target.bound, rates, soft_bump);
    if (target.shock < 0) {
        target.shock = static_cast<int>(m_shocks.size());
        m_shocks.push_back(shock);
    } else {
        m_shocks[static_cast<size_t>(target.shock)] = shock;
    }
}

float RorSolver::get_beam_stress(int beam) const {
    sync();
    if (beam < 0 || beam >= static_cast<int>(m_beams.size())) {
        return 0.0f;
    }
    return m_beams[static_cast<size_t>(beam)].stress;
}

Vector2 RorSolver::shock_law_probe(int kind, const PackedFloat32Array &rates, bool soft_bump,
                                   const PackedFloat32Array &beam, float extension, float v) const {
    const BeamBound bound = static_cast<BeamBound>(kind);
    if (bound != BeamBound::SHOCK2 && bound != BeamBound::SHOCK3) {
        return Vector2();
    }
    auto at = [&beam](int i) { return i < beam.size() ? beam[i] : 0.0f; };
    const RorShockBeam travel{at(0), at(1), at(2), at(3), at(4)};
    float k = at(5);
    float d = at(6);
    const RorShock shock = shock_from(bound, rates, soft_bump);
    if (bound == BeamBound::SHOCK2) {
        shock2_law(shock, travel, extension, v, k, d);
    } else {
        shock3_law(shock, travel, extension, v, k, d);
    }
    return Vector2(k, d);
}

} // namespace rorgd
