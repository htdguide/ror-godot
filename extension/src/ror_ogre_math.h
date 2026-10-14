#pragma once

#include <godot_cpp/variant/vector3.hpp>

#include <cmath>
#include <limits>

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

// `Vector3 / s`: Ogre multiplies by `1.0f / s`, which is not the same as dividing when 1/s is
// inexact.
inline godot::Vector3 ogre_div(const godot::Vector3 &v, float s) {
    const float inv = 1.0f / s;
    return godot::Vector3(inv * v.x, inv * v.y, inv * v.z);
}

// Ogre 1.11's `PI` and its degree-radian factors, all Reals.
inline float ogre_pi() { return static_cast<float>(4.0 * std::atan(1.0)); }
inline float ogre_deg2rad() { return ogre_pi() / 180.0f; }

// `Quaternion(Degree(degrees), axis) * v`: `FromAngleAxis` (half the angle as `0.5 * Radian`, a
// Real) and the nVidia-SDK rotation.
inline godot::Vector3 ogre_rotate_degrees(float degrees, const godot::Vector3 &axis, const godot::Vector3 &v) {
    const float radians = degrees * ogre_deg2rad();
    const float half = 0.5f * radians;
    const float s = std::sin(half);
    const float w = std::cos(half);
    const godot::Vector3 q(s * axis.x, s * axis.y, s * axis.z);
    godot::Vector3 uv = q.cross(v);
    godot::Vector3 uuv = q.cross(uv);
    uv *= (2.0f * w);
    uuv *= 2.0f;
    return v + uv + uuv;
}

// An Ogre 1.11 `Quaternion`: `Quaternion(Degree, axis)` (`FromAngleAxis`), the product
// (OgreQuaternion.cpp) and the nVidia-SDK rotation of a vector.
struct OgreQuat {
    float w, x, y, z;
};
inline OgreQuat ogre_quat(float degrees, const godot::Vector3 &axis) {
    const float half = 0.5f * (degrees * ogre_deg2rad());
    const float s = std::sin(half);
    return {std::cos(half), s * axis.x, s * axis.y, s * axis.z};
}
inline OgreQuat ogre_mul(const OgreQuat &a, const OgreQuat &b) {
    return {a.w * b.w - a.x * b.x - a.y * b.y - a.z * b.z, a.w * b.x + a.x * b.w + a.y * b.z - a.z * b.y,
            a.w * b.y + a.y * b.w + a.z * b.x - a.x * b.z, a.w * b.z + a.z * b.w + a.x * b.y - a.y * b.x};
}
inline godot::Vector3 ogre_rotate(const OgreQuat &q, const godot::Vector3 &v) {
    const godot::Vector3 qvec(q.x, q.y, q.z);
    godot::Vector3 uv = qvec.cross(v);
    godot::Vector3 uuv = qvec.cross(uv);
    uv *= (2.0f * q.w);
    uuv *= 2.0f;
    return v + uv + uuv;
}

// Ogre 1.11's `godot::Vector3::getRotationTo` (Sam Hocevar's "quaternion from two vectors") followed by
// `Quaternion::ToAngleAxis`, as `FlexAirfoil::updateForces` uses them: the angle in degrees and
// the axis.
inline void ogre_rotation_angle_axis(const godot::Vector3 &from, const godot::Vector3 &dest, float &degrees, godot::Vector3 &axis) {
    float w = 1.0f, x = 0.0f, y = 0.0f, z = 0.0f;
    const float a = std::sqrt(static_cast<float>(from.length_squared()) * static_cast<float>(dest.length_squared()));
    float b = a + static_cast<float>(dest.dot(from));
    if (!(std::abs(b - 2 * a) <= std::numeric_limits<float>::epsilon() || a == 0)) {
        godot::Vector3 c;
        if (b < 1e-06f * a) {
            b = 0.0f;
            c = std::abs(static_cast<float>(from.x)) > std::abs(static_cast<float>(from.z)) ? godot::Vector3(-from.y, from.x, 0.0f)
                                                                                           : godot::Vector3(0.0f, -from.z, from.y);
        } else {
            c = from.cross(dest);
        }
        w = b;
        x = c.x;
        y = c.y;
        z = c.z;
        const float len = std::sqrt(w * w + x * x + y * y + z * z);
        const float s = 1.0f / len;
        w *= s;
        x *= s;
        y *= s;
        z *= s;
    }
    const float sqr = x * x + y * y + z * z;
    float radians = 0.0f;
    if (sqr > 0.0) {
        // `Math::ACos`, then `2.0 * Radian`, the 2 a Real.
        const float acos_w = (-1.0 < w) ? (w < 1.0 ? std::acos(w) : 0.0f) : static_cast<float>(4.0 * std::atan(1.0));
        radians = 2.0f * acos_w;
        const float inv = 1.0f / std::sqrt(sqr);
        axis = godot::Vector3(x * inv, y * inv, z * inv);
    } else {
        axis = godot::Vector3(1.0f, 0.0f, 0.0f);
    }
    const float pi = static_cast<float>(4.0 * std::atan(1.0));
    degrees = radians * (180.0f / pi);
}


} // namespace rorgd
