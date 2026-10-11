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
    // Between axles `a` and `b`, by their order in the file; empty means locked.
    int add_interaxle(int a, int b, const std::vector<DiffType> &types);
    bool has_axles() const { return m_declared_axles > 0; }

    // Builds the automatic differentials, once, from the wheels as they stand.
    void prepare(const std::vector<RorWheel> &wheels);
    void distribute(std::vector<RorWheel> &wheels, float dt);

    // Removes every differential between axles, the automatic ones included: the axles then turn
    // free of each other. Not an upstream control; a gate uses it to measure steering on its own.
    void clear_axle_diffs() {
        m_prepared = true;
        m_axle_diffs.clear();
    }
    void toggle_wheel_diffs();
    void toggle_axle_diffs();
    int wheel_diff_count() const { return static_cast<int>(m_wheel_diffs.size()); }
    int axle_diff_count() const { return static_cast<int>(m_axle_diffs.size()); }
    // The active type of a differential, as upstream's letter, or 0 for none.
    char wheel_diff_type(int index) const;
    char axle_diff_type(int index) const;

    static std::vector<DiffType> parse_types(const char *letters);

private:
    std::vector<RorDifferential> m_wheel_diffs;
    std::vector<RorDifferential> m_axle_diffs;
    int m_declared_axles = 0;
    bool m_prepared = false;
};

} // namespace rorgd
