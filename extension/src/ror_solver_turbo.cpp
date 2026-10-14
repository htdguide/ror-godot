#include "ror_solver.h"

#include "ror_ogre_math.h"

#include <cstdio>
#include <string>

#include <godot_cpp/core/class_db.hpp>

// The `engturbo` row (`RorTurbo`), and the probe `the_turbo_is_upstreams` compares with upstream's
// own turbo pass in `tools/parity`.

using namespace godot;

namespace rorgd {

namespace {
void apply_options(RorTurbo &turbo, int version, float inertia_factor, int count, const PackedFloat32Array &params) {
    float values[11];
    for (int i = 0; i < 11; ++i) {
        values[i] = i < params.size() ? params[i] : 9999.0f;
    }
    turbo.set_options(version, inertia_factor, count, values);
}
} // namespace

void RorSolver::set_turbo(int version, float inertia_factor, int count, const PackedFloat32Array &params) {
    sync();
    apply_options(m_drivetrain.turbo(), version, inertia_factor, count, params);
}

float RorSolver::engine_power_at(float rpm) const {
    sync();
    return m_drivetrain.engine_power(rpm);
}

float RorSolver::turbo_psi() const {
    sync();
    return const_cast<RorDrivetrain &>(m_drivetrain).turbo().psi();
}

// Per step `i`: the throttle with its mixtures `acc[i]`, the driver's `cur_acc[i]`, the engine's
// `rpm[i]` and whether it `running[i]`. Out per step: every turbo's rpm, every blow-off rpm, and
// the power the turbos add to `engine_torque`.
PackedFloat32Array RorSolver::turbo_probe(int version, float inertia_factor, int count, const PackedFloat32Array &params,
                                          const PackedFloat32Array &acc, const PackedFloat32Array &cur_acc,
                                          const PackedFloat32Array &rpm, const PackedByteArray &running,
                                          float max_rpm, float engine_torque, float dt) {
    RorTurbo turbo;
    // Version 0: no `engturbo` row, the engine's own `OLD` turbo.
    if (version != 0) {
        apply_options(turbo, version, inertia_factor, count, params);
    }
    PackedFloat32Array out;
    for (int step = 0; step < acc.size(); ++step) {
        turbo.update(dt, acc[step], cur_acc[step], rpm[step], max_rpm, running[step] != 0);
        for (int i = 0; i < RorTurbo::MAXTURBO; ++i) {
            out.push_back(turbo.rpm[i]);
        }
        for (int i = 0; i < RorTurbo::MAXTURBO; ++i) {
            out.push_back(turbo.bov_rpm[i]);
        }
        out.push_back(turbo.power(engine_torque));
    }
    return out;
}

// `config` [min, max, torque, diff, reverse, neutral, n_gears, gears..., inertia, type (as a char
// code), clutch_force, shift_time, clutch_time, post_shift_time, stall, idle, maximix, minimix,
// braking, n_points, rpm, ratio..., gain, drag]; `steps` each [action, value, acc, wheel_rpm, do_update, pedal,
// priming, pump, node 0 velocity xyz, camera dir xyz, wheel 0 radius, brake, g-force y], as the
// oracle's `engine` mode reads them. Per step, `the_engine_is_upstreams`' line.
PackedStringArray RorSolver::engine_probe(const PackedFloat32Array &config, const Array &steps) {
    int at = 0;
    const auto next = [&config, &at]() { return config[at++]; };
    const float min_rpm = next(), max_rpm = next(), torque = next(), diff = next(), rev = next(), neutral = next();
    const int n_gears = static_cast<int>(next());
    std::vector<float> gears;
    for (int i = 0; i < n_gears; ++i) {
        gears.push_back(next());
    }
    RorDrivetrain engine;
    engine.configure(min_rpm, max_rpm, torque, diff, rev, neutral, gears);
    const float inertia = next();
    const char type = static_cast<char>(static_cast<int>(next()));
    const float clutch_force = next(), stime = next(), ctime = next(), pstime = next(), stall = next(), idle = next();
    const float maximix = next(), minimix = next(), braking = next();
    engine.set_options(inertia, type, clutch_force, ctime, stime, pstime, idle, stall, braking, maximix, minimix);
    const int n_points = static_cast<int>(next());
    std::vector<float> rpm, ratio;
    for (int i = 0; i < n_points; ++i) {
        rpm.push_back(next());
        ratio.push_back(next());
    }
    engine.set_torque_curve(rpm, ratio);
    const float gain = next(), drag = next();
    float wheel_rpm = 0.0f;
    PackedStringArray out;
    for (int step = 0; step < steps.size(); ++step) {
        const PackedFloat32Array v = steps[step];
        switch (static_cast<int>(v[0])) {
            case 1: engine.shift(static_cast<int>(v[1])); break;
            case 2: engine.toggle_auto_mode(); break;
            case 3: engine.auto_shift_up(); break;
            case 4: engine.auto_shift_down(); break;
            case 5: engine.auto_shift_set(static_cast<int>(v[1])); break;
            case 6: engine.set_contact(v[1] != 0.0f); break;
            case 7: engine.set_starter(v[1] != 0.0f); break;
            case 8: engine.start(); break;
            case 9: engine.stop(); break;
            default: break;
        }
        engine.auto_set_acc(v[2]);
        engine.set_manual_clutch(v[5]);
        engine.set_hydraulics(v[6] != 0.0f, v[7]);
        RorEngineActor actor;
        actor.node0_velocity = Vector3(v[8], v[9], v[10]);
        actor.camera_dir = ogre_normalised(Vector3(v[11], v[12], v[13]));
        actor.wheel0_radius = v[14];
        actor.brake = v[15];
        actor.gforce_y = v[16];
        // The oracle's vehicle, when the case has one (see its `engine` mode).
        wheel_rpm = gain != 0 ? wheel_rpm + 0.0005f * (engine.clutch_torque() * gain - wheel_rpm * drag) : v[3];
        engine.step(0.0005f, wheel_rpm, v[4] != 0.0f, actor);
        char buffer[256];
        std::snprintf(buffer, sizeof buffer, "%.9g %.9g %.9g %.9g %d %d %d %d %d %.9g %d", engine.rpm(), engine.current_acc(),
                      engine.clutch(), engine.clutch_torque(), engine.gear(), engine.autoselect(), static_cast<int>(engine.auto_mode()),
                      engine.shifting(), engine.post_shifting(), engine.shift_behaviour(), engine.running() ? 1 : 0);
        out.push_back(String(buffer));
    }
    return out;
}

Dictionary RorSolver::gearbox(const String &action, float value) {
    sync();
    RorDrivetrain &e = m_drivetrain;
    if (action == "mode") {
        e.toggle_auto_mode();
    } else if (action == "up") {
        e.shift(1);
    } else if (action == "down") {
        e.shift(-1);
    } else if (action == "neutral") {
        e.shift_to(0);
    } else if (action == "to") {
        e.shift_to(static_cast<int>(value));
    } else if (action == "auto_up") {
        e.auto_shift_up();
    } else if (action == "auto_down") {
        e.auto_shift_down();
    } else if (action == "clutch") {
        e.set_manual_clutch(value);
    }
    static const char *MODES[] = {"automatic", "semi-automatic", "manual", "manual stick", "manual with ranges"};
    Dictionary out;
    out["mode"] = MODES[static_cast<int>(e.auto_mode())];
    out["mode_index"] = static_cast<int>(e.auto_mode());
    out["gear"] = e.gear();
    out["autoselect"] = e.autoselect();
    out["clutch"] = e.clutch();
    out["shifting"] = e.shifting() != 0 || e.post_shifting() != 0;
    return out;
}

void RorSolver::bind_turbo_methods() {
    ClassDB::bind_method(D_METHOD("gearbox", "action", "value"), &RorSolver::gearbox, DEFVAL(0.0f));
    ClassDB::bind_static_method("RorSolver", D_METHOD("engine_probe", "config", "steps"), &RorSolver::engine_probe);
    ClassDB::bind_method(D_METHOD("set_turbo", "version", "inertia_factor", "count", "params"), &RorSolver::set_turbo);
    ClassDB::bind_method(D_METHOD("turbo_psi"), &RorSolver::turbo_psi);
    ClassDB::bind_method(D_METHOD("engine_power_at", "rpm"), &RorSolver::engine_power_at);
    ClassDB::bind_static_method("RorSolver",
                                D_METHOD("turbo_probe", "version", "inertia_factor", "count", "params", "acc", "cur_acc",
                                         "rpm", "running", "max_rpm", "engine_torque", "dt"),
                                &RorSolver::turbo_probe);
}

} // namespace rorgd
