#include "ror_triangles.h"

#include <algorithm>
#include <cmath>

using namespace godot;

namespace rorgd {

void RorTriangleSet::clear() {
    m_triangles.clear();
    m_cells.clear();
}

void RorTriangleSet::add(const Vector3 &a, const Vector3 &b, const Vector3 &c, int surface) {
    const Vector3 bx = b - a;
    const Vector3 by = c - a;
    Vector3 bz = bx.cross(by);
    const float area = bz.length();
    // A degenerate triangle has no normal to push along and no area to stand on. Collision meshes
    // carry them: a quad exported as two triangles with a repeated vertex is one.
    if (!(area > 0.0f) || !std::isfinite(area)) {
        return;
    }
    bz /= area;

    RorTriangle tri;
    tri.a = a;
    tri.normal = bz;
    tri.surface = surface;
    // Columns, matching upstream's `SetColumn(0, bx), (1, by), (2, bz)`.
    Basis reverse;
    reverse.set_column(0, bx);
    reverse.set_column(1, by);
    reverse.set_column(2, bz);
    tri.forward = reverse.inverse();

    tri.low = Vector3(std::min({a.x, b.x, c.x}), std::min({a.y, b.y, c.y}),
                      std::min({a.z, b.z, c.z})) - Vector3(SLAB_M, SLAB_M, SLAB_M);
    tri.high = Vector3(std::max({a.x, b.x, c.x}), std::max({a.y, b.y, c.y}),
                       std::max({a.z, b.z, c.z})) + Vector3(SLAB_M, SLAB_M, SLAB_M);

    const int index = static_cast<int>(m_triangles.size());
    m_triangles.push_back(tri);
    const int lo_x = static_cast<int>(std::floor(tri.low.x / CELL_M));
    const int hi_x = static_cast<int>(std::floor(tri.high.x / CELL_M));
    const int lo_z = static_cast<int>(std::floor(tri.low.z / CELL_M));
    const int hi_z = static_cast<int>(std::floor(tri.high.z / CELL_M));
    for (int x = lo_x; x <= hi_x; ++x) {
        for (int z = lo_z; z <= hi_z; ++z) {
            m_cells[key_of(x, z)].push_back(index);
        }
    }
}

bool RorTriangleSet::contact(const Vector3 &position, float &penetration, Vector3 &normal,
                             int &surface) const {
    if (m_triangles.empty()) {
        return false;
    }
    const auto cell = m_cells.find(key_of(static_cast<int>(std::floor(position.x / CELL_M)),
                                          static_cast<int>(std::floor(position.z / CELL_M))));
    if (cell == m_cells.end()) {
        return false;
    }

    bool found = false;
    float shallowest = SLAB_M;
    for (const int index : cell->second) {
        const RorTriangle &tri = m_triangles[static_cast<size_t>(index)];
        if (position.x < tri.low.x || position.x > tri.high.x || position.y < tri.low.y ||
            position.y > tri.high.y || position.z < tri.low.z || position.z > tri.high.z) {
            continue;
        }
        const Vector3 point = tri.forward.xform(position - tri.a);
        // Inside the triangle's own footprint, and behind its face by less than the slab: `u`
        // and `v` are barycentric, `point.z` is the distance along the unit normal.
        if (point.x < 0.0f || point.y < 0.0f || point.x + point.y > 1.0f) {
            continue;
        }
        if (point.z >= 0.0f || point.z <= -SLAB_M) {
            continue;
        }
        const float depth = -point.z;
        if (!found || depth < shallowest) {
            found = true;
            shallowest = depth;
            penetration = depth;
            normal = tri.normal;
            surface = tri.surface;
        }
    }
    return found;
}

void apply_triangle_forces(NodeArray &nodes, const RorTriangleSet &triangles,
                           const std::vector<RorGroundModel> &models, float dt) {
    if (triangles.count() == 0 || models.empty()) {
        return;
    }
    for (RorNode &node : nodes) {
        if (node.immovable) {
            continue;
        }
        float penetration = 0.0f;
        Vector3 normal;
        int surface = 0;
        if (!triangles.contact(node.position, penetration, normal, surface)) {
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
