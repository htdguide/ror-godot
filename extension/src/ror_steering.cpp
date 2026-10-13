#include "ror_steering.h"

#include <algorithm>
#include <cmath>

namespace rorgd {

void RorSteering::add_hydro(int beam_index, float factor, uint32_t flags) {
    Hydro hydro;
    hydro.beam = beam_index;
    hydro.factor = factor;
    hydro.flags = flags;
    m_hydros.push_back(hydro);
}

int RorSteering::add_animator(int beam_index, float factor, uint32_t flags, float param) {
    Hydro hydro;
    hydro.beam = beam_index;
    hydro.factor = factor;
    hydro.anim_flags = flags;
    hydro.anim_param = param;
    m_hydros.push_back(hydro);
    m_animators += 1;
    return count() - 1;
}

void RorSteering::set_command(float command) {
    m_command = std::fmax(-1.0f, std::fmin(1.0f, command));
}

void RorSteering::set_surface_commands(float aileron, float rudder, float elevator) {
    m_surface_command[0] = aileron;
    m_surface_command[1] = rudder;
    m_surface_command[2] = elevator;
}

void RorSteering::update(float dt, float road_speed, BeamArray &beams, const RorAnimatorInputs *inputs) {
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
    // Upstream's aileron, rudder and elevator states, in its double arithmetic.
    for (int k = 0; k < 3; ++k) {
        float &surface = m_surface_state[k];
        const float command = m_surface_command[k];
        if (surface != 0 || command != 0) {
            if (command != 0) {
                if (surface > command) {
                    surface -= dt * 4.0;
                } else {
                    surface += dt * 4.0;
                }
            }
            if (surface > dt) {
                surface -= dt;
            } else if (surface < -dt) {
                surface += dt;
            } else {
                surface = 0;
            }
        }
    }
    for (Hydro &hydro : m_hydros) {
        if (hydro.beam < 0 || hydro.beam >= static_cast<int>(beams.size())) {
            continue;
        }
        RorBeam &beam = beams[static_cast<size_t>(hydro.beam)];
        if (hydro.anim_flags != 0) {
            // Upstream's `CalcHydros` for an animator: no hydro flags, so its state is what
            // `CalcAnimators` makes of nothing, averaged over what it read, through its inertia.
            if (inputs == nullptr) {
                continue;
            }
            float cstate = 0.0f;
            int div = 0;
            calc_animator(hydro.anim_flags, hydro.anim_param, *inputs, m_memory, cstate, div);
            if (div) {
                cstate /= (float)div;
                cstate = hydro.inertia.calc(cstate, dt);
                float factor = 1.0 - cstate * hydro.factor;
                if (factor < 1.0f - beam.short_bound) {
                    factor = 1.0f - beam.short_bound;
                }
                if (factor > 1.0f + beam.long_bound) {
                    factor = 1.0f + beam.long_bound;
                }
                beam.rest_length = beam.reference_length * factor;
            }
            continue;
        }
        // Upstream's compound hydro: what its flags follow, clamped, averaged, through its inertia.
        float cstate = 0.0f;
        int div = 0;
        const uint32_t f = hydro.flags;
        if (f & HYDRO_SPEED) {
            if (road_speed < 12.0f) {
                cstate += m_state * (12.0f - road_speed) / 12.0f;
            }
            div++;
        }
        const float sources[7] = {m_state, m_surface_state[0], m_surface_state[1], m_surface_state[2],
                -m_surface_state[0], -m_surface_state[1], -m_surface_state[2]};
        for (int k = 0; k < 7; ++k) {
            if (f & (HYDRO_DIR << k)) {
                cstate += sources[k];
                div++;
            }
        }
        if (cstate > 1.0) {
            cstate = 1.0;
        }
        if (cstate < -1.0) {
            cstate = -1.0;
        }
        if (div) {
            cstate /= (float)div;
            cstate = hydro.inertia.calc(cstate, dt);
            float factor = 1.0 - cstate * hydro.factor;
            beam.rest_length = beam.reference_length * factor;
        }
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
    m_surface_state[0] = m_surface_state[1] = m_surface_state[2] = 0.0f;
    // The animators' shared memory (previous crank, gear, shift timer) is not reset upstream.
    for (Hydro &hydro : m_hydros) {
        hydro.inertia.reset();
    }
}

} // namespace rorgd
