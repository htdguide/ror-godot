#pragma once

#include <vector>

namespace rorgd {

struct RorWheel;

// Upstream's `DiffType`. A differential lists the ones it can switch between; the first is active.
enum class DiffType { SPLIT = 's', OPEN = 'o', VISCOUS = 'v', LOCKED = 'l' };

// One differential: upstream's `Differential`. Between two wheels it is an axle's own; between two
// axles (by their wheel differentials' indices) it joins them as a driveshaft would.
struct RorDifferential {
    int a = -1;
    int b = -1;
    std::vector<DiffType> types;
    // How far the two sides have turned against each other since the last switch, metres of tread.
    float delta_rotation = 0.0f;

    // Upstream's `CalcAxleTorque`: `in` shared between the two sides at `speed_a` and `speed_b`.
    void split(float speed_a, float speed_b, float in, float dt, float &out_a, float &out_b);
    // Upstream's `ToggleDifferentialMode`: the next type in the list becomes active.
    void toggle();
};

// Upstream's `TransferCase`: axle `ax_1` is always driven and `ax_2` only in 4WD, where a locked
// differential between the two (`diff`) joins them; `ratios` are its reductions, the first in force.
// Upstream's parser starts the list at 1 and appends the row's own, so a row's first is the second.
struct RorTransferCase {
    int ax_1 = -1;
    int ax_2 = -1;
    bool has_2wd = true;
    bool has_2wd_lo = false;
    bool four_wd = false;
    std::vector<float> ratios{1.0f};
    RorDifferential diff;
};

// The differentials of one rig, built the way upstream's `ActorSpawner` builds them and run the way
// its `Actor::CalcDifferentials` runs them: the engine's torque goes to every driven wheel, then the
// axle differentials share it between axles and the wheel differentials between each axle's two
// wheels, on last step's wheel speeds.
//
// A rig that names no axles gets a viscous differential for each pair of driven wheels in the order
// they were declared, and a viscous one between each pair of those; a rig that names axles and no
// interaxles gets a locked one between each pair of axles.
class RorDifferentials {
public:
    // `types` are upstream's letters; empty means upstream's default, open then locked. Returns the
    // new differential's index.
    int add_axle(int wheel_a, int wheel_b, const std::vector<DiffType> &types);
    // Between axles `a` and `b`, by their order in the file; empty means locked. Refused between
    // the two axles of a transfer case, as upstream refuses it.
    int add_interaxle(int a, int b, const std::vector<DiffType> &types);
    bool has_axles() const { return m_declared_axles > 0; }
    // Upstream's `ProcessTransferCase` checks, against the axles declared so far: false and nothing
    // kept if the axles are not two distinct declared ones, or if there is no 4WD axle and no 2WD.
    bool set_transfer_case(const RorTransferCase &transfer_case);
    RorTransferCase *transfer_case() { return m_has_transfer_case ? &m_transfer_case : nullptr; }
    const RorTransferCase *transfer_case() const { return m_has_transfer_case ? &m_transfer_case : nullptr; }

    // Builds the automatic differentials, once, from the wheels as they stand.
    void prepare(const std::vector<RorWheel> &wheels);
    void distribute(std::vector<RorWheel> &wheels, float dt);

    // Removes every differential between axles, the automatic ones included: the axles then turn
    // free of each other. Not an upstream control; a gate uses it to measure steering on its own.
    void clear_axle_diffs() {
        m_prepared = true;
        m_axle_diffs.clear();
    }
    // Upstream's `SyncReset`: no differential wound up; the transfer case's only while it is in 4WD.
    void reset_rotation();
    void toggle_wheel_diffs();
    void toggle_axle_diffs();
    int wheel_diff_count() const { return static_cast<int>(m_wheel_diffs.size()); }
    int axle_diff_count() const { return static_cast<int>(m_axle_diffs.size()); }
    // The active type of a differential, as upstream's letter, or 0 for none.
    char wheel_diff_type(int index) const;
    char axle_diff_type(int index) const;
    // What a differential joins: two wheels for an axle's, two axles for one between axles.
    const RorDifferential *wheel_diff(int index) const {
        return index >= 0 && index < wheel_diff_count() ? &m_wheel_diffs[static_cast<size_t>(index)] : nullptr;
    }
    const RorDifferential *axle_diff(int index) const {
        return index >= 0 && index < axle_diff_count() ? &m_axle_diffs[static_cast<size_t>(index)] : nullptr;
    }

    static std::vector<DiffType> parse_types(const char *letters);

private:
    void copy_detached_speeds(std::vector<RorWheel> &wheels);
    // One differential between axles: the four wheels' torque shared between the two axles.
    void split_axles(RorDifferential &diff, std::vector<RorWheel> &wheels, float dt);

    std::vector<RorDifferential> m_wheel_diffs;
    std::vector<RorDifferential> m_axle_diffs;
    int m_declared_axles = 0;
    bool m_prepared = false;
    RorTransferCase m_transfer_case;
    bool m_has_transfer_case = false;
};

} // namespace rorgd
