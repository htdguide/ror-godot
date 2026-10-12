#pragma once

#include <godot_cpp/variant/vector3.hpp>

#include <cmath>

namespace rorgd {

// Ogre 1.11's vector arithmetic where it differs from Godot's, for the laws ported from upstream:
// the last bit of a rounding is part of what parity with upstream means (`tools/parity`).

// `Vector3::normalise`: in place, multiplying by the inverse length rather than dividing, and only
// when the length is above zero. Returns the length it had.
inline float ogre_normalise(godot::Vector3 &v) {
    const float length = std::sqrt(static_cast<float>(v.x * v.x + v.y * v.y + v.z * v.z));
    if (length > 0.0f) {
        const float inverse = 1.0f / length;
        v.x *= inverse;
        v.y *= inverse;
        v.z *= inverse;
    }
    return length;
}

inline godot::Vector3 ogre_normalised(godot::Vector3 v) {
    ogre_normalise(v);
    return v;
}

// `Plane(normal, point).projectVector(v)`: through the matrix `I - n n^T`, row by row.
inline godot::Vector3 ogre_project(const godot::Vector3 &n, const godot::Vector3 &v) {
    const float m00 = 1.0f - n.x * n.x, m01 = -n.x * n.y, m02 = -n.x * n.z;
    const float m10 = -n.y * n.x, m11 = 1.0f - n.y * n.y, m12 = -n.y * n.z;
    const float m20 = -n.z * n.x, m21 = -n.z * n.y, m22 = 1.0f - n.z * n.z;
    return godot::Vector3(m00 * v.x + m01 * v.y + m02 * v.z, m10 * v.x + m11 * v.y + m12 * v.z,
                          m20 * v.x + m21 * v.y + m22 * v.z);
}

// `Quaternion(Radian(angle), UNIT_Y) * v`: Ogre's `FromAngleAxis` and its nVidia-SDK rotation.
inline godot::Vector3 ogre_rotate_y(float angle, const godot::Vector3 &v) {
    const float half = static_cast<float>(0.5 * angle);
    const float s = std::sin(half);
    const godot::Vector3 q(0.0f, s, 0.0f);
    const float w = std::cos(half);
    godot::Vector3 uv = q.cross(v);
    godot::Vector3 uuv = q.cross(uv);
    uv *= (2.0f * w);
    uuv *= 2.0f;
    return v + uv + uuv;
}

} // namespace rorgd
