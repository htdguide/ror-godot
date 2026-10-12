#pragma once

#include "ror_solver.h"

#include <godot_cpp/classes/ref_counted.hpp>

#include <atomic>
#include <cstdint>
#include <vector>

namespace rorgd {

// Several actors stepped together, and contact between them. PLAN §0.12, steps 3 and 4.
//
// Each `RorSolver` is one actor and knows only its own nodes, so two vehicles passed through each
// other. This holds the actors and, once per `step`, partitions them into islands — groups that
// could touch before the call is over — **derived fresh every call from the actors' own bounds and
// the causality bound** rather than kept, so there is no history to make it order-dependent:
//
//   two actors share an island when the gap between their boxes is under
//   (v_max of one + v_max of the other) * call length + collision range
//
// which is a proof, not a heuristic, because no node can outrun its solver's speed limit
// (`no_node_outruns_the_speed_limit`).
//
// An actor alone in its island steps the whole call on its own worker, so separate vehicles run
// on separate cores. An island of several steps in lockstep on the calling thread, one substep at
// a time, and after every substep each member's collision triangles are tested against every
// other member's contactable nodes — upstream's `ResolveInterActorCollisions`, in upstream's place
// in the order. That lockstep runs on the first member's worker, so separate islands step on
// separate cores too; the other members' workers wait for it, so each solver's own `sync` still
// means "my step is done". Islands share nothing, so the result is bit-equal to stepping them one
// after another (`islands_step_in_parallel_as_they_would_in_turn`).
class RorWorld : public godot::RefCounted {
    GDCLASS(RorWorld, godot::RefCounted)

protected:
    static void _bind_methods();

public:
    ~RorWorld() override;
    void add_solver(const godot::Ref<RorSolver> &solver);
    void clear();
    int solver_count() const { return static_cast<int>(m_solvers.size()); }

    // Advances every actor by `substeps` of `dt`. Lone actors are posted to their own workers and
    // may still be stepping when this returns; every solver entry point waits for its own.
    void step(float dt, int substeps);
    // Off, every island steps on the calling thread, one after another, before `step` returns: the
    // serial reference the parallel run is held to.
    void set_parallel(bool parallel) { m_parallel = parallel; }
    bool is_parallel() const { return m_parallel; }

    // What the last `step` did, for a gate or the HUD: how many islands, how many actors stepped
    // in lockstep, and how many node-in-triangle contacts were resolved.
    int last_island_count() const { return m_last_islands; }
    int last_lockstep_count() const { return m_last_lockstep; }
    // Waits for the last step, whose contacts are counted on the workers.
    int last_contact_count() const;
    // Whether two actors are in one island now, judged as the next `step` would judge it.
    bool shares_island(int first, int second, float dt, int substeps) const;
    // Upstream's hook keys for `solver`'s hooks, reaching every vehicle in this world.
    void toggle_hooks(const godot::Ref<RorSolver> &solver, int mode, int group);

private:
    struct Bounds {
        double low[3];
        double high[3];
    };

    Bounds bounds_of(const RorSolver &solver) const;
    bool linked(size_t first, size_t second, const std::vector<Bounds> &bounds, float span) const;
    // Steps one island in lockstep on the calling thread; returns the contacts it resolved.
    static int step_island(const std::vector<RorSolver *> &members, float dt, int substeps);
    void sync_all() const;
    // Joins into one island every pair a hook links, whatever their distance.
    void join_hooked(std::vector<size_t> &parent) const;
    std::vector<RorSolver *> members() const;

    std::vector<godot::Ref<RorSolver>> m_solvers;
    int m_last_islands = 0;
    int m_last_lockstep = 0;
    std::atomic<int> m_last_contacts{0};
    bool m_parallel = true;
};

} // namespace rorgd
