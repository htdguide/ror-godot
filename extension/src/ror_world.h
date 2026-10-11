#pragma once

#include "ror_solver.h"

#include <godot_cpp/classes/ref_counted.hpp>

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
// in the order. Lockstep islands are serial for now; running them on workers too is the next
// step, and the island list is already the unit of that work.
class RorWorld : public godot::RefCounted {
    GDCLASS(RorWorld, godot::RefCounted)

protected:
    static void _bind_methods();

public:
    void add_solver(const godot::Ref<RorSolver> &solver);
    void clear();
    int solver_count() const { return static_cast<int>(m_solvers.size()); }

    // Advances every actor by `substeps` of `dt`. Lone actors are posted to their own workers and
    // may still be stepping when this returns; every solver entry point waits for its own.
    void step(float dt, int substeps);

    // What the last `step` did, for a gate or the HUD: how many islands, how many actors stepped
    // in lockstep, and how many node-in-triangle contacts were resolved.
    int last_island_count() const { return m_last_islands; }
    int last_lockstep_count() const { return m_last_lockstep; }
    int last_contact_count() const { return m_last_contacts; }
    // Whether two actors are in one island now, judged as the next `step` would judge it.
    bool shares_island(int first, int second, float dt, int substeps) const;

private:
    struct Bounds {
        double low[3];
        double high[3];
    };

    Bounds bounds_of(const RorSolver &solver) const;
    bool linked(size_t first, size_t second, const std::vector<Bounds> &bounds, float span) const;
    void step_island(const std::vector<size_t> &members, float dt, int substeps);

    std::vector<godot::Ref<RorSolver>> m_solvers;
    int m_last_islands = 0;
    int m_last_lockstep = 0;
    int m_last_contacts = 0;
};

} // namespace rorgd
