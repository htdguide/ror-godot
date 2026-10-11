#include "ror_solver.h"

// Upstream's detacher groups, from the break branch of `Actor::CalcBeams`: a beam of a positive
// `detacher_group` breaking by strength takes every beam of that group and of its negative with it,
// and every wheel `wheeldetachers` names for the group comes off. A wheel held on by a ring of
// beams is how a vehicle loses one; the group is how the file says which beams those are.

#include <cstdlib>

using namespace godot;

namespace rorgd {

void RorSolver::detach_group(int group) {
    for (RorBeam &other : m_beams) {
        if (other.broken || std::abs(other.detacher_group) != group) {
            continue;
        }
        other.broken = true;
        // Only a plain beam counts towards what holds a cab node (`GetNumActiveConnectedBeams`).
        if (other.bound == BeamBound::NORMAL) {
            m_nodes[static_cast<size_t>(other.a)].active_beams -= 1;
            m_nodes[static_cast<size_t>(other.b)].active_beams -= 1;
        }
    }
    for (const std::pair<int, int> &detacher : m_wheel_detachers) {
        if (detacher.second == group) {
            m_wheels.detach(detacher.first);
        }
    }
}

void RorSolver::set_beam_detacher_group(int beam, int group) {
    sync();
    if (beam < 0 || beam >= static_cast<int>(m_beams.size())) {
        return;
    }
    m_beams[static_cast<size_t>(beam)].detacher_group = group;
}

void RorSolver::add_wheel_detacher(int wheel, int group) {
    sync();
    // Upstream's `ProcessWheelDetacher` refuses a wheel the rig does not have.
    if (wheel < 0 || wheel >= m_wheels.count()) {
        return;
    }
    m_wheel_detachers.emplace_back(wheel, group);
}

bool RorSolver::wheel_detached(int wheel) const {
    sync();
    return wheel >= 0 && wheel < m_wheels.count() && m_wheels.at(wheel).detached;
}

} // namespace rorgd
