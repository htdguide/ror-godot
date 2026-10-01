#include "ror_solver.h"

// Putting a damaged rig back the way it was built.
//
// Damage is not one field. A beam that has taken a hit can have a changed `rest_length` (the
// bend itself), weakened `max_pos_stress` and `max_neg_stress`, a recomputed `minmax_stress`, a
// reduced `strength` where upstream softened it instead of snapping it, and `broken` set — and
// breaking a beam also decrements `active_beams` on both of its nodes, which is the count
// upstream consults before it is willing to break the last beams holding a cab node.
//
// `RigBuilder.place` resets node positions, velocities and rest lengths and used to call that
// "undeformed". It is not: a rig put back on its wheels that way keeps every broken beam it
// had, so the doors and the wheels fall off again the moment it is stepped. Restoring the rest
// length alone undoes the bend and leaves the break.
//
// Rather than try to recompute what each field should be, this keeps a copy of the beams as the
// rig was built and puts it back. The copy is the only honest reference: the as-built values
// come from the file's own `set_beam_defaults` by way of several code paths, and recomputing
// them here would be a second implementation of rig building that could drift from the first.

namespace rorgd {

// Takes the rig as built, before anything has had a chance to damage it.
//
// Called at the end of `RigBuilder.build`. Damage can only happen inside a step, so any moment
// before the first step is the as-built state; the end of building is simply the clearest one to
// name. Calling it again later would snapshot the damage as if it were the factory condition,
// which is why nothing else calls it.
void RorSolver::snapshot_undamaged() {
    m_undamaged_beams = m_beams;
    m_undamaged_active_beams.clear();
    m_undamaged_active_beams.reserve(m_nodes.size());
    for (const RorNode &node : m_nodes) {
        m_undamaged_active_beams.push_back(node.active_beams);
    }
}

// Puts every beam back to its as-built condition: unbroken, unbent, at full strength.
//
// A no-op when there is no snapshot, so a rig built before this existed behaves as it did rather
// than being silently half-repaired.
void RorSolver::repair() {
    if (m_undamaged_beams.size() != m_beams.size()) {
        return;
    }
    m_beams = m_undamaged_beams;
    if (m_undamaged_active_beams.size() != m_nodes.size()) {
        return;
    }
    for (size_t i = 0; i < m_nodes.size(); ++i) {
        m_nodes[i].active_beams = m_undamaged_active_beams[i];
    }
}

} // namespace rorgd
