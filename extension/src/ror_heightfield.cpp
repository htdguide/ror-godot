#include "ror_heightfield.h"

#include <algorithm>
#include <cmath>

using namespace godot;

namespace rorgd {

bool RorHeightfield::set_field(const PackedFloat32Array &heights, int width, int depth,
                               const Vector3 &origin, float spacing) {
    if (width < 2 || depth < 2 || spacing <= 0.0f ||
        heights.size() != static_cast<int64_t>(width) * static_cast<int64_t>(depth)) {
        clear();
        return false;
    }
    m_heights.resize(static_cast<size_t>(width) * static_cast<size_t>(depth));
    for (int64_t i = 0; i < heights.size(); ++i) {
        m_heights[static_cast<size_t>(i)] = heights[i];
    }
    m_width = width;
    m_depth = depth;
    m_origin = origin;
    m_spacing = spacing;
    m_enabled = true;
    return true;
}

bool RorHeightfield::set_surfaces(const PackedByteArray &surfaces, int width, int depth) {
    // Must match the height grid exactly: they are looked up by the same cell arithmetic, and
    // a mismatch would put the grip somewhere other than the ground it belongs to.
    if (width != m_width || depth != m_depth ||
        surfaces.size() != static_cast<int64_t>(width) * static_cast<int64_t>(depth)) {
        m_surfaces.clear();
        return false;
    }
    m_surfaces.resize(static_cast<size_t>(width) * static_cast<size_t>(depth));
    for (int64_t i = 0; i < surfaces.size(); ++i) {
        m_surfaces[static_cast<size_t>(i)] = surfaces[i];
    }
    return true;
}

int RorHeightfield::surface_at(const Vector3 &position) const {
    if (m_surfaces.empty()) {
        return 0;
    }
    const float u = (static_cast<float>(position.x) - static_cast<float>(m_origin.x)) / m_spacing;
    const float v = (static_cast<float>(position.z) - static_cast<float>(m_origin.z)) / m_spacing;
    const int x = std::max(0, std::min(static_cast<int>(std::floor(u + 0.5f)), m_width - 1));
    const int z = std::max(0, std::min(static_cast<int>(std::floor(v + 0.5f)), m_depth - 1));
    return m_surfaces[static_cast<size_t>(z) * static_cast<size_t>(m_width) + static_cast<size_t>(x)];
}

void RorHeightfield::clear() {
    m_heights.clear();
    m_surfaces.clear();
    m_width = 0;
    m_depth = 0;
    m_enabled = false;
}

float RorHeightfield::sample(int x, int z) const {
    // Clamped rather than wrapped: a rig that drives off the edge should find the edge
    // extending flat, not the far side of the map underneath it.
    const int cx = std::max(0, std::min(x, m_width - 1));
    const int cz = std::max(0, std::min(z, m_depth - 1));
    return m_heights[static_cast<size_t>(cz) * static_cast<size_t>(m_width) + static_cast<size_t>(cx)];
}

float RorHeightfield::height_at(const Vector3 &position) const {
    if (!m_enabled) {
        return 0.0f;
    }
    const float u = (static_cast<float>(position.x) - static_cast<float>(m_origin.x)) / m_spacing;
    const float v = (static_cast<float>(position.z) - static_cast<float>(m_origin.z)) / m_spacing;
    const int x = static_cast<int>(std::floor(u));
    const int z = static_cast<int>(std::floor(v));
    const float fx = u - static_cast<float>(x);
    const float fz = v - static_cast<float>(z);
    const float h00 = sample(x, z);
    const float h10 = sample(x + 1, z);
    const float h01 = sample(x, z + 1);
    const float h11 = sample(x + 1, z + 1);
    const float top = h00 + (h10 - h00) * fx;
    const float bottom = h01 + (h11 - h01) * fx;
    return static_cast<float>(m_origin.y) + top + (bottom - top) * fz;
}

Vector3 RorHeightfield::normal_at(const Vector3 &position) const {
    if (!m_enabled) {
        return Vector3(0.0f, 1.0f, 0.0f);
    }
    // Central difference over one cell either side. Sampling the interpolated height rather
    // than the grid keeps the normal continuous across a cell boundary, which matters because
    // a node sitting on a seam would otherwise be pushed two different ways on alternate steps.
    const Vector3 along_x(m_spacing, 0.0f, 0.0f);
    const Vector3 along_z(0.0f, 0.0f, m_spacing);
    const float dx = height_at(position + along_x) - height_at(position - along_x);
    const float dz = height_at(position + along_z) - height_at(position - along_z);
    return Vector3(-dx, 2.0f * m_spacing, -dz).normalized();
}

} // namespace rorgd
