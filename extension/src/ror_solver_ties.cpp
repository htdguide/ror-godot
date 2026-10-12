#include "ror_solver.h"

#include <godot_cpp/core/class_db.hpp>

#include <cmath>

// Upstream's ties (`Actor::tieToggle`, `Actor::CalcTies`) and the ropables they take: a tie
// reaches up to its length for the nearest free ropable on any vehicle of the world, its own too
// unless it says `s`, and shortens until it is tight.

using namespace godot;

namespace rorgd {

namespace {
Vector3 world_of(const RorFrame &frame, const Vector3 &local) {
    return Vector3(static_cast<float>(frame.world_x(local.x)), local.y, static_cast<float>(frame.world_z(local.z)));
}
} // namespace

int RorSolver::add_tie(int root, float reach, float rate, float min_length, float max_stress, int group,
                       bool no_self_lock, float spring, float damp, float strength, float deform) {
    sync();
    if (root < 0 || root >= static_cast<int>(m_nodes.size()) || m_nodes.size() < 2) {
        return -1;
    }
    // Upstream's `ProcessTie`: root to node 0 (node 1 if the root is 0), as long as it can reach,
    // a rope, disabled until tied.
    const int beam = add_beam(root, root == 0 ? 1 : 0, reach, spring, damp);
    set_beam_limits(beam, deform, strength, 0.0f, false);
    set_beam_bounds(beam, static_cast<int>(BeamBound::ROPE), 0.0f, 0.0f, 0.0f, 0.0f, 1.0f);
    m_beams[static_cast<size_t>(beam)].disabled = true;
    RorTie tie;
    tie.beam = beam;
    tie.group = group;
    tie.contract_speed = rate;
    tie.max_stress = max_stress;
    tie.min_length = min_length;
    tie.no_self_lock = no_self_lock;
    m_ties.push_back(tie);
    return static_cast<int>(m_ties.size()) - 1;
}

int RorSolver::add_ropable(int node, int group, bool multilock) {
    sync();
    if (node < 0 || node >= static_cast<int>(m_nodes.size())) {
        return -1;
    }
    RorRopable ropable;
    ropable.node = node;
    ropable.group = group;
    ropable.multilock = multilock;
    m_ropables.push_back(ropable);
    return static_cast<int>(m_ropables.size()) - 1;
}

void RorSolver::toggle_ties(int group) {
    sync();
    toggle_ties_among({this}, group, false);
}

void RorSolver::untie(RorTie &tie) {
    RorSolver *owner = tie.target != nullptr ? tie.target : this;
    if (tie.ropable >= 0) {
        owner->m_ropables[static_cast<size_t>(tie.ropable)].attached_ties -= 1;
    }
    tie.tied = false;
    tie.tying = false;
    tie.target = nullptr;
    tie.ropable = -1;
    RorBeam &beam = m_beams[static_cast<size_t>(tie.beam)];
    beam.b = beam.a == 0 ? 1 : 0;
    beam.inter_actor = false;
    beam.disabled = true;
}

// Upstream's `tieToggle`: if any tie of the group is tied, every one of them lets go; if none was,
// a toggle ties each to the nearest free ropable within its reach.
void RorSolver::toggle_ties_among(const std::vector<RorSolver *> &actors, int group, bool reset) {
    bool tied_any = false;
    for (RorTie &tie : m_ties) {
        if (group != -1 && tie.group != -1 && tie.group != group) {
            continue;
        }
        if (tie.tied) {
            tied_any = !m_beams[static_cast<size_t>(tie.beam)].disabled;
            untie(tie);
        }
    }
    if (tied_any || reset) {
        return;
    }
    for (RorTie &tie : m_ties) {
        if (group != -1 && tie.group != -1 && tie.group != group) {
            continue;
        }
        if (tie.tied) {
            continue;
        }
        RorBeam &beam = m_beams[static_cast<size_t>(tie.beam)];
        const Vector3 root = world_of(m_frame, m_nodes[static_cast<size_t>(beam.a)].position);
        float best = beam.reference_length;
        RorSolver *found = nullptr;
        int found_ropable = -1;
        for (RorSolver *actor : actors) {
            if (actor == this && tie.no_self_lock) {
                continue;
            }
            for (size_t r = 0; r < actor->m_ropables.size(); ++r) {
                const RorRopable &ropable = actor->m_ropables[r];
                if (!ropable.multilock && ropable.attached_ties > 0) {
                    continue;
                }
                if (actor == this && ropable.node == beam.a) {
                    continue;
                }
                const float gap = static_cast<float>(
                        (root - world_of(actor->m_frame, actor->m_nodes[static_cast<size_t>(ropable.node)].position)).length());
                if (gap < best) {
                    best = gap;
                    found = actor;
                    found_ropable = static_cast<int>(r);
                }
            }
        }
        if (found == nullptr) {
            continue;
        }
        beam.disabled = false;
        tie.target = found == this ? nullptr : found;
        tie.ropable = found_ropable;
        beam.inter_actor = tie.target != nullptr;
        if (!beam.inter_actor) {
            beam.b = m_ropables[static_cast<size_t>(found_ropable)].node;
        }
        beam.stress = 0.0f;
        beam.rest_length = beam.reference_length;
        tie.tied = true;
        tie.tying = true;
        found->m_ropables[static_cast<size_t>(found_ropable)].attached_ties += 1;
    }
}

// Upstream's `CalcTies`, after the commands and before the beams.
void RorSolver::calc_ties(float dt) {
    for (RorTie &tie : m_ties) {
        if (!tie.tying) {
            continue;
        }
        RorBeam &beam = m_beams[static_cast<size_t>(tie.beam)];
        if (beam.reference_length == 0.0f || beam.rest_length == 0.0f) {
            continue;
        }
        const float share = beam.rest_length / beam.reference_length;
        if (share > tie.min_length) {
            beam.rest_length = static_cast<float>(beam.rest_length * (1.0 - tie.contract_speed * dt / beam.rest_length));
        } else {
            tie.tying = false;
        }
        if (std::fabs(beam.stress) > tie.max_stress) {
            tie.tying = false;
        }
    }
}

int RorSolver::tie_count() {
    sync();
    return static_cast<int>(m_ties.size());
}

String RorSolver::tie_state(int index) {
    sync();
    if (index < 0 || index >= static_cast<int>(m_ties.size())) {
        return String();
    }
    const RorTie &tie = m_ties[static_cast<size_t>(index)];
    return tie.tying ? "tying" : (tie.tied ? "tied" : "free");
}

float RorSolver::tie_length(int index) {
    sync();
    if (index < 0 || index >= static_cast<int>(m_ties.size())) {
        return 0.0f;
    }
    return m_beams[static_cast<size_t>(m_ties[static_cast<size_t>(index)].beam)].rest_length;
}

int RorSolver::tie_ropable(int index) {
    sync();
    return index >= 0 && index < static_cast<int>(m_ties.size()) ? m_ties[static_cast<size_t>(index)].ropable : -1;
}

bool RorSolver::tie_locked_to_self(int index) {
    sync();
    return index >= 0 && index < static_cast<int>(m_ties.size()) && m_ties[static_cast<size_t>(index)].tied &&
           m_ties[static_cast<size_t>(index)].target == nullptr;
}

void RorSolver::bind_tie_methods() {
    ClassDB::bind_method(D_METHOD("add_tie", "root", "reach", "rate", "min_length", "max_stress", "group", "no_self_lock",
                                  "spring", "damp", "strength", "deform"),
                         &RorSolver::add_tie);
    ClassDB::bind_method(D_METHOD("add_ropable", "node", "group", "multilock"), &RorSolver::add_ropable);
    ClassDB::bind_method(D_METHOD("toggle_ties", "group"), &RorSolver::toggle_ties);
    ClassDB::bind_method(D_METHOD("tie_count"), &RorSolver::tie_count);
    ClassDB::bind_method(D_METHOD("tie_state", "index"), &RorSolver::tie_state);
    ClassDB::bind_method(D_METHOD("tie_length", "index"), &RorSolver::tie_length);
    ClassDB::bind_method(D_METHOD("tie_ropable", "index"), &RorSolver::tie_ropable);
    ClassDB::bind_method(D_METHOD("tie_locked_to_self", "index"), &RorSolver::tie_locked_to_self);
}

} // namespace rorgd
