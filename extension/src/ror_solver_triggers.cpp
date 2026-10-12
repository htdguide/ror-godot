#include "ror_solver.h"

#include <godot_cpp/core/class_db.hpp>

#include <cmath>
#include <cstring>
#include <string>

// Upstream's triggers: `ActorSpawner::ProcessTrigger` builds each, and `Actor::CalcTriggers`, called
// from the beam pass, has it press command keys, block other triggers or keys, swap two keys,
// lock or unlock a hook group, or work the engine, as its beam leaves or re-enters its bounds.

using namespace godot;

namespace rorgd {

// Upstream's fixed `PHYSICS_DT`, which its trigger timers count in whatever the step.
constexpr float PHYSICS_DT = 0.0005f;

// Upstream's `ProcessTrigger`, its options a string of upstream's letters. -1 when upstream
// deactivates the row.
int RorSolver::add_trigger(int a, int b, float contraction_limit, float expansion_limit, int short_action,
                           int long_action, const String &options, float boundary_timer, int detacher_group) {
    sync();
    float sbound = contraction_limit;
    float lbound = expansion_limit;
    int flags = TRIGGER_FLAG_NORMAL | TRIGGER_FLAG_IS_TRIGGER;
    bool enabled = true;
    bool blocker = false;
    bool blocker_inverted = false;
    bool key_block = false;
    bool hook_toggle = false;
    bool engine = false;
    bool block_short = false;
    bool block_long = long_action == -1;
    const CharString letters = options.utf8();
    const auto has = [&letters](char c) { return std::strchr(letters.get_data(), c) != nullptr; };
    if (has('x')) {
        enabled = false;
    }
    if (has('B')) {
        flags |= TRIGGER_FLAG_BLOCKER;
        blocker = true;
    }
    if (has('b')) {
        key_block = true;
    }
    if (has('s')) {
        flags |= TRIGGER_FLAG_CMD_SWITCH;
    }
    if (has('c')) {
        sbound = std::fabs(sbound - 1);
        lbound = lbound - 1;
    }
    if (has('A')) {
        flags |= TRIGGER_FLAG_BLOCKER_A;
        blocker_inverted = true;
    }
    if (has('h')) {
        flags |= TRIGGER_FLAG_HOOK_UNLOCK;
        hook_toggle = true;
    }
    if (has('H')) {
        flags |= TRIGGER_FLAG_HOOK_LOCK;
        hook_toggle = true;
    }
    if (has('t')) {
        flags |= TRIGGER_FLAG_CONTINUOUS;
    }
    if (has('E')) {
        flags |= TRIGGER_FLAG_ENGINE;
        engine = true;
    }
    if (!blocker && !blocker_inverted && !hook_toggle && !engine) {
        if (short_action < 1 || short_action > MAX_COMMAND_KEYS) {
            return -1;
        }
    } else if (!hook_toggle && !engine) {
        if (short_action < 0 || long_action < 0) {
            return -1;
        }
    } else if (engine) {
        if (blocker || blocker_inverted || hook_toggle || (flags & TRIGGER_FLAG_CMD_SWITCH)) {
            return -1;
        }
    }
    if (a < 0 || b < 0 || a >= static_cast<int>(m_nodes.size()) || b >= static_cast<int>(m_nodes.size())) {
        return -1;
    }
    // A beam with no spring and no damping, as long as it was built: it measures and pushes nothing.
    const float length = static_cast<float>(m_nodes[static_cast<size_t>(a)].position.distance_to(
            m_nodes[static_cast<size_t>(b)].position));
    const int beam = add_beam(a, b, length, 0.0f, 0.0f);
    RorBeam &made = m_beams[static_cast<size_t>(beam)];
    made.bound = BeamBound::TRIGGER;
    made.short_bound = sbound;
    made.long_bound = lbound;
    made.deformable = false;
    made.detacher_group = detacher_group;

    RorTrigger trigger;
    trigger.beam = beam;
    if (!blocker && !blocker_inverted) {
        trigger.cmd_short = short_action;
        if (long_action != -1 || hook_toggle) {
            trigger.cmd_long = long_action;
        } else {
            flags |= TRIGGER_FLAG_CMD_BLOCKER;
        }
    } else {
        flags |= blocker_inverted ? TRIGGER_FLAG_BLOCKER_A : TRIGGER_FLAG_BLOCKER;
        trigger.cmd_short = short_action;
        trigger.cmd_long = long_action;
    }
    if (key_block && !blocker) {
        block_short = true;
        if (long_action != -1) {
            block_long = true;
        }
    }
    trigger.boundary_t = boundary_timer > 0 ? boundary_timer : 1.0f;
    trigger.flags = flags;
    trigger.enabled = enabled;
    made.shock = static_cast<int>(m_triggers.size());
    m_triggers.push_back(trigger);
    // Upstream sets both, short then long, whatever keys they name.
    m_commands.key(short_action).trigger_blocked = block_short;
    m_commands.key(long_action).trigger_blocked = block_long;
    return beam;
}

RorTrigger *RorSolver::trigger_of(int beam) {
    if (beam < 0 || beam >= static_cast<int>(m_beams.size())) {
        return nullptr;
    }
    const RorBeam &b = m_beams[static_cast<size_t>(beam)];
    if (b.bound != BeamBound::TRIGGER || b.shock < 0 || b.shock >= static_cast<int>(m_triggers.size())) {
        return nullptr;
    }
    return &m_triggers[static_cast<size_t>(b.shock)];
}

// Upstream's `engineTriggerHelper`; upstream's rpm trigger does nothing.
void RorSolver::engine_trigger(int type, float value) {
    if (m_trigger_log != nullptr) {
        const char *names[] = {"clutch", "brake", "acc", "rpm", "shift", "shift"};
        if (type == ENGINE_TRIGGER_CLUTCH || type == ENGINE_TRIGGER_ACC) {
            m_trigger_log->push_back(std::string(names[type]) + " " + std::to_string(value));
        } else if (type == ENGINE_TRIGGER_SHIFTUP || type == ENGINE_TRIGGER_SHIFTDOWN) {
            m_trigger_log->push_back(std::string("shift ") + (type == ENGINE_TRIGGER_SHIFTUP ? "1" : "-1"));
        }
    }
    switch (type) {
        case ENGINE_TRIGGER_CLUTCH:
            m_drivetrain.trigger_clutch(value);
            break;
        case ENGINE_TRIGGER_BRAKE:
            m_wheels.set_brake(value);
            break;
        case ENGINE_TRIGGER_ACC:
            m_drivetrain.trigger_acc(value);
            break;
        case ENGINE_TRIGGER_SHIFTUP:
            m_drivetrain.trigger_shift(1);
            break;
        case ENGINE_TRIGGER_SHIFTDOWN:
            m_drivetrain.trigger_shift(-1);
            break;
        default:
            break;
    }
}

// Upstream's `CalcTriggers` for beam `i`, its extension `diff`. `hooks` is upstream's
// `trigger_hooks`, true on the first substep of a frame: a hook trigger queues its request, which
// the world carries out before the next frame's step as upstream's message queue does.
void RorSolver::calc_trigger(int i, float diff, bool hooks) {
    RorTrigger *t = trigger_of(i);
    if (t == nullptr || !(t->flags & TRIGGER_FLAG_IS_TRIGGER) || !t->enabled) {
        return;
    }
    const RorBeam &beam = m_beams[static_cast<size_t>(i)];
    const float dt = PHYSICS_DT;
    const float L = beam.rest_length;
    if (diff > beam.long_bound * L || diff < -beam.short_bound * L) {
        t->switch_state -= dt;
        if (t->switch_state <= 0.0f) {
            t->switch_state = 0.0f;
        }
        if (t->flags & TRIGGER_FLAG_BLOCKER) {
            for (int s = i + 1; s <= i + t->cmd_short; s++) {
                if (RorTrigger *other = trigger_of(s); other && (other->flags & TRIGGER_FLAG_IS_TRIGGER)) {
                    other->enabled = false;
                }
            }
        } else if (t->flags & TRIGGER_FLAG_BLOCKER_A) {
            for (int s = i + 1; s <= i + t->cmd_long; s++) {
                if (RorTrigger *other = trigger_of(s); other && (other->flags & TRIGGER_FLAG_IS_TRIGGER)) {
                    other->enabled = true;
                }
            }
        } else if (t->flags & TRIGGER_FLAG_CMD_BLOCKER) {
            m_commands.key(t->cmd_short).trigger_blocked = false;
        } else if (t->flags & TRIGGER_FLAG_CMD_SWITCH) {
            if (!t->switch_state) {
                for (RorTrigger &other : m_triggers) {
                    const int short1 = other.cmd_short, short2 = t->cmd_short;
                    const int long1 = other.cmd_long, long2 = t->cmd_long;
                    if (((short1 == short2 && long1 == long2) || (short1 == long2 && long1 == short2)) && i != other.beam) {
                        const int swap = other.cmd_long;
                        other.cmd_long = other.cmd_short;
                        other.cmd_short = swap;
                        t->switch_state = t->boundary_t;
                    }
                }
            }
        } else if (diff > beam.long_bound * L) {
            if (t->flags & TRIGGER_FLAG_HOOK_UNLOCK) {
                if (hooks) {
                    m_trigger_hook_requests.push_back({RorHook::UNLOCK, t->cmd_long});
                }
            } else if (t->flags & TRIGGER_FLAG_HOOK_LOCK) {
                if (hooks) {
                    m_trigger_hook_requests.push_back({RorHook::LOCK, t->cmd_long});
                }
            } else if (t->flags & TRIGGER_FLAG_ENGINE) {
                engine_trigger(t->cmd_long, 1.0f);
            } else if (!m_commands.key(t->cmd_long).trigger_blocked) {
                if (t->flags & TRIGGER_FLAG_CONTINUOUS) {
                    m_commands.key(t->cmd_short).trigger_input = 1;
                } else {
                    m_commands.key(t->cmd_long).trigger_input = 1;
                }
            }
        } else {
            if (t->flags & TRIGGER_FLAG_HOOK_UNLOCK) {
                if (hooks) {
                    m_trigger_hook_requests.push_back({RorHook::UNLOCK, t->cmd_short});
                }
            } else if (t->flags & TRIGGER_FLAG_HOOK_LOCK) {
                if (hooks) {
                    m_trigger_hook_requests.push_back({RorHook::LOCK, t->cmd_short});
                }
            } else if (t->flags & TRIGGER_FLAG_ENGINE) {
                const bool value = !(t->flags & TRIGGER_FLAG_CONTINUOUS);
                engine_trigger(t->cmd_long, value);
            } else if (!m_commands.key(t->cmd_short).trigger_blocked) {
                if (t->flags & TRIGGER_FLAG_CONTINUOUS) {
                    m_commands.key(t->cmd_short).trigger_input = 0;
                } else {
                    m_commands.key(t->cmd_short).trigger_input = 1;
                }
            }
        }
        return;
    }
    if (t->flags & TRIGGER_FLAG_CONTINUOUS) {
        if (beam.long_bound - beam.short_bound > 0.0f) {
            const float share = diff / L;
            float value = (share - beam.short_bound) / (beam.long_bound - beam.short_bound);
            value = std::max(0.0f, value);
            value = std::min(value, 1.0f);
            if (t->flags & TRIGGER_FLAG_ENGINE) {
                engine_trigger(t->cmd_long, value);
            } else {
                m_commands.key(t->cmd_short).trigger_input = value;
                m_commands.key(t->cmd_long).trigger_input = value;
            }
        }
    } else if (t->flags & TRIGGER_FLAG_BLOCKER) {
        for (int s = i + 1; s <= i + t->cmd_long; s++) {
            if (RorTrigger *other = trigger_of(s); other && (other->flags & TRIGGER_FLAG_IS_TRIGGER)) {
                other->enabled = true;
            }
        }
    } else if (t->flags & TRIGGER_FLAG_BLOCKER_A) {
        for (int s = i + 1; s <= i + t->cmd_short; s++) {
            if (RorTrigger *other = trigger_of(s); other && (other->flags & TRIGGER_FLAG_IS_TRIGGER)) {
                other->enabled = false;
            }
        }
    } else if ((t->flags & TRIGGER_FLAG_CMD_SWITCH) && t->switch_state) {
        t->switch_state = 0.0f;
    } else if ((t->flags & TRIGGER_FLAG_CMD_BLOCKER) && !m_commands.key(t->cmd_short).trigger_blocked) {
        m_commands.key(t->cmd_short).trigger_blocked = true;
    }
}

// The hook requests triggers queued last frame, in order, over `actors`.
void RorSolver::run_trigger_hook_requests(const std::vector<RorSolver *> &actors) {
    const std::vector<std::pair<int, int>> requests = std::move(m_trigger_hook_requests);
    m_trigger_hook_requests.clear();
    for (const std::pair<int, int> &request : requests) {
        toggle_hooks_among(actors, request.first, request.second);
    }
}

int RorSolver::trigger_count() {
    sync();
    return static_cast<int>(m_triggers.size());
}

bool RorSolver::trigger_enabled(int beam) {
    sync();
    RorTrigger *t = trigger_of(beam);
    return t != nullptr && t->enabled;
}

Vector2i RorSolver::trigger_commands(int beam) {
    sync();
    RorTrigger *t = trigger_of(beam);
    return t == nullptr ? Vector2i(0, 0) : Vector2i(t->cmd_short, t->cmd_long);
}

float RorSolver::command_value(int key) {
    sync();
    return m_commands.key(key).value;
}

bool RorSolver::command_trigger_blocked(int key) {
    sync();
    return m_commands.key(key).trigger_blocked;
}

// `positions` the nodes; `rows` the triggers, each [a, b, contraction, expansion, short, long,
// options, timer]; `steps` each [hooks, positions]. Per step, after the beam pass and the command
// keys' read, a line in `the_trigger_is_upstreams`' format: every trigger's state, every key's value
// and block, the hook requests, the engine calls and the brake.
PackedStringArray RorSolver::trigger_probe(const PackedVector3Array &positions, const Array &rows, const Array &steps) {
    Ref<RorSolver> s;
    s.instantiate();
    for (int i = 0; i < positions.size(); ++i) {
        s->add_node(positions[i], 1.0f);
    }
    for (int r = 0; r < rows.size(); ++r) {
        const Array row = rows[r];
        s->add_trigger(row[0], row[1], row[2], row[3], row[4], row[5], row[6], row[7], 0);
    }
    std::vector<std::string> log;
    s->m_trigger_log = &log;
    PackedStringArray out;
    for (int step = 0; step < steps.size(); ++step) {
        const Array each = steps[step];
        const PackedVector3Array at = each[1];
        for (int i = 0; i < at.size(); ++i) {
            s->m_nodes[static_cast<size_t>(i)].position = at[i];
            s->m_nodes[static_cast<size_t>(i)].forces = Vector3();
        }
        log.clear();
        s->m_trigger_hook_requests.clear();
        s->m_first_substep = static_cast<bool>(each[0]);
        s->accumulate_beam_forces();
        s->m_commands.read_keys();
        std::string line = "T";
        for (const RorTrigger &t : s->m_triggers) {
            line += " " + std::to_string(t.enabled ? 1 : 0) + "," + std::to_string(t.cmd_short) + "," + std::to_string(t.cmd_long);
        }
        char buffer[64];
        line += " K";
        for (int i = 1; i <= MAX_COMMAND_KEYS; i++) {
            if (s->m_commands.key(i).value != 0.0f) {
                std::snprintf(buffer, sizeof buffer, " %d:%.9g", i, s->m_commands.key(i).value);
                line += buffer;
            }
        }
        line += " B";
        for (int i = -5; i <= MAX_COMMAND_KEYS; i++) {
            if (s->m_commands.key(i).trigger_blocked) {
                line += " " + std::to_string(i);
            }
        }
        line += " H";
        for (const std::pair<int, int> &r : s->m_trigger_hook_requests) {
            line += std::string(r.first == RorHook::LOCK ? " lock " : " unlock ") + std::to_string(r.second);
        }
        line += " E";
        for (const std::string &c : log) {
            line += " " + c;
        }
        std::snprintf(buffer, sizeof buffer, " R %.9g", s->m_wheels.brake());
        line += buffer;
        out.push_back(String(line.c_str()));
    }
    s->m_trigger_log = nullptr;
    return out;
}

void RorSolver::bind_trigger_methods() {
    ClassDB::bind_static_method("RorSolver", D_METHOD("trigger_probe", "positions", "rows", "steps"), &RorSolver::trigger_probe);
    ClassDB::bind_method(D_METHOD("add_trigger", "a", "b", "contraction_limit", "expansion_limit", "short_action",
                                  "long_action", "options", "boundary_timer", "detacher_group"),
                         &RorSolver::add_trigger);
    ClassDB::bind_method(D_METHOD("trigger_count"), &RorSolver::trigger_count);
    ClassDB::bind_method(D_METHOD("trigger_enabled", "beam"), &RorSolver::trigger_enabled);
    ClassDB::bind_method(D_METHOD("trigger_commands", "beam"), &RorSolver::trigger_commands);
    ClassDB::bind_method(D_METHOD("command_value", "key"), &RorSolver::command_value);
    ClassDB::bind_method(D_METHOD("command_trigger_blocked", "key"), &RorSolver::command_trigger_blocked);
}

} // namespace rorgd
