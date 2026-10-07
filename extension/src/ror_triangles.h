#pragma once

#include "ror_ground.h"
#include "ror_node.h"

#include <godot_cpp/variant/basis.hpp>
#include <godot_cpp/variant/vector3.hpp>

#include <cstdint>
#include <unordered_map>
#include <vector>

namespace rorgd {

// A terrain's static collision geometry as triangles, which is what upstream collides against.
//
// **A box has to decide which face to push a node out of, and a triangle never does.** Upstream's
// box branch picks the nearest face, and so does this project's, because that is right while a box
// is wider than a node is deep inside it. A pole is 0.148 m deep: a node a centimetre past its
// midplane is nearer the back face, so the obstacle ejects the car forward instead of holding it.
// Measured, the Mazda 626 drove 1.08 m through a box the size of La Paz's own pole at 21.3 m/s.
//
// A triangle carries its own outward normal and is solid on one side, so there is no midplane to
// flip across. 59 of this library's 96 object definitions ship a `beginmesh` collision mesh and
// only 21 state a box, so this is the shape most of the library's collision is authored in.
//
// Upstream's `Collisions::addCollisionTri` and the triangle branch of `Collisions::nodeCollision`.
struct RorTriangle {
    godot::Vector3 a;
    // Columns (b - a), (c - a), and the unit normal. Its inverse takes a world offset from `a`
    // into (u, v, distance along the normal), which is the whole of the test.
    godot::Basis forward;
    godot::Vector3 normal;
    godot::Vector3 low;
    godot::Vector3 high;
    int surface = 0;
};

// Static triangles with a grid on the ground plane to find them by.
class RorTriangleSet {
public:
    void clear();
    void add(const godot::Vector3 &a, const godot::Vector3 &b, const godot::Vector3 &c,
             int surface);
    int count() const { return static_cast<int>(m_triangles.size()); }
    // The shallowest triangle this point is inside the collision slab of. False when none is.
    bool contact(const godot::Vector3 &position, float &penetration, godot::Vector3 &normal,
                 int &surface) const;

private:
    // Upstream's `CELL_SIZE`, the cell its own triangle index uses.
    static constexpr float CELL_M = 2.0f;
    // How far behind a face a node still counts as touching it, from upstream's own
    // `point.z > -0.1`. Past this the node has gone through and is let go, which is what stops a
    // thin wall grabbing something already clear of it.
    static constexpr float SLAB_M = 0.1f;

    static int64_t key_of(int x, int z) {
        return (static_cast<int64_t>(x) << 32) ^ static_cast<uint32_t>(z);
    }

    std::vector<RorTriangle> m_triangles;
    std::unordered_map<int64_t, std::vector<int>> m_cells;
};

// Applies the contact law to every node standing inside a triangle's slab.
void apply_triangle_forces(NodeArray &nodes, const RorTriangleSet &triangles,
                           const std::vector<RorGroundModel> &models, float dt);

} // namespace rorgd
