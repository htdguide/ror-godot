#include "ror_solver.h"

#include "ror_aero.h"

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

// A `turboprops`/`turboprops2` row (`pitch` -10, upstream's variable pitch) or a `pistonprops`
// row (`piston`, its own fixed pitch): upstream's `BuildAeroEngine`. A node of -1 is none.
int RorSolver::add_turboprop(const PackedInt32Array &nodes, float power, const String &afl, bool piston, float pitch) {
    sync();
    if (nodes.size() != 7) {
        return -1;
    }
    const int count = static_cast<int>(m_nodes.size());
    for (int i = 0; i < 7; ++i) {
        // The hub, the back node and two blades are required; the rest may be -1, none.
        if ((i < 4 && nodes[i] < 0) || nodes[i] >= count) {
            return -1;
        }
    }
    auto airfoil = std::make_shared<RorAirfoil>();
    airfoil->load(afl);
    return m_wing_set.add_engine(std::make_unique<RorTurboprop>(m_nodes, nodes[0], nodes[1], nodes[2], nodes[3], nodes[4],
                                                                nodes[5], nodes[6], power, airfoil, piston, pitch));
}

// A `turbojets` row: front, back and side nodes, reversable, dry and wet thrust (kN), back diameter.
int RorSolver::add_turbojet(const PackedInt32Array &nodes, bool reversable, float dry_thrust, float wet_thrust,
                            float back_diameter) {
    sync();
    if (nodes.size() != 3 || nodes[0] < 0 || nodes[1] < 0 || nodes[2] < 0 || nodes[0] >= static_cast<int>(m_nodes.size()) ||
        nodes[1] >= static_cast<int>(m_nodes.size()) || nodes[2] >= static_cast<int>(m_nodes.size())) {
        return -1;
    }
    return m_wing_set.add_engine(std::make_unique<RorTurbojet>(m_nodes, nodes[0], nodes[1], nodes[2], reversable, dry_thrust,
                                                               wet_thrust, back_diameter));
}

// Upstream's airplane keys for every aero engine: "throttle" sets it to `value`, "throttle_step"
// adds `value`, "reverse" toggles the reversers, "start" flips the ignition.
void RorSolver::aero_command(const String &action, float value) {
    sync();
    for (int i = 0; i < m_wing_set.engine_count(); ++i) {
        RorAeroEngine &engine = m_wing_set.engine(i);
        if (action == "throttle") {
            engine.set_throttle(value);
        } else if (action == "throttle_step") {
            engine.set_throttle(engine.throttle() + value);
        } else if (action == "reverse") {
            engine.toggle_reverse();
        } else if (action == "start") {
            engine.flip_start();
        }
    }
}

Dictionary RorSolver::aero_state(int index) {
    sync();
    Dictionary out;
    if (index < 0 || index >= m_wing_set.engine_count()) {
        return out;
    }
    RorAeroEngine &engine = m_wing_set.engine(index);
    out["throttle"] = engine.throttle();
    out["rpm_pc"] = engine.rpm_pc();
    out["propwash"] = engine.propwash();
    out["ignition"] = engine.ignition();
    out["failed"] = engine.failed();
    return out;
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
    Array wash;
    for (size_t i = 0; i < w.wash_engines.size(); ++i) {
        wash.push_back(Vector2(w.wash_engines[i], w.wash_ratios[i]));
    }
    out["wash"] = wash;
    out["induced"] = w.use_induced_drag ? Vector3(w.id_span, w.id_area, w.id_left ? 1.0f : 0.0f) : Vector3(-1, -1, -1);
    return out;
}

namespace {
// An engine that only blows: the wing probe's prop wash.
class WashEngine : public RorAeroEngine {
public:
    WashEngine(float wash, const Vector3 &along) : wash_(wash), along_(along) {}
    void update_forces(NodeArray &, float, bool) override {}
    void set_throttle(float) override {}
    float throttle() const override { return 0.0f; }
    void reset() override {}
    void toggle_reverse() override {}
    void flip_start() override {}
    float propwash() const override { return wash_; }
    Vector3 axis() const override { return along_; }
    int noderef() const override { return 0; }
    float radius() const override { return 0.0f; }
    float rpm_pc() const override { return 0.0f; }
    bool failed() const override { return false; }
    bool ignition() const override { return false; }

private:
    float wash_;
    Vector3 along_;
};
} // namespace

