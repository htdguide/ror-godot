#include "ror_obstacles.h"

#include <cmath>

using namespace godot;

namespace rorgd {

namespace {

// How far beyond a face to look for a neighbour. Smaller than any box this project builds and
// larger than the gap a float leaves between two that meet exactly.
constexpr float SKIN_M = 0.01f;

} // namespace

int RorObstacles::add_box(const Transform3D &transform, const Vector3 &half_extents, int surface) {
    RorObstacleBox box;
    box.basis = transform.basis.orthonormalized();
    box.origin = transform.origin;
    // The transform's own scale is folded into the extents, so a caller may size a box either way.
    const Vector3 scale = transform.basis.get_scale();
    box.half = Vector3(std::abs(half_extents.x * scale.x), std::abs(half_extents.y * scale.y),
                       std::abs(half_extents.z * scale.z));
    box.surface = surface;

    // World bounds: the box's half extents projected onto each world axis.
    const Vector3 x = box.basis.get_column(0) * box.half.x;
    const Vector3 y = box.basis.get_column(1) * box.half.y;
    const Vector3 z = box.basis.get_column(2) * box.half.z;
    const Vector3 reach(std::abs(x.x) + std::abs(y.x) + std::abs(z.x),
                        std::abs(x.y) + std::abs(y.y) + std::abs(z.y),
                        std::abs(x.z) + std::abs(y.z) + std::abs(z.z));
    box.aabb_min = box.origin - reach;
    box.aabb_max = box.origin + reach;

    m_boxes.push_back(box);
    m_near.clear();
    return static_cast<int>(m_boxes.size()) - 1;
}

void RorObstacles::clear() {
    m_boxes.clear();
    m_near.clear();
}

void RorObstacles::select(const Vector3 &min, const Vector3 &max) {
    m_near.clear();
    for (size_t i = 0; i < m_boxes.size(); ++i) {
        const RorObstacleBox &box = m_boxes[i];
        if (box.aabb_max.x < min.x || box.aabb_min.x > max.x) {
            continue;
        }
        if (box.aabb_max.y < min.y || box.aabb_min.y > max.y) {
            continue;
        }
        if (box.aabb_max.z < min.z || box.aabb_min.z > max.z) {
            continue;
        }
        m_near.push_back(static_cast<int>(i));
    }
}

bool RorObstacles::occupied(const Vector3 &point, int ignore) const {
    for (const int index : m_near) {
        if (index == ignore) {
            continue;
        }
        const RorObstacleBox &box = m_boxes[static_cast<size_t>(index)];
        const Vector3 offset = point - box.origin;
        const Vector3 local(offset.dot(box.basis.get_column(0)), offset.dot(box.basis.get_column(1)),
                            offset.dot(box.basis.get_column(2)));
        if (std::abs(static_cast<float>(local.x)) < box.half.x &&
            std::abs(static_cast<float>(local.y)) < box.half.y &&
            std::abs(static_cast<float>(local.z)) < box.half.z) {
            return true;
        }
    }
    return false;
}

bool RorObstacles::contact(const Vector3 &position, float &penetration, Vector3 &normal,
                           int &surface) const {
    bool found = false;
    float deepest = 0.0f;
    for (const int index : m_near) {
        const RorObstacleBox &box = m_boxes[static_cast<size_t>(index)];
        const Vector3 offset = position - box.origin;
        // Into the box's own frame, where the test is three comparisons.
        const Vector3 local(offset.dot(box.basis.get_column(0)), offset.dot(box.basis.get_column(1)),
                            offset.dot(box.basis.get_column(2)));
        const float depth_x = box.half.x - std::abs(static_cast<float>(local.x));
        if (depth_x <= 0.0f) {
            continue;
        }
        const float depth_y = box.half.y - std::abs(static_cast<float>(local.y));
        if (depth_y <= 0.0f) {
            continue;
        }
        const float depth_z = box.half.z - std::abs(static_cast<float>(local.z));
        if (depth_z <= 0.0f) {
            continue;
        }
        // **Out through the nearest face a node can actually leave by.** Nearest alone is right
        // while a box is wider than a node is deep inside it, and wrong the moment it is not: on
        // a 0.7 m wide, 4 m tall column a node falling onto the top is nearer a side than the top
        // after one centimetre, so it is pushed off something it should be resting on. That is
        // what stopped a terrain's objects being approximated by columns that cover their
        // surfaces rather than their corners.
        //
        // A node cannot be pushed into another solid box, so a face with a neighbour flush
        // against it is not an exit. Inside a grid of columns every side face has one and the
        // top is the only way out, which is the answer wanted — and it falls out of the geometry
        // rather than being asserted. Velocity was tried for this and is worse than useless: a
        // resting node has a little of it in every direction, the chosen face flips frame to
        // frame, and a rig sank into open ground while a pole hit threw it off at 277 m/s.
        const float depths[3] = {depth_x, depth_y, depth_z};
        int order[3] = {0, 1, 2};
        for (int i = 0; i < 2; ++i) {
            for (int j = i + 1; j < 3; ++j) {
                if (depths[order[j]] < depths[order[i]]) {
                    const int swap = order[i];
                    order[i] = order[j];
                    order[j] = swap;
                }
            }
        }
        int axis = order[0];
        float depth = depths[axis];
        for (int i = 0; i < 3; ++i) {
            const int candidate = order[i];
            const double along = candidate == 0 ? local.x : (candidate == 1 ? local.y : local.z);
            const Vector3 face = box.basis.get_column(candidate) * (along < 0.0 ? -1.0f : 1.0f);
            if (!occupied(position + face * (depths[candidate] + SKIN_M), index)) {
                axis = candidate;
                depth = depths[candidate];
                break;
            }
        }
        if (!found || depth > deepest) {
            found = true;
            deepest = depth;
            penetration = depth;
            const double along = axis == 0 ? local.x : (axis == 1 ? local.y : local.z);
            normal = box.basis.get_column(axis) * (along < 0.0 ? -1.0f : 1.0f);
            surface = box.surface;
        }
    }
    return found;
}


// The same contact law the ground uses, against the boxes a world puts on it.
void apply_obstacle_forces(NodeArray &nodes, const RorObstacles &obstacles,
                           const std::vector<RorGroundModel> &models, float dt) {
    if (obstacles.selected() == 0 || models.empty()) {
        return;
    }
    for (RorNode &node : nodes) {
        if (node.immovable) {
            continue;
        }
        float penetration = 0.0f;
        Vector3 normal;
        int surface = 0;
        if (!obstacles.contact(node.position, penetration, normal, surface)) {
            continue;
        }
        node.ground_contact = true;
        size_t model = 0;
        if (surface >= 0 && surface < static_cast<int>(models.size())) {
            model = static_cast<size_t>(surface);
        }
        node.forces += ground_contact_force(node, normal, penetration, dt, models[model]);
    }
}

} // namespace rorgd
