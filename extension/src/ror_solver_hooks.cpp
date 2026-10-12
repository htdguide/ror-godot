#include "ror_solver.h"

#include "ror_approx.h"

#include <godot_cpp/core/class_db.hpp>

#include <algorithm>
#include <cmath>

// Upstream's hooks (`Actor::hookToggle`, `Actor::CalcHooks`): a node with option `h` reaches for
// the nearest node in range, on any vehicle in the world or, with `selflock`, its own, and reels
// its rope beam in until it is locked.

using namespace godot;

namespace rorgd {

namespace {
Vector3 world_of(const RorSolver &, const RorFrame &frame, const Vector3 &local) {
    return Vector3(static_cast<float>(frame.world_x(local.x)), local.y, static_cast<float>(frame.world_z(local.z)));
}
} // namespace

int RorSolver::add_hook(int node, float spring, float damp, float strength, float deform) {
    sync();
    if (node < 0 || node >= static_cast<int>(m_nodes.size()) || m_nodes.size() < 2) {
        return -1;
    }
    // Upstream links the hook node to node 0, or node 1 when the hook is node 0, and leaves the
    // beam disabled until the hook locks.
    const int other = node == 0 ? 1 : 0;
    const int beam = add_beam(node, other, 0.0f, spring, damp);
    set_beam_limits(beam, deform, strength, 0.0f, false);
    set_beam_bounds(beam, static_cast<int>(BeamBound::ROPE), 0.0f, 0.0f, 0.0f, 0.0f, 1.0f);
    m_beams[static_cast<size_t>(beam)].disabled = true;
    m_beams[static_cast<size_t>(beam)].rest_length = HOOK_RANGE;
    RorHook hook;
    hook.node = node;
    hook.beam = beam;
    m_hooks.push_back(hook);
    return static_cast<int>(m_hooks.size()) - 1;
}

void RorSolver::set_hook_options(int node, float lockrange, float speed_coef, float maxforce, int group,
                                 int lockgroup, float timer, float min_length, bool selflock, bool autolock,
                                 bool nodisable, bool norope) {
    sync();
    for (RorHook &hook : m_hooks) {
        if (hook.node != node) {
            continue;
        }
        hook.lockrange = lockrange;
        hook.lockspeed = speed_coef * HOOK_SPEED;
        hook.maxforce = maxforce;
        hook.group = group;
        hook.lockgroup = lockgroup;
        hook.timer = 0.0f;
        hook.timer_preset = timer;
        hook.min_length = min_length;
        hook.selflock = selflock;
        hook.nodisable = nodisable;
        if (autolock) {
            hook.autolock = true;
            if (hook.group == -1) {
                hook.group = -2;
            }
        }
        if (norope) {
            set_beam_bounds(hook.beam, static_cast<int>(BeamBound::NORMAL), 0.0f, 0.0f, 0.0f, 0.0f, 1.0f);
        }
        return;
    }
}

void RorSolver::set_node_lockgroup(int node, int group) {
    sync();
    if (node >= 0 && node < static_cast<int>(m_nodes.size())) {
        m_nodes[static_cast<size_t>(node)].lockgroup = group;
    }
}

void RorSolver::toggle_hooks(int mode, int group) {
    sync();
    toggle_hooks_among({this}, mode, group);
}

// Upstream's `hookToggle`, over `actors` in order, each a vehicle the hooks may reach.
// With `only_to`, a reset lets go only of the hooks locked to that vehicle, upstream's
// `forceunlock_filter`.
void RorSolver::toggle_hooks_among(const std::vector<RorSolver *> &actors, int mode, int group, RorSolver *only_to) {
    for (RorHook &hook : m_hooks) {
        if (mode == RorHook::RESET && only_to != nullptr && hook.state != RorHook::State::UNLOCKED &&
            hook.target != only_to) {
            continue;
        }
        if (mode == RorHook::TOGGLE && group == -1 && hook.group <= -2) {
            continue;
        }
        if (mode == RorHook::LOCK && group == -2 && (hook.group >= -1 || !hook.autolock)) {
            continue;
        }
        if (mode == RorHook::UNLOCK && group == -2 && (hook.group >= -1 || !hook.autolock)) {
            continue;
        }
        if ((mode == RorHook::LOCK || mode == RorHook::UNLOCK) && group <= -3 && hook.group != group) {
            continue;
        }
        if ((mode == RorHook::LOCK || mode == RorHook::UNLOCK) && group >= -1) {
            continue;
        }
        if (mode == RorHook::LOCK && hook.timer > 0.0f) {
            continue;
        }
        RorBeam &beam = m_beams[static_cast<size_t>(hook.beam)];
        if (mode != RorHook::UNLOCK && mode != RorHook::RESET && hook.state == RorHook::State::UNLOCKED) {
            const Vector3 from = world_of(*this, m_frame, m_nodes[static_cast<size_t>(hook.node)].position);
            // Upstream keeps the best distance across vehicles but takes the beam's far end from
            // the first vehicle it finds one on: a later, nearer one only changes the bookkeeping.
            float distance = 100000000.0f;
            for (RorSolver *actor : actors) {
                if (actor == this && !hook.selflock) {
                    continue;
                }
                int nearest = -1;
                for (size_t i = 0; i < actor->m_nodes.size(); ++i) {
                    const RorNode &node = actor->m_nodes[i];
                    if (node.lockgroup == LOCKGROUP_NOLOCK) {
                        continue;
                    }
                    if (actor == this && static_cast<int>(i) == hook.node) {
                        continue;
                    }
                    if (hook.lockgroup != -1 && hook.lockgroup != node.lockgroup) {
                        continue;
                    }
                    const float gap = static_cast<float>((from - world_of(*actor, actor->m_frame, node.position)).length());
                    if (gap < hook.lockrange && distance >= gap) {
                        distance = gap;
                        nearest = static_cast<int>(i);
                    }
                }
                if (nearest < 0) {
                    continue;
                }
                hook.lock_node = nearest;
                hook.target = actor == this ? nullptr : actor;
                hook.state = RorHook::State::PRELOCK;
                if (beam.disabled) {
                    hook.beam_target = hook.target;
                    hook.beam_node = nearest;
                    beam.inter_actor = hook.target != nullptr;
                    if (!beam.inter_actor) {
                        beam.b = nearest;
                    }
                    beam.rest_length = static_cast<float>(
                            (from - world_of(*actor, actor->m_frame, actor->m_nodes[static_cast<size_t>(nearest)].position)).length());
                    beam.disabled = false;
                }
            }
        } else if ((hook.state == RorHook::State::LOCKED || hook.state == RorHook::State::PRELOCK) &&
                   (mode != RorHook::LOCK || !beam.inter_actor)) {
            hook.state = RorHook::State::UNLOCKED;
            if (hook.group <= -2) {
                hook.timer = mode == RorHook::RESET ? 0.0f : hook.timer_preset;
            }
            hook.lock_node = -1;
            hook.target = nullptr;
            hook.beam_target = nullptr;
            hook.beam_node = -1;
            const int home = hook.node == 0 ? 1 : 0;
            beam.b = home;
            beam.inter_actor = false;
            beam.rest_length = static_cast<float>(
                    (m_nodes[static_cast<size_t>(home)].position - m_nodes[static_cast<size_t>(hook.node)].position).length());
            beam.disabled = true;
        }
    }
}

// Upstream's `CalcHooks`, at the start of a substep.
void RorSolver::calc_hooks(float dt) {
    for (RorHook &hook : m_hooks) {
        hook.timer = std::max(0.0f, hook.timer - dt);
        if (hook.lock_node < 0 || hook.state != RorHook::State::PRELOCK) {
            continue;
        }
        RorBeam &beam = m_beams[static_cast<size_t>(hook.beam)];
        if (beam.rest_length < hook.min_length) {
            hook.state = RorHook::State::LOCKED;
        } else if (beam.rest_length > hook.lockspeed && std::fabs(beam.stress) < hook.maxforce) {
            beam.rest_length = beam.rest_length - hook.lockspeed;
        } else if (std::fabs(beam.stress) < hook.maxforce) {
            beam.rest_length = 0.001f;
            hook.state = RorHook::State::LOCKED;
        } else if (hook.nodisable) {
            hook.state = RorHook::State::LOCKED;
        }
        // Otherwise upstream asks for an unlock with group -1, which `hookToggle` skips for every
        // hook: the hook stays half-locked, holding where it got to.
    }
}

// One beam whose far end is node `far` of `other`, upstream's `CalcBeamsInterActor`: a rope
// unless the file said otherwise, a `BEAM_HYDRO` that never yields, applied to both vehicles.
void RorSolver::apply_link_beam(RorBeam &beam, RorSolver *other, int far) {
    RorNode &a = m_nodes[static_cast<size_t>(beam.a)];
    RorNode &b = other->m_nodes[static_cast<size_t>(far)];
    const Vector3 offset(static_cast<float>(other->m_frame.x - m_frame.x), 0.0f,
                         static_cast<float>(other->m_frame.z - m_frame.z));
    const Vector3 dis = a.position - (b.position + offset);
    const float squared = static_cast<float>(dis.length_squared());
    if (squared <= 0.0f) {
        return;
    }
    const float inverted = fast_invSqrt(squared);
    const float length = squared * inverted;
    const float extension = length - beam.rest_length;
    float k = beam.spring;
    float d = beam.damping;
    if (beam.bound == BeamBound::ROPE && extension < 0.0f) {
        k = 0.0f;
        d *= 0.1f;
    }
    const Vector3 v = a.velocity - b.velocity;
    float stress = -k * extension - d * static_cast<float>(v.dot(dis)) * inverted;
    beam.stress = stress;
    // Upstream's break test; its cab-node exemption is left out, as a link counts no cab node.
    if (std::fabs(stress) > beam.minmax_stress && std::fabs(stress) > beam.strength) {
        beam.broken = true;
        beam.disabled = true;
        stress = 0.0f;
    }
    const Vector3 force = dis * (stress * inverted);
    a.forces += force;
    b.forces -= force;
}

// Every hook and tie beam whose far end is on another member of `island`.
void RorSolver::apply_inter_actor_links(const std::vector<RorSolver *> &island) {
    auto in_island = [&island](RorSolver *other) {
        return other != nullptr && std::find(island.begin(), island.end(), other) != island.end();
    };
    for (RorHook &hook : m_hooks) {
        RorBeam &beam = m_beams[static_cast<size_t>(hook.beam)];
        if (!beam.disabled && beam.inter_actor && !beam.broken && in_island(hook.beam_target)) {
            apply_link_beam(beam, hook.beam_target, hook.beam_node);
        }
    }
    for (RorTie &tie : m_ties) {
        RorBeam &beam = m_beams[static_cast<size_t>(tie.beam)];
        if (!beam.disabled && beam.inter_actor && !beam.broken && in_island(tie.target)) {
            apply_link_beam(beam, tie.target, tie.target->m_ropables[static_cast<size_t>(tie.ropable)].node);
        }
    }
}

int RorSolver::hook_count() {
    sync();
    return static_cast<int>(m_hooks.size());
}

String RorSolver::hook_state(int index) {
    sync();
    if (index < 0 || index >= static_cast<int>(m_hooks.size())) {
        return String();
    }
    switch (m_hooks[static_cast<size_t>(index)].state) {
        case RorHook::State::UNLOCKED: return "unlocked";
        case RorHook::State::PRELOCK: return "prelock";
        case RorHook::State::LOCKED: return "locked";
    }
    return String();
}

int RorSolver::hook_lock_node(int index) {
    sync();
    return index >= 0 && index < static_cast<int>(m_hooks.size()) ? m_hooks[static_cast<size_t>(index)].lock_node : -1;
}

bool RorSolver::hook_locked_to_self(int index) {
    sync();
    return index >= 0 && index < static_cast<int>(m_hooks.size()) &&
           m_hooks[static_cast<size_t>(index)].state != RorHook::State::UNLOCKED &&
           m_hooks[static_cast<size_t>(index)].target == nullptr;
}

float RorSolver::hook_length(int index) {
    sync();
    if (index < 0 || index >= static_cast<int>(m_hooks.size())) {
        return 0.0f;
    }
    return m_beams[static_cast<size_t>(m_hooks[static_cast<size_t>(index)].beam)].rest_length;
}

void RorSolver::bind_hook_methods() {
    ClassDB::bind_method(D_METHOD("add_hook", "node", "spring", "damp", "strength", "deform"), &RorSolver::add_hook);
    ClassDB::bind_method(D_METHOD("set_hook_options", "node", "lockrange", "speed_coef", "maxforce", "group",
                                  "lockgroup", "timer", "min_length", "selflock", "autolock", "nodisable", "norope"),
                         &RorSolver::set_hook_options);
    ClassDB::bind_method(D_METHOD("set_node_lockgroup", "node", "group"), &RorSolver::set_node_lockgroup);
    ClassDB::bind_method(D_METHOD("toggle_hooks", "mode", "group"), &RorSolver::toggle_hooks);
    ClassDB::bind_method(D_METHOD("hook_count"), &RorSolver::hook_count);
    ClassDB::bind_method(D_METHOD("hook_state", "index"), &RorSolver::hook_state);
    ClassDB::bind_method(D_METHOD("hook_lock_node", "index"), &RorSolver::hook_lock_node);
    ClassDB::bind_method(D_METHOD("hook_locked_to_self", "index"), &RorSolver::hook_locked_to_self);
    ClassDB::bind_method(D_METHOD("hook_length", "index"), &RorSolver::hook_length);
}

} // namespace rorgd
