#include "ror_solver.h"

#include <godot_cpp/core/class_db.hpp>

#include <string>

// Upstream's wings (`ActorSpawner::ProcessWing`, `FlexAirfoil`): built here, their induced drag
// set up as the spawner does, their control surfaces deflected once a frame (`Actor::updateVisual`)
// and their forces applied each substep with the aircraft forces (`CalcAircraftForces`).

using namespace godot;

namespace rorgd {

// One `wings` row: `nodes` its eight, `afl` its airfoil file's text ("" when none could be read,
// which leaves upstream's all-zero polar). Returns the wing's index.
int RorSolver::add_wing(const PackedInt32Array &nodes, const String &type, float chord_point, float min_deflection,
                        float max_deflection, const String &afl, float lift_coef) {
    sync();
    if (nodes.size() != 8) {
        return -1;
    }
    for (int i = 0; i < 8; ++i) {
        if (nodes[i] < 0 || nodes[i] >= static_cast<int>(m_nodes.size())) {
            return -1;
        }
    }
    RorWing wing;
    wing.nfld = nodes[0];
    wing.nfrd = nodes[1];
    wing.nflu = nodes[2];
    wing.nfru = nodes[3];
    wing.nbld = nodes[4];
    wing.nbrd = nodes[5];
    wing.nblu = nodes[6];
    wing.nbru = nodes[7];
    wing.type = type.is_empty() ? 'n' : static_cast<char>(type[0]);
    wing.chordratio = chord_point;
    wing.mindef = min_deflection;
    wing.maxdef = max_deflection;
    wing.liftcoef = lift_coef;
    wing.airfoil = std::make_shared<RorAirfoil>();
    wing.airfoil->load(afl);
    return m_wing_set.add(wing, m_nodes);
}

void RorSolver::finish_wings() {
    sync();
    m_wing_set.finish(m_nodes);
}

void RorSolver::set_aero_controls(float aileron, float rudder, float elevator, int flap) {
    sync();
    m_wing_set.set_controls(aileron, rudder, elevator, flap);
}

int RorSolver::wing_count() {
    sync();
    return m_wing_set.count();
}

// A wing's state: whether it has broken, its control surface's deflection, its angle of attack,
// and its induced drag as the spawner set it (span, area, left; -1s for none).
Dictionary RorSolver::wing_state(int index) {
    sync();
    Dictionary out;
    if (index < 0 || index >= m_wing_set.count()) {
        return out;
    }
    const RorWing &w = m_wing_set.at(index);
    out["broken"] = w.broken;
    out["deflection"] = w.deflection;
    out["aoa"] = w.aoa;
    out["induced"] = w.use_induced_drag ? Vector3(w.id_span, w.id_area, w.id_left ? 1.0f : 0.0f) : Vector3(-1, -1, -1);
    return out;
}

// One wing on eight nodes, `params` [type, chordratio, mindef, maxdef, liftcoef, breakable, induced,
// span, area, left], `start` its nodes as built, `steps` each [control, positions, front-left and
// front-right velocity]. Per step, `the_wing_is_upstreams`' line: every node's force, the angle of
// attack and whether it has broken.
PackedStringArray RorSolver::wing_probe(const String &afl, const Array &params, const PackedVector3Array &start,
                                        const Array &steps) {
    NodeArray nodes(8);
    for (int i = 0; i < 8; ++i) {
        nodes[static_cast<size_t>(i)].position = start[i];
    }
    RorWing wing;
    wing.nfld = 0, wing.nfrd = 1, wing.nflu = 2, wing.nfru = 3, wing.nbld = 4, wing.nbrd = 5, wing.nblu = 6, wing.nbru = 7;
    const String type = params[0];
    wing.type = type.is_empty() ? 'n' : static_cast<char>(type[0]);
    wing.chordratio = params[1];
    wing.mindef = params[2];
    wing.maxdef = params[3];
    wing.liftcoef = params[4];
    wing.breakable = params[5];
    wing.airfoil = std::make_shared<RorAirfoil>();
    wing.airfoil->load(afl);
    wing.setup(nodes);
    if (static_cast<bool>(params[6])) {
        wing.enable_induced_drag(params[7], params[8], params[9]);
    }
    PackedStringArray out;
    for (int step = 0; step < steps.size(); ++step) {
        const Array each = steps[step];
        const PackedVector3Array at = each[1];
        for (int i = 0; i < 8; ++i) {
            nodes[static_cast<size_t>(i)].position = at[i];
            nodes[static_cast<size_t>(i)].velocity = Vector3();
            nodes[static_cast<size_t>(i)].forces = Vector3();
        }
        nodes[0].velocity = each[2];
        nodes[1].velocity = each[3];
        wing.set_control_deflection(each[0]);
        wing.update_broken(nodes);
        wing.update_forces(nodes);
        std::string line;
        char buffer[96];
        for (const RorNode &n : nodes) {
            std::snprintf(buffer, sizeof buffer, "%.9g %.9g %.9g ", n.forces.x, n.forces.y, n.forces.z);
            line += buffer;
        }
        std::snprintf(buffer, sizeof buffer, "| %.9g %d", wing.aoa, wing.broken ? 1 : 0);
        line += buffer;
        out.push_back(String(line.c_str()));
    }
    return out;
}

void RorSolver::bind_wing_methods() {
    ClassDB::bind_static_method("RorSolver", D_METHOD("wing_probe", "afl", "params", "start", "steps"), &RorSolver::wing_probe);
    ClassDB::bind_method(D_METHOD("add_wing", "nodes", "type", "chord_point", "min_deflection", "max_deflection", "afl",
                                  "lift_coef"),
                         &RorSolver::add_wing);
    ClassDB::bind_method(D_METHOD("finish_wings"), &RorSolver::finish_wings);
    ClassDB::bind_method(D_METHOD("set_aero_controls", "aileron", "rudder", "elevator", "flap"), &RorSolver::set_aero_controls);
    ClassDB::bind_method(D_METHOD("wing_count"), &RorSolver::wing_count);
    ClassDB::bind_method(D_METHOD("wing_state", "index"), &RorSolver::wing_state);
}

} // namespace rorgd
