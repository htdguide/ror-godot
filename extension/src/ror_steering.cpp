#include "ror_steering.h"

#include <algorithm>
#include <cmath>

namespace rorgd {

void RorSteering::add_hydro(int beam_index, float factor) {
    Hydro hydro;
    hydro.beam = beam_index;
    hydro.factor = factor;
    m_hydros.push_back(hydro);
}

void RorSteering::set_command(float command) {
    m_command = std::fmax(-1.0f, std::fmin(1.0f, command));
}

void RorSteering::update(float dt, float road_speed, BeamArray &beams) {
    if (dt <= 0.0f) {
        return;
    }
    if (m_state != 0.0f || m_command != 0.0f) {
        if (m_command != 0.0f) {
            // Full lock takes about half a second standing still and longer the faster
            // the rig is going. The floor keeps it usable at speed rather than locking out.
            const float rate = std::fmax(1.2f, 30.0f / (10.0f + std::fabs(road_speed / 2.0f)));
            m_state += (m_state > m_command ? -dt : dt) * rate;
        }
        // Self-centring, at one unit of lock per second.
        if (m_state > dt) {
            m_state -= dt;
        } else if (m_state < -dt) {
            m_state += dt;
        } else {
            m_state = 0.0f;
        }
    }
    const float state = std::fmax(-1.0f, std::fmin(1.0f, m_state));
    for (Hydro &hydro : m_hydros) {
        if (hydro.beam < 0 || hydro.beam >= static_cast<int>(beams.size())) {
            continue;
        }
        RorBeam &beam = beams[static_cast<size_t>(hydro.beam)];
        const float own = hydro.inertia.calc(state, dt);
        beam.rest_length = beam.reference_length * (1.0f - own * hydro.factor);
    }
}

void RorSteering::set_hydro_inertia(int hydro, float start_delay, float stop_delay, const RorSpline *start,
                                    const RorSpline *stop) {
    if (hydro >= 0 && hydro < count()) {
        m_hydros[static_cast<size_t>(hydro)].inertia.configure(start_delay, stop_delay, start, stop);
    }
}

bool RorSteering::hydro_has_inertia(int hydro) const {
    return hydro >= 0 && hydro < count() && m_hydros[static_cast<size_t>(hydro)].inertia.active();
}

void RorSteering::reset() {
    m_state = 0.0f;
    for (Hydro &hydro : m_hydros) {
        hydro.inertia.reset();
    }
}

} // namespace rorgd