// One wing on eight nodes, `params` [type, chordratio, mindef, maxdef, liftcoef, breakable, induced,
// span, area, left, wash ratio, propwash, wash axis], `start` its nodes as built, `steps` each [control, positions, front-left and
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
    std::vector<std::unique_ptr<RorAeroEngine>> engines;
    engines.push_back(std::make_unique<WashEngine>(params[11], params[12]));
    if (static_cast<float>(params[10]) > 0.0f) {
        wing.wash_engines.push_back(0);
        wing.wash_ratios.push_back(params[10]);
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
        wing.update_forces(nodes, &engines);
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

// One aero engine, `kind` "prop" (`ids` ref, back, p1-p4, couple; `params` power, piston, pitch) or
// "jet" (`ids` front, back, side; `params` reversable, dry, wet, back diameter, starting rpm), on nodes at
// `positions` of `masses`; `steps` each [throttle, reverse, start, do_update, positions,
// velocities]. Per step, `the_aero_engine_is_upstreams`' line: every node's force, the rpm, the
// prop wash, the pitch, and whether it has failed and has ignition.
PackedStringArray RorSolver::aero_probe(const String &kind, const PackedInt32Array &ids, const Array &params,
                                        const PackedVector3Array &positions, const PackedFloat32Array &masses,
                                        const String &afl, const Array &steps) {
    NodeArray nodes(static_cast<size_t>(positions.size()));
    for (int i = 0; i < positions.size(); ++i) {
        nodes[static_cast<size_t>(i)].position = positions[i];
        nodes[static_cast<size_t>(i)].mass = masses[i];
    }
    std::unique_ptr<RorAeroEngine> engine;
    RorTurboprop *prop = nullptr;
    if (kind == "prop") {
        auto airfoil = std::make_shared<RorAirfoil>();
        airfoil->load(afl);
        auto made = std::make_unique<RorTurboprop>(nodes, ids[0], ids[1], ids[2], ids[3], ids[4], ids[5], ids[6], params[0],
                                                   airfoil, params[1], params[2]);
        prop = made.get();
        engine = std::move(made);
    } else {
        auto made = std::make_unique<RorTurbojet>(nodes, ids[0], ids[1], ids[2], params[0], params[1], params[2], params[3]);
        made->set_rpm(params[4]);
        engine = std::move(made);
    }
    PackedStringArray out;
    for (int step = 0; step < steps.size(); ++step) {
        const Array each = steps[step];
        const PackedVector3Array at = each[4];
        const PackedVector3Array vel = each[5];
        for (size_t i = 0; i < nodes.size(); ++i) {
            nodes[i].position = at[static_cast<int>(i)];
            nodes[i].velocity = vel[static_cast<int>(i)];
            nodes[i].forces = Vector3();
        }
        if (static_cast<bool>(each[1])) {
            engine->toggle_reverse();
        }
        if (static_cast<bool>(each[2])) {
            engine->flip_start();
        }
        engine->set_throttle(each[0]);
        engine->update_forces(nodes, 0.0005f, each[3]);
        std::string line;
        char buffer[160];
        for (const RorNode &n : nodes) {
            std::snprintf(buffer, sizeof buffer, "%.9g %.9g %.9g ", n.forces.x, n.forces.y, n.forces.z);
            line += buffer;
        }
        const float rpm = prop != nullptr ? prop->rpm : engine->rpm_pc();
        std::snprintf(buffer, sizeof buffer, "| %.9g %.9g %.9g %d %d", rpm, engine->propwash(), prop != nullptr ? prop->pitch : 0.0,
                      engine->failed() ? 1 : 0, engine->ignition() ? 1 : 0);
        line += buffer;
        out.push_back(String(line.c_str()));
    }
    return out;
}

void RorSolver::bind_wing_methods() {
    ClassDB::bind_static_method("RorSolver",
                                D_METHOD("aero_probe", "kind", "ids", "params", "positions", "masses", "afl", "steps"),
                                &RorSolver::aero_probe);
    ClassDB::bind_static_method("RorSolver", D_METHOD("wing_probe", "afl", "params", "start", "steps"), &RorSolver::wing_probe);
    ClassDB::bind_method(D_METHOD("add_wing", "nodes", "type", "chord_point", "min_deflection", "max_deflection", "afl",
                                  "lift_coef"),
                         &RorSolver::add_wing);
    ClassDB::bind_method(D_METHOD("finish_wings"), &RorSolver::finish_wings);
    ClassDB::bind_method(D_METHOD("add_turboprop", "nodes", "power", "afl", "piston", "pitch"), &RorSolver::add_turboprop);
    ClassDB::bind_method(D_METHOD("add_turbojet", "nodes", "reversable", "dry_thrust", "wet_thrust", "back_diameter"),
                         &RorSolver::add_turbojet);
    ClassDB::bind_method(D_METHOD("aero_command", "action", "value"), &RorSolver::aero_command);
    ClassDB::bind_method(D_METHOD("aero_state", "index"), &RorSolver::aero_state);
    ClassDB::bind_method(D_METHOD("set_aero_controls", "aileron", "rudder", "elevator", "flap"), &RorSolver::set_aero_controls);
    ClassDB::bind_method(D_METHOD("wing_count"), &RorSolver::wing_count);
    ClassDB::bind_method(D_METHOD("wing_state", "index"), &RorSolver::wing_state);
}

} // namespace rorgd
