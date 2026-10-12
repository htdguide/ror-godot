#include "ror_commands.h"

#include <algorithm>
#include <cmath>

namespace rorgd {

void RorCommands::add(int beam, int contract_key, int extend_key, float shorten_rate,
                      float lengthen_rate, float max_contraction, float max_extension,
                      bool force_restricted, bool auto_center, bool one_press,
                      bool one_press_center, float engine_coupling, bool needs_engine) {
    // Upstream's `ProcessCommand`: the middle of the travel, and one state the two directions share.
    const float center = max_extension > max_contraction
            ? (max_extension - max_contraction) / 2.0f + max_contraction
            : (max_contraction - max_extension) / 2.0f + max_extension;
    m_states.emplace_back();
    RorCommandBeam entry;
    entry.beam = beam;
    entry.force_restricted = force_restricted;
    entry.auto_center = auto_center;
    entry.needs_engine = needs_engine;
    entry.one_press = one_press;
    entry.one_press_center = one_press_center;
    entry.engine_coupling = engine_coupling;
    entry.center = center;
    entry.state = static_cast<int>(m_states.size()) - 1;
    if (contract_key >= 1 && contract_key <= MAX_COMMAND_KEYS) {
        entry.contraction = true;
        entry.speed = shorten_rate;
        entry.boundary = max_contraction;
        m_keys[static_cast<size_t>(contract_key)].beams.push_back(entry);
    }
    if (extend_key >= 1 && extend_key <= MAX_COMMAND_KEYS) {
        entry.contraction = false;
        entry.speed = lengthen_rate;
        entry.boundary = max_extension;
        m_keys[static_cast<size_t>(extend_key)].beams.push_back(entry);
    }
    ++m_count;
}

void RorCommands::set_key(int key, float value) {
    if (key >= 1 && key <= MAX_COMMAND_KEYS) {
        m_keys[static_cast<size_t>(key)].player_input = std::clamp(value, 0.0f, 1.0f);
    }
}

void RorCommands::set_key_inertia(int key, float start_delay, float stop_delay, const RorSpline *start,
                                  const RorSpline *stop) {
    if (key >= 1 && key <= MAX_COMMAND_KEYS) {
        m_keys[static_cast<size_t>(key)].inertia.configure(start_delay, stop_delay, start, stop);
    }
}

void RorCommands::reset() {
    for (RorCommandKey &key : m_keys) {
        key.player_input = 0.0f;
        key.trigger_input = 0.0f;
        key.value = 0.0f;
    }
    for (RorCommandState &state : m_states) {
        state.auto_moving_mode = 0;
    }
}

RorCommandKey &RorCommands::key(int index) {
    if (index >= 0 && index <= MAX_COMMAND_KEYS) {
        return m_keys[static_cast<size_t>(index)];
    }
    if (index < 0) {
        return m_virtual_keys[index];
    }
    return m_dummy_key;
}

void RorCommands::read_keys() {
    for (int i = 1; i <= MAX_COMMAND_KEYS; ++i) {
        RorCommandKey &key = m_keys[static_cast<size_t>(i)];
        key.value = std::max(key.player_input, key.trigger_input);
        key.trigger_input = 0.0f;
    }
}

bool RorCommands::key_has_inertia(int key) const {
    return key >= 1 && key <= MAX_COMMAND_KEYS && m_keys[static_cast<size_t>(key)].inertia.active();
}

RorCommands::Power RorCommands::update(BeamArray &beams, float dt, bool engine_running,
                                       bool hydraulics_ready, float crank_factor) {
    Power power;
    if (m_count == 0) {
        return power;
    }
    for (RorCommandState &state : m_states) {
        state.auto_move_lock = false;
    }
    read_keys();
    for (int i = 1; i <= MAX_COMMAND_KEYS; ++i) {
        RorCommandKey &key = m_keys[static_cast<size_t>(i)];
        if (key.value >= 0.5f) {
            for (const RorCommandBeam &entry : key.beams) {
                RorCommandState &state = m_states[static_cast<size_t>(entry.state)];
                state.auto_move_lock = true;
                if (entry.auto_center) {
                    state.auto_moving_mode = 0;
                }
            }
        }
    }
    // Upstream lowers `crankfactor` itself for a force-restricted ram, so every ram after it in
    // the loop is restricted too; kept, because it is what the vehicles were tuned against.
    float crank = crank_factor;
    for (int i = 1; i <= MAX_COMMAND_KEYS; ++i) {
        RorCommandKey &key = m_keys[static_cast<size_t>(i)];
        bool request = false;
        for (RorCommandBeam &entry : key.beams) {
            if (entry.beam < 0 || static_cast<size_t>(entry.beam) >= beams.size()) {
                continue;
            }
            RorBeam &beam = beams[static_cast<size_t>(entry.beam)];
            RorCommandState &state = m_states[static_cast<size_t>(entry.state)];
            const int dir = entry.contraction ? -1 : 1;
            if (entry.force_restricted) {
                crank = std::min(crank, 1.0f);
            }
            float v = key.value;
            if (entry.auto_center && !state.auto_move_lock) {
                if (beam.reference_length == 0.0f || beam.rest_length == 0.0f) {
                    continue;
                }
                const float current = beam.rest_length / beam.reference_length;
                if (std::fabs(current - entry.center) < 0.0001f) {
                    state.auto_moving_mode = 0;
                } else {
                    const int mode = state.auto_moving_mode;
                    state.auto_moving_mode = current > entry.center ? -1 : 1;
                    // Avoid overshooting: a direction change means the middle was crossed.
                    if (mode != 0 && mode != state.auto_moving_mode) {
                        beam.rest_length = entry.center * beam.reference_length;
                        state.auto_moving_mode = 0;
                    }
                }
            }
            if (beam.reference_length == 0.0f || beam.rest_length == 0.0f) {
                continue;
            }
            const float clen = beam.rest_length / beam.reference_length;
            const bool can_move = (dir > 0 && clen < entry.boundary) || (dir < 0 && clen > entry.boundary);
            if (!can_move) {
                if ((entry.one_press || entry.one_press_center) && dir * state.auto_moving_mode > 0) {
                    state.auto_moving_mode = 0;
                }
                continue;
            }
            const float before = beam.rest_length;
            if (entry.one_press_center) {
                if (dir * state.auto_moving_mode > 0 && dir * clen > dir * entry.center &&
                    !state.pressed_center_mode) {
                    state.pressed_center_mode = true;
                    state.auto_moving_mode = 0;
                } else if (dir * state.auto_moving_mode < 0 && dir * clen > dir * entry.center &&
                           state.pressed_center_mode) {
                    state.pressed_center_mode = false;
                }
            }
            if (entry.one_press || entry.one_press_center) {
                // Press, release, press, release: the four phases of a one-press ram.
                const bool held = v > 0.5f;
                if (dir * state.auto_moving_mode <= 0 && held) {
                    state.auto_moving_mode = dir * 1;
                } else if (state.auto_moving_mode == dir * 1 && !held) {
                    state.auto_moving_mode = dir * 2;
                } else if (state.auto_moving_mode == dir * 2 && held) {
                    state.auto_moving_mode = dir * 3;
                } else if (state.auto_moving_mode == dir * 3 && !held) {
                    state.auto_moving_mode = 0;
                }
            }
            // Upstream runs the key's inertia once per ram on the key, so a key driving two rams
            // ramps twice as fast; kept, because it is what the vehicles were tuned against.
            v = key.inertia.calc(v, dt);
            if (dir * state.auto_moving_mode > 0) {
                v = 1.0f;
            }
            if (entry.needs_engine && (!engine_running || !hydraulics_ready)) {
                continue;
            }
            if (v > 0.0f && entry.engine_coupling > 0.0f) {
                request = true;
            }
            const float cf = entry.engine_coupling > 0.0f ? crank : 1.0f;
            beam.rest_length *= 1.0f + static_cast<float>(dir) * entry.speed * v * cf * dt / beam.rest_length;
            if (request) {
                power.work += std::fabs(beam.stress) * std::fabs(before - beam.rest_length) *
                              entry.engine_coupling;
            }
        }
        if (request) {
            power.requested = true;
        }
    }
    return power;
}

} // namespace rorgd
