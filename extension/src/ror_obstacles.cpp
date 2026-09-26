#include "ror_obstacles.h"

#include <cmath>

using namespace godot;

namespace rorgd {

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
        // Out through the nearest face: a node a centimetre under the top of a ramp is pushed up,
        // not sideways out of the end of it, and the two are a metre apart in a long box.
        int axis = 0;
        float depth = depth_x;
        if (depth_y < depth) {
            axis = 1;
            depth = depth_y;
        }
        if (depth_z < depth) {
            axis = 2;
            depth = depth_z;
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

} // namespace rorgd
