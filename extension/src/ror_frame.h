#pragma once

#include <godot_cpp/variant/vector3.hpp>

#include <cmath>

namespace rorgd {

// The origin an actor's nodes are stored relative to: PLAN §0.12, per-actor frames.
//
// float32 resolves a coordinate to about `distance * 2^-23`, and every beam force begins with the
// difference of two node positions, so a rig stored in world coordinates carries phantom stretch
// that grows with its distance from the world origin: at La Paz's spawn, 3.9 km out, the settled
// hero rang four times harder than at the origin and bent 78 beams settling. Stored relative to a
// frame that follows it, a node's coordinates never exceed the frame radius and that error stops
// depending on where the rig is.
//
// X and Z only. Y stays global, because only the horizontal coordinates grow with a map and a
// global Y keeps a ground height directly comparable to a node's height.
//
// The origin is held in double and is always a whole multiple of `STEP_M`, so shifting a node by
// the difference of two origins is exact in float, and a cell index on a grid that divides
// `STEP_M` shifts by a whole number of cells.
struct RorFrame {
    static constexpr double STEP_M = 64.0;

    double x = 0.0;
    double z = 0.0;

    godot::Vector3 to_world(const godot::Vector3 &local) const {
        return godot::Vector3(static_cast<float>(static_cast<double>(local.x) + x), local.y,
                              static_cast<float>(static_cast<double>(local.z) + z));
    }
    godot::Vector3 to_local(const godot::Vector3 &world) const {
        return godot::Vector3(static_cast<float>(static_cast<double>(world.x) - x), world.y,
                              static_cast<float>(static_cast<double>(world.z) - z));
    }
    // `local` minus a point given in world coordinates, taken in double: how a static thing that
    // lives in world space — a box, a triangle, a heightfield's corner — is measured from a node
    // without differencing two numbers of world magnitude in float.
    godot::Vector3 from(const godot::Vector3 &local, const godot::Vector3 &world) const {
        return godot::Vector3(
            static_cast<float>(static_cast<double>(local.x) + x - static_cast<double>(world.x)),
            local.y - world.y,
            static_cast<float>(static_cast<double>(local.z) + z - static_cast<double>(world.z)));
    }
    double world_x(float local_x) const { return static_cast<double>(local_x) + x; }
    double world_z(float local_z) const { return static_cast<double>(local_z) + z; }

    // The whole number of steps nearest `metres`.
    static double snap(double metres) { return STEP_M * std::round(metres / STEP_M); }
};

} // namespace rorgd
