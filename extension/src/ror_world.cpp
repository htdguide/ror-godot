#include "ror_world.h"

#include <godot_cpp/core/class_db.hpp>

#include <algorithm>
#include <condition_variable>
#include <memory>
#include <mutex>
#include <numeric>

using namespace godot;

namespace rorgd {

namespace {

// Upstream resets the triangles' skip rates when two actors' first nodes close faster than this,
// squared: 4 m/s.
constexpr float FAST_APPROACH_SQUARED = 16.0f;

size_t find_root(std::vector<size_t> &parent, size_t at) {
    while (parent[at] != at) {
        parent[at] = parent[parent[at]];
        at = parent[at];
    }
    return at;
}

// Opened once by the worker stepping an island; the other members' workers wait on it, so each
// member's own worker is busy exactly as long as the island is.
struct IslandLatch {
    std::mutex mutex;
    std::condition_variable opened;
    bool open = false;

    void release() {
        {
            std::lock_guard<std::mutex> lock(mutex);
            open = true;
        }
        opened.notify_all();
    }
    void wait() {
        std::unique_lock<std::mutex> lock(mutex);
        opened.wait(lock, [this] { return open; });
    }
};

} // namespace

void RorWorld::_bind_methods() {
    ClassDB::bind_method(D_METHOD("add_solver", "solver"), &RorWorld::add_solver);
    ClassDB::bind_method(D_METHOD("clear"), &RorWorld::clear);
    ClassDB::bind_method(D_METHOD("solver_count"), &RorWorld::solver_count);
    ClassDB::bind_method(D_METHOD("step", "dt", "substeps"), &RorWorld::step);
    ClassDB::bind_method(D_METHOD("set_parallel", "parallel"), &RorWorld::set_parallel);
    ClassDB::bind_method(D_METHOD("is_parallel"), &RorWorld::is_parallel);
    ClassDB::bind_method(D_METHOD("last_island_count"), &RorWorld::last_island_count);
    ClassDB::bind_method(D_METHOD("last_lockstep_count"), &RorWorld::last_lockstep_count);
    ClassDB::bind_method(D_METHOD("last_contact_count"), &RorWorld::last_contact_count);
    ClassDB::bind_method(D_METHOD("shares_island", "first", "second", "dt", "substeps"),
                         &RorWorld::shares_island);
    ClassDB::bind_method(D_METHOD("toggle_hooks", "solver", "mode", "group"), &RorWorld::toggle_hooks);
    ClassDB::bind_method(D_METHOD("toggle_ties", "solver", "group"), &RorWorld::toggle_ties);
    ClassDB::bind_method(D_METHOD("toggle_ropes", "solver", "group"), &RorWorld::toggle_ropes);
}

void RorWorld::add_solver(const Ref<RorSolver> &solver) {
    if (solver.is_valid()) {
        m_solvers.push_back(solver);
    }
}

RorWorld::~RorWorld() {
    sync_all();
}

void RorWorld::clear() {
    sync_all();
    m_solvers.clear();
}

std::vector<RorSolver *> RorWorld::members() const {
    std::vector<RorSolver *> out;
    for (const Ref<RorSolver> &solver : m_solvers) {
        out.push_back(solver.ptr());
    }
    return out;
}

void RorWorld::toggle_hooks(const Ref<RorSolver> &solver, int mode, int group) {
    sync_all();
    if (solver.is_valid()) {
        solver->toggle_hooks_among(members(), mode, group);
    }
}

void RorWorld::toggle_ties(const Ref<RorSolver> &solver, int group) {
    sync_all();
    if (solver.is_valid()) {
        solver->toggle_ties_among(members(), group, false);
    }
}

void RorWorld::toggle_ropes(const Ref<RorSolver> &solver, int group) {
    sync_all();
    if (solver.is_valid()) {
        solver->toggle_ropes_among(members(), group, false);
    }
}

void RorWorld::join_hooked(std::vector<size_t> &parent) const {
    for (size_t i = 0; i < m_solvers.size(); ++i) {
        std::vector<const RorSolver *> targets;
        for (const RorHook &hook : m_solvers[i]->m_hooks) {
            targets.push_back(hook.beam_target);
        }
        for (const RorTie &tie : m_solvers[i]->m_ties) {
            targets.push_back(tie.target);
        }
        for (const RorRope &rope : m_solvers[i]->m_ropes) {
            targets.push_back(rope.target);
        }
        for (const RorSolver *target : targets) {
            if (target == nullptr) {
                continue;
            }
            for (size_t j = 0; j < m_solvers.size(); ++j) {
                if (m_solvers[j].ptr() == target) {
                    parent[find_root(parent, i)] = find_root(parent, j);
                }
            }
        }
    }
}

void RorWorld::sync_all() const {
    for (const Ref<RorSolver> &solver : m_solvers) {
        solver->sync();
    }
}

int RorWorld::last_contact_count() const {
    sync_all();
    return m_last_contacts.load(std::memory_order_relaxed);
}

RorWorld::Bounds RorWorld::bounds_of(const RorSolver &solver) const {
    Bounds out{{1e300, 1e300, 1e300}, {-1e300, -1e300, -1e300}};
    for (const RorNode &node : solver.m_nodes) {
        const double at[3] = {solver.m_frame.world_x(node.position.x),
                              static_cast<double>(node.position.y),
                              solver.m_frame.world_z(node.position.z)};
        for (int axis = 0; axis < 3; ++axis) {
            out.low[axis] = std::min(out.low[axis], at[axis]);
            out.high[axis] = std::max(out.high[axis], at[axis]);
        }
    }
    return out;
}

// The causality bound: two actors whose boxes are further apart than both could close in `span`
// seconds at their speed limits, plus the range a contact reaches, cannot touch inside it.
bool RorWorld::linked(size_t first, size_t second, const std::vector<Bounds> &bounds,
                      float span) const {
    const RorSolver &a = **m_solvers[first];
    const RorSolver &b = **m_solvers[second];
    const double reach = static_cast<double>(a.m_speed_limit + b.m_speed_limit) * span +
                         std::max(a.m_collcabs.range, b.m_collcabs.range);
    for (int axis = 0; axis < 3; ++axis) {
        const double gap = std::max(bounds[first].low[axis] - bounds[second].high[axis],
                                    bounds[second].low[axis] - bounds[first].high[axis]);
        if (gap > reach) {
            return false;
        }
    }
    return true;
}

bool RorWorld::shares_island(int first, int second, float dt, int substeps) const {
    const int count = solver_count();
    if (first < 0 || second < 0 || first >= count || second >= count) {
        return false;
    }
    std::vector<Bounds> bounds;
    for (const Ref<RorSolver> &solver : m_solvers) {
        solver->sync();
        bounds.push_back(bounds_of(**solver));
    }
    // Islands are transitive: two actors each in reach of a third are in one island.
    std::vector<size_t> parent(m_solvers.size());
    std::iota(parent.begin(), parent.end(), 0);
    const float span = dt * static_cast<float>(substeps);
    for (size_t i = 0; i < m_solvers.size(); ++i) {
        for (size_t j = i + 1; j < m_solvers.size(); ++j) {
            if (linked(i, j, bounds, span)) {
                parent[find_root(parent, i)] = find_root(parent, j);
            }
        }
    }
    join_hooked(parent);
    return find_root(parent, static_cast<size_t>(first)) ==
           find_root(parent, static_cast<size_t>(second));
}

void RorWorld::step(float dt, int substeps) {
    sync_all();
    m_last_islands = 0;
    m_last_lockstep = 0;
    m_last_contacts.store(0, std::memory_order_relaxed);
    if (substeps <= 0 || m_solvers.empty()) {
        return;
    }
    // Upstream's once-a-frame attempt of every auto-lock hook (`CalcForcesEulerPrepare` asks for
    // it on a frame's first substep and the game runs it between frames).
    const std::vector<RorSolver *> everyone = members();
    for (RorSolver *solver : everyone) {
        if (!solver->m_hooks.empty()) {
            solver->toggle_hooks_among(everyone, RorHook::LOCK, -2);
        }
    }
    std::vector<Bounds> bounds;
    for (const Ref<RorSolver> &solver : m_solvers) {
        solver->sync();
        bounds.push_back(bounds_of(**solver));
    }
    std::vector<size_t> parent(m_solvers.size());
    std::iota(parent.begin(), parent.end(), 0);
    const float span = dt * static_cast<float>(substeps);
    for (size_t i = 0; i < m_solvers.size(); ++i) {
        for (size_t j = i + 1; j < m_solvers.size(); ++j) {
            if (linked(i, j, bounds, span)) {
                parent[find_root(parent, i)] = find_root(parent, j);
            }
        }
    }
    join_hooked(parent);
    // Members of each island in the order the actors were added, so the order contact is
    // resolved in is a property of the world and not of the partition.
    std::vector<std::vector<size_t>> islands(m_solvers.size());
    for (size_t i = 0; i < m_solvers.size(); ++i) {
        islands[find_root(parent, i)].push_back(i);
    }
    for (const std::vector<size_t> &members : islands) {
        if (members.empty()) {
            continue;
        }
        ++m_last_islands;
        if (members.size() == 1) {
            if (m_parallel) {
                m_solvers[members[0]]->step_async(dt, substeps);
            } else {
                m_solvers[members[0]]->step(dt, substeps);
            }
            continue;
        }
        m_last_lockstep += static_cast<int>(members.size());
        std::vector<RorSolver *> solvers;
        for (size_t m : members) {
            solvers.push_back(m_solvers[m].ptr());
        }
        if (!m_parallel) {
            m_last_contacts.fetch_add(step_island(solvers, dt, substeps), std::memory_order_relaxed);
            continue;
        }
        auto latch = std::make_shared<IslandLatch>();
        for (size_t k = 1; k < solvers.size(); ++k) {
            solvers[k]->m_worker.post([latch] { latch->wait(); });
        }
        // Raw pointers: the world holds every member and waits for them all before it lets one go
        // (`clear`, the destructor, the next `step`). A reference held by the job could be the
        // last one and free a solver on its own worker, which would then join itself.
        std::atomic<int> *contacts = &m_last_contacts;
        solvers[0]->m_worker.post([solvers, latch, contacts, dt, substeps] {
            contacts->fetch_add(step_island(solvers, dt, substeps), std::memory_order_relaxed);
            latch->release();
        });
    }
}

int RorWorld::step_island(const std::vector<RorSolver *> &members, float dt, int substeps) {
    const int64_t began = steady_usec();
    int contacts = 0;
    for (RorSolver *member : members) {
        RorSolver &solver = *member;
        solver.begin_steps();
        solver.m_collcabs.prepare(solver.m_nodes, solver.m_beams);
    }
    for (size_t i = 0; i < members.size(); ++i) {
        for (size_t j = i + 1; j < members.size(); ++j) {
            RorSolver &a = *members[i];
            RorSolver &b = *members[j];
            if (a.m_nodes.empty() || b.m_nodes.empty()) {
                continue;
            }
            const Vector3 closing = a.m_nodes.front().velocity - b.m_nodes.front().velocity;
            if (static_cast<float>(closing.length_squared()) > FAST_APPROACH_SQUARED) {
                reset_rates(a.m_collcabs);
                reset_rates(b.m_collcabs);
            }
        }
    }
    for (int step = 0; step < substeps; ++step) {
        // Upstream prepares every actor before it computes any: ropes locked to another member.
        for (RorSolver *member : members) {
            member->calc_ropes(true);
        }
        for (RorSolver *member : members) {
            member->substep(dt, step == 0);
        }
        // Upstream's `CalcBeamsInterActor`, after every member's own forces and before contact.
        for (RorSolver *member : members) {
            member->apply_inter_actor_links(members);
        }
        for (RorSolver *owner : members) {
            RorSolver &a = *owner;
            for (RorSolver *other : members) {
                if (other == owner) {
                    continue;
                }
                RorSolver &b = *other;
                // The other actor's frame-local positions in the owner's frame. Both origins are
                // whole multiples of 64 m, so the difference is exact.
                const Vector3 offset(static_cast<float>(b.m_frame.x - a.m_frame.x), 0.0f,
                                     static_cast<float>(b.m_frame.z - a.m_frame.z));
                contacts += resolve_inter_actor(a.m_collcabs, a.m_nodes,
                                                       a.m_ground_models[0], b.m_collcabs,
                                                       b.m_nodes, offset, dt);
            }
        }
    }
    const int64_t spent = steady_usec() - began;
    for (RorSolver *member : members) {
        member->m_step_usec.fetch_add(spent / static_cast<int64_t>(members.size()),
                                      std::memory_order_relaxed);
    }
    return contacts;
}

} // namespace rorgd
