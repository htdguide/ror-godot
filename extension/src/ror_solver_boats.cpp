#include "ror_solver.h"

#include <godot_cpp/core/class_db.hpp>

#include <cstdio>
#include <string>

using namespace godot;

namespace rorgd {

// The terrain's sea: whether it has one, and its height. Without one upstream skips buoyancy.
void RorSolver::set_water(bool has_water, float height) {
    sync();
    m_buoyance.set_water(has_water, height);
    m_wing_set.set_water(has_water, height);
}

// A buoyant `cab` triangle: `type` 0 normal (option b, D, F or S), 1 drag only (r), 2 no drag (s).
// A row with two buoyant options is two of them, as upstream's spawner makes it.
void RorSolver::add_buoy_cab(int a, int b, int c, int type) {
    sync();
    const int count = static_cast<int>(m_nodes.size());
    if (a < 0 || b < 0 || c < 0 || a >= count || b >= count || c >= count || type < 0 || type > 2) {
        return;
    }
    m_buoyance.add_cab(a, b, c, type);
}

// `cabs` each [a, b, c, type] over nodes 0..n; `steps` each a PackedVector3Array of every node's
// position then every node's velocity. Per step, `a_boat_floats_as_upstreams` line: the force
// buoyancy adds to each node, from zero.
PackedStringArray RorSolver::buoyancy_probe(float height, const Array &cabs, const Array &steps) {
    RorBuoyance buoyance;
    buoyance.set_water(true, height);
    int count = 0;
    for (int i = 0; i < cabs.size(); ++i) {
        const PackedInt32Array cab = cabs[i];
        buoyance.add_cab(cab[0], cab[1], cab[2], cab[3]);
        count = std::max(count, std::max(cab[0], std::max(cab[1], cab[2])) + 1);
    }
    NodeArray nodes(static_cast<size_t>(count));
    PackedStringArray out;
    for (int step = 0; step < steps.size(); ++step) {
        const PackedVector3Array v = steps[step];
        for (int k = 0; k < count; ++k) {
            nodes[static_cast<size_t>(k)].position = v[k];
            nodes[static_cast<size_t>(k)].velocity = v[count + k];
            nodes[static_cast<size_t>(k)].forces = Vector3();
        }
        buoyance.update(nodes, 0.0005f);
        std::string line;
        char buffer[96];
        for (const RorNode &node : nodes) {
            std::snprintf(buffer, sizeof buffer, "%.9g %.9g %.9g ", node.forces.x, node.forces.y, node.forces.z);
            line += buffer;
        }
        out.push_back(String(line.c_str()));
    }
    return out;
}

// A `screwprops` row: its reference, back and up nodes and its power. The index, or -1.
int RorSolver::add_screwprop(int noderef, int nodeback, int nodeup, float power) {
    sync();
    const int count = static_cast<int>(m_nodes.size());
    if (noderef < 0 || nodeback < 0 || nodeup < 0 || noderef >= count || nodeback >= count || nodeup >= count) {
        return -1;
    }
    return m_wing_set.add_screwprop(RorScrewprop(noderef, nodeback, nodeup, power));
}

// Upstream's boat keys for every screw prop: "throttle_step" adds `value` to its throttle,
// "rudder_step" to its rudder, "center" centres the rudder, "reverse" toggles the reverser,
// "throttle" sets it. Returns every prop's throttle and rudder, as upstream reads them back.
Dictionary RorSolver::boat_command(const String &action, float value) {
    sync();
    Array throttles;
    Array rudders;
    for (int i = 0; i < m_wing_set.screwprop_count(); ++i) {
        RorScrewprop &prop = m_wing_set.screwprop(i);
        if (action == "throttle_step") {
            prop.set_throttle(prop.throttle() + value);
        } else if (action == "rudder_step") {
            prop.set_rudder(prop.rudder_value() + value);
        } else if (action == "center") {
            prop.set_rudder(0);
        } else if (action == "reverse") {
            prop.toggle_reverse();
        } else if (action == "throttle") {
            prop.set_throttle(value);
        }
        throttles.push_back(prop.throttle());
        rudders.push_back(prop.rudder_value());
    }
    Dictionary out;
    out["throttle"] = throttles;
    out["rudder"] = rudders;
    return out;
}

// `nodes` [ref, back, up] of a three-node rig; `steps` each [action (0 none, 1 throttle_step,
// 2 rudder_step, 3 center, 4 reverse), value, water height, then each node's position]. Per step,
// `a_screw_prop_is_upstreams`' line: the force on the reference node, the throttle and the rudder.
PackedStringArray RorSolver::screwprop_probe(const PackedInt32Array &ids, float power, const Array &steps) {
    NodeArray nodes(3);
    RorScrewprop prop(ids[0], ids[1], ids[2], power);
    PackedStringArray out;
    for (int step = 0; step < steps.size(); ++step) {
        const PackedFloat32Array v = steps[step];
        switch (static_cast<int>(v[0])) {
            case 1: prop.set_throttle(prop.throttle() + v[1]); break;
            case 2: prop.set_rudder(prop.rudder_value() + v[1]); break;
            case 3: prop.set_rudder(0); break;
            case 4: prop.toggle_reverse(); break;
            default: break;
        }
        for (int k = 0; k < 3; ++k) {
            nodes[static_cast<size_t>(k)].position = Vector3(v[3 + 3 * k], v[4 + 3 * k], v[5 + 3 * k]);
            nodes[static_cast<size_t>(k)].forces = Vector3();
        }
        prop.update_forces(nodes, true, v[2]);
        const Vector3 f = nodes[static_cast<size_t>(ids[0])].forces;
        char buffer[160];
        std::snprintf(buffer, sizeof buffer, "%.9g %.9g %.9g %.9g %.9g", f.x, f.y, f.z, prop.throttle(), prop.rudder_value());
        out.push_back(String(buffer));
    }
    return out;
}

void RorSolver::bind_boat_methods() {
    ClassDB::bind_method(D_METHOD("add_screwprop", "noderef", "nodeback", "nodeup", "power"), &RorSolver::add_screwprop);
    ClassDB::bind_method(D_METHOD("boat_command", "action", "value"), &RorSolver::boat_command, DEFVAL(0.0f));
    ClassDB::bind_static_method("RorSolver", D_METHOD("screwprop_probe", "nodes", "power", "steps"), &RorSolver::screwprop_probe);
    ClassDB::bind_method(D_METHOD("set_water", "has_water", "height"), &RorSolver::set_water);
    ClassDB::bind_method(D_METHOD("add_buoy_cab", "a", "b", "c", "type"), &RorSolver::add_buoy_cab);
    ClassDB::bind_static_method("RorSolver", D_METHOD("buoyancy_probe", "height", "cabs", "steps"), &RorSolver::buoyancy_probe);
}

} // namespace rorgd
