#include "ror_solver.h"

#include "ror_ogre_math.h"

#include <godot_cpp/core/class_db.hpp>

#include <string>

// Upstream's animators (`ActorSpawner::ProcessAnimator`, `Actor::CalcAnimators`): hydros moved by
// what the vehicle is doing. This gathers what they read once a substep (`ror_animators.cpp`).

using namespace godot;

namespace rorgd {

// Upstream's `ProcessAnimator`: a beam as long as it was built, with the beam defaults' scaled
// rates, its bounds 0.99999 short and 1000000 long unless the row limits them, and the hydro.
// Returns the hydro index, for its inertia.
int RorSolver::add_animator(int a, int b, float factor, int flags, float param, float short_limit, float long_limit,
                            float spring, float damp, float strength, int detacher_group) {
    sync();
    if (a < 0 || b < 0 || a >= static_cast<int>(m_nodes.size()) || b >= static_cast<int>(m_nodes.size())) {
        return -1;
    }
    const float length = static_cast<float>(m_nodes[static_cast<size_t>(a)].position.distance_to(
            m_nodes[static_cast<size_t>(b)].position));
    const int beam = add_beam(a, b, length, spring, damp);
    RorBeam &made = m_beams[static_cast<size_t>(beam)];
    made.strength = strength;
    made.deformable = false;
    made.detacher_group = detacher_group;
    made.short_bound = std::isnan(short_limit) ? 0.99999f : short_limit;
    made.long_bound = std::isnan(long_limit) ? 1000000.0f : long_limit;
    return m_steering.add_animator(beam, factor, static_cast<uint32_t>(flags), param);
}

void RorSolver::set_camera_roll_node(int node) {
    sync();
    if (node >= 0 && node < static_cast<int>(m_nodes.size())) {
        m_camera_roll = node;
    }
}

void RorSolver::set_speedo_max(float kph) {
    sync();
    m_speedo_max_kph = kph;
}

RorAnimatorInputs RorSolver::animator_inputs() const {
    RorAnimatorInputs in;
    in.engine = m_drivetrain.configured();
    in.crank_factor = m_drivetrain.crank_factor();
    in.gear = m_drivetrain.gear();
    in.num_gears = m_drivetrain.gear_count();
    in.parking_brake = m_wheels.parking_brake();
    in.wheel_speed = m_wheels.driven_speed();
    in.speedo_max_kph = m_speedo_max_kph;
    in.rpm = m_drivetrain.rpm();
    in.shift_up_rpm = m_drivetrain.max_rpm();
    in.turbo_psi = const_cast<RorDrivetrain &>(m_drivetrain).turbo().psi();
    in.brake = m_wheels.brake();
    in.acc = m_drivetrain.current_acc();
    in.clutch = m_drivetrain.clutch();
    const RorDifferentials &diffs = m_wheels.differentials();
    if (diffs.wheel_diff_count() > 0) {
        const char type = diffs.wheel_diff_type(0);
        in.diff_kind = type == 'o' ? 0 : (type == 's' ? 1 : (type == 'l' ? 2 : 3));
    }
    if (!m_nodes.empty()) {
        in.node0_velocity = m_nodes[0].velocity;
        in.node0_height = m_nodes[0].position.y;
    }
    // Upstream's `GetCameraDir` and `GetCameraRoll`, from the main camera's nodes.
    const int pos = m_direction_pos >= 0 ? m_direction_pos : 0;
    const int dir = m_direction_dir >= 0 ? m_direction_dir : 0;
    const int count = static_cast<int>(m_nodes.size());
    if (pos < count && dir < count && m_camera_roll < count) {
        in.camera_dir = ogre_normalised(m_nodes[static_cast<size_t>(pos)].position - m_nodes[static_cast<size_t>(dir)].position);
        in.camera_roll =
                ogre_normalised(m_nodes[static_cast<size_t>(pos)].position - m_nodes[static_cast<size_t>(m_camera_roll)].position);
    }
    return in;
}

// `rows` each [flags, param, factor, ref_length, short, long]; `steps` each the values the
// oracle's `anim` mode reads, in its order. Per step, `the_animator_is_upstreams`' line: every
// animator beam's length and the shared memory.
PackedStringArray RorSolver::animator_probe(const Array &rows, const Array &steps) {
    RorSteering steering;
    BeamArray beams(static_cast<size_t>(rows.size()));
    for (int i = 0; i < rows.size(); ++i) {
        const Array row = rows[i];
        RorBeam &beam = beams[static_cast<size_t>(i)];
        beam.reference_length = row[3];
        beam.rest_length = row[3];
        beam.short_bound = row[4];
        beam.long_bound = row[5];
        steering.add_animator(i, row[2], static_cast<uint32_t>(static_cast<int64_t>(row[0])), row[1]);
    }
    PackedStringArray out;
    for (int step = 0; step < steps.size(); ++step) {
        const PackedFloat32Array v = steps[step];
        RorAnimatorInputs in;
        in.engine = v[0] != 0.0f;
        in.crank_factor = v[1];
        in.gear = static_cast<int>(v[2]);
        in.num_gears = static_cast<int>(v[3]);
        in.parking_brake = v[4] != 0.0f;
        in.wheel_speed = v[5];
        in.speedo_max_kph = v[6];
        in.rpm = v[7];
        in.shift_up_rpm = v[8];
        in.turbo_psi = v[9];
        in.brake = v[10];
        in.acc = v[11];
        in.clutch = v[12];
        in.diff_kind = static_cast<int>(v[13]);
        in.node0_velocity = Vector3(v[14], v[15], v[16]);
        in.node0_height = v[17];
        const Vector3 pos(v[18], v[19], v[20]);
        in.camera_dir = ogre_normalised(pos - Vector3(v[21], v[22], v[23]));
        in.camera_roll = ogre_normalised(pos - Vector3(v[24], v[25], v[26]));
        steering.update(0.0005f, in.wheel_speed, beams, &in);
        std::string line;
        char buffer[48];
        for (const RorBeam &beam : beams) {
            std::snprintf(buffer, sizeof buffer, "%.9g ", beam.rest_length);
            line += buffer;
        }
        const RorAnimatorMemory &memory = steering.animator_memory();
        std::snprintf(buffer, sizeof buffer, "| %.9g %d %.9g", memory.previous_crank, memory.previous_gear, memory.shift_timer);
        line += buffer;
        out.push_back(String(line.c_str()));
    }
    return out;
}

void RorSolver::bind_animator_methods() {
    ClassDB::bind_static_method("RorSolver", D_METHOD("animator_probe", "rows", "steps"), &RorSolver::animator_probe);
    ClassDB::bind_method(D_METHOD("add_animator", "a", "b", "factor", "flags", "param", "short_limit", "long_limit",
                                  "spring", "damp", "strength", "detacher_group"),
                         &RorSolver::add_animator);
    ClassDB::bind_method(D_METHOD("set_camera_roll_node", "node"), &RorSolver::set_camera_roll_node);
    ClassDB::bind_method(D_METHOD("set_speedo_max", "kph"), &RorSolver::set_speedo_max);
}

} // namespace rorgd
