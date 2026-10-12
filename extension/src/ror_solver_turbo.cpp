#include "ror_solver.h"

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
    apply_options(turbo, version, inertia_factor, count, params);
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

void RorSolver::bind_turbo_methods() {
    ClassDB::bind_method(D_METHOD("set_turbo", "version", "inertia_factor", "count", "params"), &RorSolver::set_turbo);
    ClassDB::bind_method(D_METHOD("turbo_psi"), &RorSolver::turbo_psi);
    ClassDB::bind_method(D_METHOD("engine_power_at", "rpm"), &RorSolver::engine_power_at);
    ClassDB::bind_static_method("RorSolver",
                                D_METHOD("turbo_probe", "version", "inertia_factor", "count", "params", "acc", "cur_acc",
                                         "rpm", "running", "max_rpm", "engine_torque", "dt"),
                                &RorSolver::turbo_probe);
}

} // namespace rorgd
