#pragma once

#include <godot_cpp/variant/transform3d.hpp>
#include <godot_cpp/variant/vector3.hpp>

#include <vector>

namespace rorgd {

// The solid things standing on the ground: ramps, walls, kerbs, rocks, blocks.
//
// A heightfield can only describe ground that is a function of x and z, so it can carry a hump, a
// rut and a dip, and cannot carry a wall, an overhang, or the vertical face of a ramp. Those are
// what a test park is made of, so they are boxes — oriented, static, and contacted with upstream's
// own ground law rather than with a second contact model, because a rig hitting a wall and a rig
// landing on a slope are the same physics and should not be two implementations.
//
// Static, deliberately: a box never moves, so its world bounds are computed once and the broad
// phase is a list of indices near the rig, rebuilt per step rather than per substep.
struct RorObstacleBox {
    godot::Basis basis;      // Orientation. Columns are the box's own axes, unit length.
    godot::Vector3 origin;   // Centre, in world space.
    godot::Vector3 half;     // Half extents, along the box's own axes.
    godot::Vector3 aabb_min; // World bounds, for the broad phase.
    godot::Vector3 aabb_max;
    int surface = 0;         // Which ground model the face is made of.
};

class RorObstacles {
public:
    // Returns the box's index. `transform` places and orients it; `half_extents` are along its
    // own axes.
    int add_box(const godot::Transform3D &transform, const godot::Vector3 &half_extents,
                int surface);
    void clear();
    size_t count() const { return m_boxes.size(); }

    // Narrows the set to the boxes whose bounds overlap the given world bounds, and keeps it.
    // Every contact query afterwards tests only those, until the next call.
    void select(const godot::Vector3 &min, const godot::Vector3 &max);
    size_t selected() const { return m_near.size(); }

    // The deepest contact for a point among the selected boxes. Returns false when the point is
    // outside all of them. `penetration` is how far inside the surface the point is and `normal`
    // points out of it, which is the same convention the heightfield contact uses.
    bool contact(const godot::Vector3 &position, float &penetration, godot::Vector3 &normal,
                 int &surface) const;

private:
    std::vector<RorObstacleBox> m_boxes;
    std::vector<int> m_near;
};

} // namespace rorgd
